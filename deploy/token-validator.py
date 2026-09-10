#!/usr/bin/env python3
"""Loopback auth_request backend: Basic handle:selenoidToken → Keycloak attribute.

Bind 127.0.0.1 only. No htpasswd, no file sync. Stdlib only.

    python3 token-validator.py --self-test
    python3 token-validator.py          # KEYCLOAK_* from env / EnvironmentFile
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import ssl
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

ATTR = "selenoidToken"
DEFAULT_BIND = "127.0.0.1"
DEFAULT_PORT = 9082
DEFAULT_TTL = 30
DEFAULT_REALM = "qaguru"
DEFAULT_CLIENT = "svc-selenoid-token"


def ssl_ctx() -> ssl.SSLContext:
    ctx = ssl.create_default_context()
    try:
        import certifi

        ctx.load_verify_locations(certifi.where())
    except Exception:
        pass
    return ctx


CTX = ssl_ctx()


class TtlCache:
    def __init__(self, ttl_s: float) -> None:
        self.ttl_s = ttl_s
        self._data: dict[str, tuple[float, int]] = {}
        self._lock = threading.Lock()

    def get(self, key: str) -> int | None:
        now = time.monotonic()
        with self._lock:
            hit = self._data.get(key)
            if hit is None:
                return None
            expires, value = hit
            if expires <= now:
                self._data.pop(key, None)
                return None
            return value

    def put(self, key: str, value: int) -> None:
        if self.ttl_s <= 0:
            return
        with self._lock:
            self._data[key] = (time.monotonic() + self.ttl_s, value)


def parse_basic(authorization: str) -> tuple[str, str] | None:
    if not authorization:
        return None
    kind, _, rest = authorization.partition(" ")
    if kind.lower() != "basic" or not rest.strip():
        return None
    try:
        raw = base64.b64decode(rest.strip(), validate=True)
        decoded = raw.decode("utf-8")
    except (ValueError, UnicodeDecodeError):
        return None
    if ":" not in decoded:
        return None
    user, _, password = decoded.partition(":")
    if not user or not password:
        return None
    return user, password


def tokens_equal(stored: str, provided: str) -> bool:
    if not stored or not provided:
        return False
    left = stored.encode("utf-8")
    right = provided.encode("utf-8")
    if len(left) != len(right):
        hmac.compare_digest(left, left)
        return False
    return hmac.compare_digest(left, right)


def cache_key(authorization: str) -> str:
    return hashlib.sha256(authorization.encode("utf-8")).hexdigest()


class Keycloak:
    def __init__(self, base_url: str, realm: str, client_id: str, client_secret: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.realm = realm
        self.client_id = client_id
        self.client_secret = client_secret
        self._token = ""
        self._token_exp = 0.0
        self._lock = threading.Lock()

    def _request(
        self,
        url: str,
        *,
        method: str = "GET",
        token: str | None = None,
        form: dict[str, str] | None = None,
        timeout: float = 8.0,
    ) -> tuple[int, Any]:
        data = None
        headers: dict[str, str] = {}
        if form is not None:
            data = urllib.parse.urlencode(form).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        if token:
            headers["Authorization"] = f"Bearer {token}"
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, context=CTX, timeout=timeout) as resp:
                raw = resp.read()
                parsed: Any = json.loads(raw) if raw else None
                return resp.status, parsed
        except urllib.error.HTTPError as exc:
            exc.read()
            return exc.code, None
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
            return 0, None

    def access_token(self) -> str | None:
        now = time.time()
        with self._lock:
            if self._token and now < self._token_exp:
                return self._token
        st, body = self._request(
            f"{self.base_url}/realms/{self.realm}/protocol/openid-connect/token",
            method="POST",
            form={
                "grant_type": "client_credentials",
                "client_id": self.client_id,
                "client_secret": self.client_secret,
            },
        )
        token = (body or {}).get("access_token") if isinstance(body, dict) else None
        if st != 200 or not token:
            sys.stderr.write(f"token-validator: client_credentials HTTP {st}\n")
            return None
        expires = int((body or {}).get("expires_in") or 60)
        with self._lock:
            self._token = str(token)
            self._token_exp = time.time() + max(expires - 30, 15)
        return self._token

    def stored_token(self, username: str) -> str | None | bool:
        """Return stored selenoidToken, None if missing/disabled, False on IdP error."""
        token = self.access_token()
        if not token:
            return False
        q = urllib.parse.urlencode(
            {"username": username, "exact": "true", "briefRepresentation": "false"}
        )
        st, found = self._request(
            f"{self.base_url}/admin/realms/{self.realm}/users?{q}",
            token=token,
        )
        if st in (401, 403):
            sys.stderr.write(f"token-validator: users lookup HTTP {st}\n")
            return False
        if st != 200:
            sys.stderr.write(f"token-validator: users lookup HTTP {st}\n")
            return False
        if not found:
            return None
        user = found[0]
        if user.get("enabled") is False:
            return None
        attrs = user.get("attributes") or {}
        values = attrs.get(ATTR) or []
        if not values and user.get("id"):
            st, full = self._request(
                f"{self.base_url}/admin/realms/{self.realm}/users/{user['id']}",
                token=token,
            )
            if st != 200:
                return False
            values = ((full or {}).get("attributes") or {}).get(ATTR) or []
        if not values:
            return None
        stored = str(values[0] or "")
        return stored or None


def decide(authorization: str, lookup) -> int:
    """204 if handle+token match, 401 if not, 502 if IdP is down."""
    parsed = parse_basic(authorization)
    if parsed is None:
        return 401
    user, provided = parsed
    stored = lookup(user)
    if stored is False:
        return 502
    if not stored or not tokens_equal(str(stored), provided):
        return 401
    return 204


class App:
    def __init__(self, kc: Keycloak, cache: TtlCache) -> None:
        self.kc = kc
        self.cache = cache

    def handle(self, path: str, authorization: str) -> int:
        if path.rstrip("/") == "/health":
            return 204
        if not authorization:
            return 401
        key = cache_key(authorization)
        hit = self.cache.get(key)
        if hit is not None:
            return hit
        status = decide(authorization, self.kc.stored_token)
        if status in (204, 401):
            self.cache.put(key, status)
        return status


def load_settings() -> dict[str, str]:
    bind = (os.environ.get("BIND") or DEFAULT_BIND).strip()
    if bind not in ("127.0.0.1", "::1") and os.environ.get("ALLOW_NON_LOOPBACK") != "1":
        raise SystemExit(f"refusing non-loopback BIND={bind}")
    secret = (os.environ.get("KEYCLOAK_CLIENT_SECRET") or "").strip()
    base = (os.environ.get("KEYCLOAK_BASE_URL") or "").strip()
    if not secret or not base:
        raise SystemExit("KEYCLOAK_BASE_URL and KEYCLOAK_CLIENT_SECRET are required")
    return {
        "bind": bind,
        "port": os.environ.get("PORT") or str(DEFAULT_PORT),
        "ttl": os.environ.get("CACHE_TTL_SECONDS") or str(DEFAULT_TTL),
        "base": base,
        "realm": (os.environ.get("KEYCLOAK_REALM") or DEFAULT_REALM).strip(),
        "client_id": (os.environ.get("KEYCLOAK_CLIENT_ID") or DEFAULT_CLIENT).strip(),
        "secret": secret,
    }


def make_handler(app: App):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt: str, *args: object) -> None:
            sys.stderr.write("token-validator: " + (fmt % args) + "\n")

        def _send(self, status: int) -> None:
            self.send_response(status)
            self.send_header("Content-Length", "0")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()

        def do_GET(self) -> None:  # noqa: N802
            self._send(app.handle(self.path.split("?", 1)[0], self.headers.get("Authorization") or ""))

        do_POST = do_GET  # noqa: N815
        do_HEAD = do_GET  # noqa: N815
        do_PUT = do_GET  # noqa: N815
        do_DELETE = do_GET  # noqa: N815
        do_PATCH = do_GET  # noqa: N815

    return Handler


def self_test() -> int:
    assert parse_basic("") is None
    assert parse_basic("Bearer abc") is None
    blob = base64.b64encode(b"alice:secret-token-value-ok").decode()
    assert parse_basic(f"Basic {blob}") == ("alice", "secret-token-value-ok")
    assert tokens_equal("same-token-value-ok", "same-token-value-ok")
    assert not tokens_equal("same-token-value-ok", "other-token-value-no")
    assert not tokens_equal("short", "longer-token-value")

    def lookup_ok(user: str):
        return "personal-token-value-ok" if user == "alice" else None

    def lookup_down(_user: str):
        return False

    ok = "Basic " + base64.b64encode(b"alice:personal-token-value-ok").decode()
    bad = "Basic " + base64.b64encode(b"alice:wrong-token-value-xx").decode()
    missing = "Basic " + base64.b64encode(b"bob:personal-token-value-ok").decode()
    assert decide(ok, lookup_ok) == 204
    assert decide(bad, lookup_ok) == 401
    assert decide(missing, lookup_ok) == 401
    assert decide("", lookup_ok) == 401
    assert decide(ok, lookup_down) == 502

    class FakeKc:
        def stored_token(self, user: str):
            return lookup_ok(user)

    app = App(FakeKc(), TtlCache(30))  # type: ignore[arg-type]
    assert app.handle("/health", "") == 204
    assert app.handle("/_auth/selenoid-token", "") == 401
    assert app.handle("/_auth/selenoid-token", ok) == 204
    assert app.handle("/_auth/selenoid-token", bad) == 401
    print("OK  token-validator self-test")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if "--self-test" in args:
        return self_test()
    cfg = load_settings()
    app = App(
        Keycloak(cfg["base"], cfg["realm"], cfg["client_id"], cfg["secret"]),
        TtlCache(float(cfg["ttl"])),
    )
    server = ThreadingHTTPServer((cfg["bind"], int(cfg["port"])), make_handler(app))
    sys.stderr.write(f"token-validator listen {cfg['bind']}:{cfg['port']} realm={cfg['realm']}\n")
    try:
        # Loopback auth_request only (BIND refuses non-loopback). Not a public HTTP surface.
        server.serve_forever()  # NOSONAR python:S5332
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
