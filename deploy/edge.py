#!/usr/bin/env python3
"""P3 — class B edge: oauth2-proxy + nginx auth_request on selenoid.qa.guru.

Prometheus stays loopback on Box2 (decision of this window). Secrets stay in
~/.config (mode 600). Nothing here is printed.

  python3 deploy/edge.py inventory
  python3 deploy/edge.py ensure-idp-client
  python3 deploy/edge.py install-proxy
  python3 deploy/edge.py apply-nginx
  python3 deploy/edge.py login-check
  python3 deploy/edge.py verify
  python3 deploy/edge.py break-glass
"""
from __future__ import annotations

import argparse
import base64
import html
import json
import os
import re
import secrets
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from http.cookiejar import CookieJar
from pathlib import Path
from typing import Any

try:
    import certifi
except ImportError:
    certifi = None  # type: ignore[assignment]

SELENOID_URL = os.environ.get("SELENOID_URL", "https://selenoid.qa.guru").rstrip("/")
AUTH_URL = os.environ.get("AUTH_URL", "https://auth.qa.guru").rstrip("/")
REALM = os.environ.get("REALM", "qaguru")
CLIENT_ID = "oauth2-proxy"
BOX1 = os.environ.get("SELENOID_SSH", "selenoid-prod")
BOX2 = os.environ.get("PROMETHEUS_SSH", "box2-ci")
AUTH_SSH = os.environ.get("AUTH_SSH", "auth-qa-guru")
AUTH_ENV_FILE = Path(os.environ.get("AUTH_ENV", Path.home() / ".config/auth-qa-guru/keycloak.env"))
PILOT_ENV_FILE = Path(os.environ.get("PILOT_ENV", Path.home() / ".config/auth-qa-guru/pilot.env"))
PROXY_ENV_FILE = Path(os.environ.get("OAUTH2_PROXY_ENV", Path.home() / ".config/selenoid/oauth2-proxy.env"))
INV_DIR = Path.home() / ".config/selenoid/p3-inventory"
DEPLOY_DIR = Path(__file__).resolve().parent
NGINX_SRC = DEPLOY_DIR / "nginx-selenoid.conf"
COMPOSE_SRC = DEPLOY_DIR / "oauth2-proxy" / "docker-compose.yml"
STUDENT_HUB = ("user1", "1234")
BREAKGLASS_USER = "breakglass"
ALLOWED_GROUP = "/staff"

GROUPS_MAPPER = {
    "name": "groups",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-group-membership-mapper",
    "config": {
        "full.path": "true",
        "claim.name": "groups",
        "id.token.claim": "true",
        "access.token.claim": "true",
        "introspection.token.claim": "true",
        "userinfo.token.claim": "true",
    },
}


def ssl_ctx() -> ssl.SSLContext:
    if certifi is not None:
        return ssl.create_default_context(cafile=certifi.where())
    return ssl.create_default_context()


def load_kv(path: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    if not path.is_file():
        return env
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        env[key.strip()] = value.strip()
    return env


def write_kv(path: Path, env: dict[str, str], header: str) -> None:
    path.parent.mkdir(mode=0o700, exist_ok=True)
    lines = [header.rstrip(), ""]
    for key, value in env.items():
        lines.append(f"{key}={value}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    path.chmod(0o600)


def upsert_kv(path: Path, key: str, value: str) -> None:
    env = load_kv(path)
    if env.get(key) == value:
        return
    if path.is_file():
        text = path.read_text(encoding="utf-8")
        pattern = re.compile(rf"^{re.escape(key)}=.*$", re.M)
        if pattern.search(text):
            path.write_text(pattern.sub(f"{key}={value}", text, count=1), encoding="utf-8")
        else:
            with path.open("a", encoding="utf-8") as fh:
                fh.write(f"\n{key}={value}\n")
        path.chmod(0o600)
        return
    write_kv(path, {key: value}, f"# {path.name}")


def ssh(host: str, script: str, *, stdin: bytes | None = None, check: bool = True) -> str:
    proc = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", host, script],
        input=stdin,
        capture_output=True,
        check=False,
    )
    if check and proc.returncode != 0:
        err = (proc.stderr or proc.stdout).decode("utf-8", "replace")[:500]
        raise SystemExit(f"ssh {host} failed: {err}")
    return (proc.stdout or b"").decode("utf-8", "replace")


def scp_to(host: str, src: Path, dest: str) -> None:
    proc = subprocess.run(
        ["scp", "-o", "BatchMode=yes", str(src), f"{host}:{dest}"],
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        raise SystemExit(f"scp {src} -> {host}:{dest} failed: {proc.stderr.decode()[:400]}")


def http_json(url: str, *, token: str | None = None, data: bytes | None = None, method: str = "GET", json_body: Any = None) -> Any:
    headers: dict[str, str] = {}
    body = data
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if json_body is not None:
        body = json.dumps(json_body).encode()
        headers["Content-Type"] = "application/json"
        method = method if method != "GET" else "POST"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30, context=ssl_ctx()) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"{method} {url} -> {exc.code} {exc.read()[:300]!r}") from exc


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ARG002
        return None


def http_status(url: str, *, auth: tuple[str, str] | None = None, headers: dict[str, str] | None = None) -> tuple[int, dict[str, str]]:
    hdrs = dict(headers or {})
    if auth:
        token = base64.b64encode(f"{auth[0]}:{auth[1]}".encode()).decode()
        hdrs["Authorization"] = f"Basic {token}"
    opener = urllib.request.build_opener(
        urllib.request.HTTPSHandler(context=ssl_ctx()),
        _NoRedirect(),
    )
    req = urllib.request.Request(url, headers=hdrs, method="GET")
    try:
        with opener.open(req, timeout=20) as resp:
            return resp.status, {k.lower(): v for k, v in resp.headers.items()}
    except urllib.error.HTTPError as exc:
        return exc.code, {k.lower(): v for k, v in exc.headers.items()}
    except urllib.error.URLError:
        return 0, {}
    except TimeoutError:
        return 0, {}


def keycloak_token(env: dict[str, str]) -> str:
    form = urllib.parse.urlencode(
        {
            "client_id": "admin-cli",
            "grant_type": "password",
            "username": env["KC_BOOTSTRAP_ADMIN_USERNAME"],
            "password": env["KC_BOOTSTRAP_ADMIN_PASSWORD"],
        }
    ).encode()
    data = http_json(f"{AUTH_URL}/realms/master/protocol/openid-connect/token", data=form, method="POST")
    return data["access_token"]


def kc(method: str, path: str, token: str, body: Any = None) -> Any:
    return http_json(f"{AUTH_URL}{path}", token=token, json_body=body, method=method)


def client_payload(secret: str) -> dict[str, Any]:
    return {
        "clientId": CLIENT_ID,
        "name": "oauth2-proxy — class B edge (Selenoid UI)",
        "description": "Класс B, nginx auth_request. Cookie host-only. Prometheus loopback — без второго vhost.",
        "enabled": True,
        "protocol": "openid-connect",
        "publicClient": False,
        "secret": secret,
        "standardFlowEnabled": True,
        "implicitFlowEnabled": False,
        "directAccessGrantsEnabled": False,
        "serviceAccountsEnabled": False,
        "clientAuthenticatorType": "client-secret",
        "redirectUris": [f"{SELENOID_URL}/oauth2/callback"],
        "webOrigins": [SELENOID_URL],
        "protocolMappers": [GROUPS_MAPPER],
    }


def rand_secret() -> str:
    return secrets.token_urlsafe(24)


def cookie_secret() -> str:
    return base64.urlsafe_b64encode(secrets.token_bytes(32)).decode()


def htpasswd_line(user: str, password: str) -> str:
    for args in (["htpasswd", "-nbB", user, password], ["htpasswd", "-nb", user, password]):
        proc = subprocess.run(args, capture_output=True, text=True)
        if proc.returncode == 0 and ":" in proc.stdout:
            return proc.stdout.strip().splitlines()[0]
    hashed = subprocess.check_output(["openssl", "passwd", "-apr1", password], text=True).strip()
    return f"{user}:{hashed}"


def proxy_env() -> dict[str, str]:
    env = load_kv(PROXY_ENV_FILE)
    if not env.get("OAUTH2_PROXY_CLIENT_SECRET") or not env.get("OAUTH2_PROXY_COOKIE_SECRET") or not env.get("BREAKGLASS_PASSWORD"):
        raise SystemExit(f"missing secrets in {PROXY_ENV_FILE} — run ensure-idp-client first")
    return env


# ---------------------------------------------------------------------------
# inventory
# ---------------------------------------------------------------------------


def cmd_inventory() -> int:
    INV_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    ui_code, ui_hdrs = http_status(f"{SELENOID_URL}/")
    hub_anon, hub_hdrs = http_status(f"{SELENOID_URL}/wd/hub/status")
    hub_ok, _ = http_status(f"{SELENOID_URL}/wd/hub/status", auth=STUDENT_HUB)
    status_code, _ = http_status(f"{SELENOID_URL}/status")
    names = [n for n in ssh(BOX1, "sudo awk -F: '{print $1}' /etc/nginx/selenoid.htpasswd").split() if n]
    prom_listen = ssh(BOX2, "ss -lntp | grep -E ':9091' || true").strip()
    prom_public, _ = http_status("http://89.248.193.83:9091/-/healthy")
    payload = {
        "when": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "ui": {
            "url": f"{SELENOID_URL}/",
            "anonymous_status": ui_code,
            "www_authenticate": ui_hdrs.get("www-authenticate", ""),
            "note": "P3 start: UI was public (200, no basic). Plan text 'UI за basic auth' was stale.",
        },
        "wd_hub": {
            "anonymous_status": hub_anon,
            "www_authenticate": hub_hdrs.get("www-authenticate", ""),
            "student_user1_status": hub_ok,
            "keep": "basic auth / tokens — never oauth2-proxy",
        },
        "public_no_auth": ["/status", "/ui/status", "/hub/ping", "/hub/status"],
        "machine_basic": ["/wd/hub", "/logs/", "/vnc/", "/error", ":4445"],
        "machine_access_key": ["/playwright/"],
        "htpasswd_users": names,
        "htpasswd_count": len(names),
        "username_map": [
            {"current": name, "handle": name if name not in {"user1", "qa_engineer"} else None, "kind": "machine htpasswd, not Keycloak"}
            for name in names
        ],
        "ci_plan": "htpasswd / accessKey / :4445 unchanged. No reissue. Do not put student passwords on oauth2-proxy.",
        "prometheus": {
            "listen": prom_listen,
            "public_http": prom_public,
            "decision": "leave loopback on Box2 127.0.0.1:9091; UI is Grafana; do not publish a vhost",
        },
        "groups": {"ui": ["/staff"], "students": "no — no Keycloak accounts yet except student-pilot; machine traffic unchanged"},
    }
    dest = INV_DIR / ("after.json" if (INV_DIR / "before.json").is_file() else "before.json")
    dest.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    dest.chmod(0o600)
    print(
        json.dumps(
            {
                "ok": True,
                "wrote": str(dest),
                "ui_anon": ui_code,
                "wd_hub_anon": hub_anon,
                "htpasswd_users": names,
                "prometheus_public": prom_public,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


# ---------------------------------------------------------------------------
# Keycloak client
# ---------------------------------------------------------------------------


def _put_client(token: str, secret: str) -> str:
    found = kc("GET", f"/admin/realms/{REALM}/clients?clientId={CLIENT_ID}", token) or []
    payload = client_payload(secret)
    if found:
        cid = found[0]["id"]
        body = {k: v for k, v in payload.items() if k != "protocolMappers"}
        body["id"] = cid
        kc("PUT", f"/admin/realms/{REALM}/clients/{cid}", token, body)
        mappers = kc("GET", f"/admin/realms/{REALM}/clients/{cid}/protocol-mappers/models", token) or []
        if not any(m.get("name") == "groups" for m in mappers):
            kc("POST", f"/admin/realms/{REALM}/clients/{cid}/protocol-mappers/models", token, GROUPS_MAPPER)
        return "updated"
    kc("POST", f"/admin/realms/{REALM}/clients", token, payload)
    return "created"


def cmd_ensure_idp_client() -> int:
    auth_env = load_kv(AUTH_ENV_FILE)
    if not auth_env.get("KC_BOOTSTRAP_ADMIN_USERNAME"):
        raise SystemExit(f"missing bootstrap admin in {AUTH_ENV_FILE}")
    stand = "localhost" in AUTH_URL
    if stand:
        secret = auth_env.get("KC_CLIENT_SECRET_OAUTH2_PROXY") or rand_secret()
        upsert_kv(AUTH_ENV_FILE, "KC_CLIENT_SECRET_OAUTH2_PROXY", secret)
        token = keycloak_token(auth_env)
        action = _put_client(token, secret)
        print(json.dumps({"ok": True, "client": CLIENT_ID, "action": action, "target": "stand"}, indent=2))
        return 0

    existing_proxy = load_kv(PROXY_ENV_FILE)
    secret = existing_proxy.get("OAUTH2_PROXY_CLIENT_SECRET") or rand_secret()
    cookie = existing_proxy.get("OAUTH2_PROXY_COOKIE_SECRET") or cookie_secret()
    bg_pass = existing_proxy.get("BREAKGLASS_PASSWORD") or rand_secret()
    write_kv(
        PROXY_ENV_FILE,
        {
            "OAUTH2_PROXY_CLIENT_ID": CLIENT_ID,
            "OAUTH2_PROXY_CLIENT_SECRET": secret,
            "OAUTH2_PROXY_COOKIE_SECRET": cookie,
            "BREAKGLASS_USER": BREAKGLASS_USER,
            "BREAKGLASS_PASSWORD": bg_pass,
        },
        "# oauth2-proxy + UI break-glass. Not git. Not Vault. Mode 600.",
    )
    upsert_kv(AUTH_ENV_FILE, "KC_CLIENT_SECRET_OAUTH2_PROXY", secret)
    token = keycloak_token(auth_env)
    action = _put_client(token, secret)
    remote = ssh(AUTH_SSH, "sudo grep -c '^KC_CLIENT_SECRET_OAUTH2_PROXY=' /etc/keycloak/keycloak.env || true").strip()
    if remote in {"", "0"}:
        ssh(
            AUTH_SSH,
            "sudo tee -a /etc/keycloak/keycloak.env >/dev/null && sudo chmod 600 /etc/keycloak/keycloak.env",
            stdin=f"\nKC_CLIENT_SECRET_OAUTH2_PROXY={secret}\n".encode(),
        )
    print(json.dumps({"ok": True, "client": CLIENT_ID, "action": action, "env": str(PROXY_ENV_FILE)}, indent=2))
    return 0


# ---------------------------------------------------------------------------
# install proxy on Box1
# ---------------------------------------------------------------------------


def cmd_install_proxy() -> int:
    env = proxy_env()
    container_env = (
        f"OAUTH2_PROXY_CLIENT_ID={CLIENT_ID}\n"
        f"OAUTH2_PROXY_CLIENT_SECRET={env['OAUTH2_PROXY_CLIENT_SECRET']}\n"
        f"OAUTH2_PROXY_COOKIE_SECRET={env['OAUTH2_PROXY_COOKIE_SECRET']}\n"
    ).encode()
    htpasswd = htpasswd_line(env.get("BREAKGLASS_USER", BREAKGLASS_USER), env["BREAKGLASS_PASSWORD"]).encode() + b"\n"
    ssh(BOX1, "sudo mkdir -p /opt/oauth2-proxy /etc/oauth2-proxy && sudo chmod 755 /etc/oauth2-proxy")
    scp_to(BOX1, COMPOSE_SRC, "/tmp/oauth2-proxy-compose.yml")
    ssh(BOX1, "sudo tee /etc/oauth2-proxy/oauth2-proxy.env >/dev/null && sudo chmod 600 /etc/oauth2-proxy/oauth2-proxy.env", stdin=container_env)
    ssh(BOX1, "sudo tee /etc/oauth2-proxy/htpasswd >/dev/null && sudo chmod 644 /etc/oauth2-proxy/htpasswd", stdin=htpasswd)
    ssh(BOX1, "sudo cp /tmp/oauth2-proxy-compose.yml /opt/oauth2-proxy/docker-compose.yml")
    ssh(BOX1, "sudo docker compose -f /opt/oauth2-proxy/docker-compose.yml pull")
    ssh(BOX1, "sudo docker compose -f /opt/oauth2-proxy/docker-compose.yml up -d")
    ping = ""
    for _ in range(20):
        ping = ssh(BOX1, "curl -sf -o /dev/null -w '%{http_code}' http://127.0.0.1:4180/ping || true").strip()
        if ping == "200":
            break
        time.sleep(2)
    if ping != "200":
        raise SystemExit(f"oauth2-proxy /ping -> {ping!r}")
    print(json.dumps({"ok": True, "ping": ping, "image": "quay.io/oauth2-proxy/oauth2-proxy:v7.15.2"}, indent=2))
    return 0


# ---------------------------------------------------------------------------
# nginx
# ---------------------------------------------------------------------------


def steal_public_map(live: str, template: str) -> str:
    lines = []
    for line in live.splitlines():
        stripped = line.strip()
        if stripped.startswith('"') and stripped.endswith("1;") and "user1" not in stripped and "__SELENOID" not in stripped:
            lines.append(stripped)
    placeholders = [ln for ln in template.splitlines() if "__SELENOID_PUBLIC_ACCESS_KEY" in ln and not ln.lstrip().startswith("#")]
    if len(lines) != len(placeholders):
        raise SystemExit(f"public map mismatch: live {len(lines)} vs template {len(placeholders)}")
    out = []
    i = 0
    for line in template.splitlines():
        if "__SELENOID_PUBLIC_ACCESS_KEY" in line and not line.lstrip().startswith("#"):
            indent = re.match(r"^(\s*)", line)
            pad = indent.group(1) if indent else ""
            out.append(f"{pad}{lines[i]}")
            i += 1
        else:
            out.append(line)
    return "\n".join(out) + "\n"


def inject_ssl(live: str, template: str) -> str:
    ssl_lines: list[str] = []
    seen: set[str] = set()
    for line in live.splitlines():
        if re.search(r"ssl_certificate(_key)? ", line) and not line.strip().startswith("#"):
            if line not in seen:
                seen.add(line)
                ssl_lines.append(line)
    if not ssl_lines:
        raise SystemExit("no ssl_certificate lines on live site")
    out = []
    for line in template.splitlines():
        if "# ssl_certificate ...;" in line:
            out.extend(ssl_lines)
        elif "# ssl_certificate_key ...;" in line:
            continue
        else:
            out.append(line)
    return "\n".join(out) + "\n"


def cmd_apply_nginx() -> int:
    if "auth_request" not in NGINX_SRC.read_text(encoding="utf-8"):
        raise SystemExit("nginx source missing auth_request")
    live = ssh(BOX1, "sudo cat /etc/nginx/sites-available/selenoid")
    conf = inject_ssl(live, steal_public_map(live, NGINX_SRC.read_text(encoding="utf-8")))
    stamp = time.strftime("%Y%m%d-%H%M%S")
    local = Path("/tmp/nginx-selenoid.p3")
    local.write_text(conf, encoding="utf-8")
    scp_to(BOX1, local, "/tmp/nginx-selenoid.p3")
    script = f"""
set -euo pipefail
if ! curl -sf --max-time 3 http://127.0.0.1:4180/ping >/dev/null; then
  echo "oauth2-proxy not healthy on :4180" >&2
  exit 1
fi
sudo cp /etc/nginx/sites-available/selenoid /etc/nginx/sites-available/selenoid.bak-p3-{stamp}
sudo cp /tmp/nginx-selenoid.p3 /etc/nginx/sites-available/selenoid
if ! sudo nginx -t; then
  sudo cp /etc/nginx/sites-available/selenoid.bak-p3-{stamp} /etc/nginx/sites-available/selenoid
  sudo nginx -t
  echo "nginx -t failed, restored backup" >&2
  exit 1
fi
sudo systemctl reload nginx
echo OK
"""
    out = ssh(BOX1, script).strip()
    print(json.dumps({"ok": True, "backup": f"selenoid.bak-p3-{stamp}", "reload": out}, indent=2))
    return 0


# ---------------------------------------------------------------------------
# OIDC login without a browser
# ---------------------------------------------------------------------------


class FormParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.forms: list[dict[str, Any]] = []
        self._current: dict[str, Any] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        ad = {k: (v or "") for k, v in attrs}
        if tag == "form":
            self._current = {"action": ad.get("action", ""), "id": ad.get("id", ""), "inputs": {}}
            self.forms.append(self._current)
        elif tag in {"input", "button"} and self._current is not None:
            name = ad.get("name")
            if name:
                self._current["inputs"][name] = ad.get("value", "")


def parse_forms(page: str) -> list[dict[str, Any]]:
    parser = FormParser()
    parser.feed(page)
    return parser.forms


def oidc_login(username: str, password: str) -> dict[str, Any]:
    jar = CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPSHandler(context=ssl_ctx()),
        urllib.request.HTTPCookieProcessor(jar),
    )
    opener.addheaders = [("User-Agent", "qa-guru-p3-oidc/1.0")]

    def fetch(url: str, data: bytes | None = None) -> tuple[str, int, str]:
        req = urllib.request.Request(url, data=data, method="POST" if data else "GET")
        try:
            with opener.open(req, timeout=45) as resp:
                return resp.geturl(), resp.status, resp.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as exc:
            return exc.geturl() or url, exc.code, exc.read().decode("utf-8", "replace")

    start = f"{SELENOID_URL}/oauth2/start?rd={urllib.parse.quote(SELENOID_URL + '/', safe='')}"
    url, status, page = fetch(start)
    for _ in range(8):
        forms = parse_forms(page)
        login = next((f for f in forms if f.get("id") == "kc-form-login" or "username" in f["inputs"]), None)
        if login and "username" in login["inputs"] and status < 400:
            action = urllib.parse.urljoin(url, html.unescape(login["action"]))
            payload = dict(login["inputs"])
            payload["username"] = username
            payload["password"] = password
            payload.setdefault("credentialId", "")
            url, status, page = fetch(action, urllib.parse.urlencode(payload).encode())
            continue
        if status in {200, 403}:
            break
        if status in {301, 302, 303, 307, 308}:
            break
        break
    cookies = {c.name: c.value for c in jar}
    return {"status": status, "url": url, "cookies": list(cookies), "body_head": re.sub(r"\s+", " ", page)[:240]}


def cmd_login_check() -> int:
    pilot = load_kv(PILOT_ENV_FILE)
    staff_user = pilot.get("PILOT_STAFF_USERNAME", "svasenkov")
    staff_pass = pilot.get("PILOT_STAFF_PASSWORD")
    student_user = pilot.get("PILOT_STUDENT_USERNAME", "student-pilot")
    student_pass = pilot.get("PILOT_STUDENT_PASSWORD")
    if not staff_pass or not student_pass:
        raise SystemExit(f"missing pilot passwords in {PILOT_ENV_FILE}")
    staff = oidc_login(staff_user, staff_pass)
    student = oidc_login(student_user, student_pass)
    staff_ok = staff["status"] == 200
    student_blocked = student["status"] in {403, 401} or "forbidden" in student["body_head"].lower() or "not authorized" in student["body_head"].lower()
    print(json.dumps({"staff": {"user": staff_user, "status": staff["status"], "ok": staff_ok}, "student": {"user": student_user, "status": student["status"], "blocked": student_blocked}}, indent=2))
    if not staff_ok or not student_blocked:
        raise SystemExit("login-check failed")
    return 0


# ---------------------------------------------------------------------------
# verify / break-glass
# ---------------------------------------------------------------------------


def cmd_verify() -> int:
    checks: list[tuple[str, bool, str]] = []

    def check(name: str, ok: bool, detail: str = "") -> None:
        checks.append((name, bool(ok), detail))

    ui, ui_h = http_status(f"{SELENOID_URL}/")
    check("UI anonymous redirects to OIDC", ui in {302, 401, 403}, f"{ui} {ui_h.get('location', '')[:80]}")
    hub_anon, hub_h = http_status(f"{SELENOID_URL}/wd/hub/status")
    check("/wd/hub anonymous 401", hub_anon == 401, str(hub_anon))
    check("/wd/hub WWW-Authenticate Basic", "basic" in hub_h.get("www-authenticate", "").lower(), hub_h.get("www-authenticate", ""))
    hub_ok, _ = http_status(f"{SELENOID_URL}/wd/hub/status", auth=STUDENT_HUB)
    check("/wd/hub user1 still 200", hub_ok == 200, str(hub_ok))
    st, _ = http_status(f"{SELENOID_URL}/status")
    check("/status public", st == 200, str(st))
    ui_st, _ = http_status(f"{SELENOID_URL}/ui/status")
    check("/ui/status public", ui_st == 200, str(ui_st))
    ping = ssh(BOX1, "curl -sf -o /dev/null -w '%{http_code}' http://127.0.0.1:4180/ping").strip()
    check("oauth2-proxy ping", ping == "200", ping)
    listen = ssh(BOX2, "ss -lntp | grep '127.0.0.1:9091' || true")
    check("Prometheus loopback :9091", "127.0.0.1:9091" in listen, listen.strip()[:80])
    pub, _ = http_status("http://89.248.193.83:9091/-/healthy")
    check("Prometheus not on the internet", pub == 0, str(pub))
    env = proxy_env()
    bg, _ = http_status(f"{SELENOID_URL}/", auth=(env.get("BREAKGLASS_USER", BREAKGLASS_USER), env["BREAKGLASS_PASSWORD"]))
    check("break-glass htpasswd reaches UI", bg == 200, str(bg))

    width = max(len(n) for n, _, _ in checks)
    for name, ok, detail in checks:
        print(f"{'ok  ' if ok else 'FAIL'}  {name.ljust(width)}  {detail}".rstrip())
    failed = [n for n, ok, _ in checks if not ok]
    print(f"\n{len(checks) - len(failed)}/{len(checks)} checks passed")
    return 1 if failed else 0


def curl_code(url: str, *, auth: tuple[str, str] | None = None) -> int:
    cmd = ["curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "15"]
    if auth:
        cmd += ["-u", f"{auth[0]}:{auth[1]}"]
    cmd.append(url)
    proc = subprocess.run(cmd, capture_output=True, text=True)
    try:
        return int((proc.stdout or "0").strip() or "0")
    except ValueError:
        return 0


def _docker_keycloak(action: str) -> subprocess.CompletedProcess[str]:
    container = os.environ.get("KEYCLOAK_CONTAINER", "auth-qa-guru-keycloak-1")
    return subprocess.run(
        ["ssh", "-o", "BatchMode=yes", AUTH_SSH, f"sudo docker {action} {container}"],
        check=False,
        capture_output=True,
        text=True,
    )


def cmd_break_glass() -> int:
    env = proxy_env()
    bg_user = env.get("BREAKGLASS_USER", BREAKGLASS_USER)
    bg_pass = env["BREAKGLASS_PASSWORD"]
    before, _ = http_status(f"{SELENOID_URL}/", auth=(bg_user, bg_pass))
    if before != 200:
        raise SystemExit(f"break-glass UI before stop -> {before}")
    print("ok    break-glass UI before stop")
    stop = _docker_keycloak("stop")
    if stop.returncode != 0:
        raise SystemExit(f"failed to stop Keycloak: {stop.stderr or stop.stdout}")
    result = 1
    restarted = False
    ready = False
    try:
        time.sleep(2)
        ui_anon = curl_code(f"{SELENOID_URL}/")
        ui_bg = curl_code(f"{SELENOID_URL}/", auth=(bg_user, bg_pass))
        hub = curl_code(f"{SELENOID_URL}/wd/hub/status", auth=STUDENT_HUB)
        print(json.dumps({"ui_anon": ui_anon, "ui_breakglass": ui_bg, "wd_hub": hub}, indent=2))
        if ui_bg == 200 and hub == 200 and ui_anon != 200:
            print("ok    UI break-glass + /wd/hub while Keycloak is down")
            result = 0
    finally:
        start = _docker_keycloak("start")
        restarted = start.returncode == 0
        if restarted:
            for _ in range(40):
                try:
                    req = urllib.request.Request(f"{AUTH_URL}/realms/{REALM}/.well-known/openid-configuration")
                    with urllib.request.urlopen(req, timeout=10, context=ssl_ctx()) as resp:
                        if resp.status == 200:
                            print("ok    Keycloak back")
                            ready = True
                            break
                except (urllib.error.URLError, TimeoutError, OSError, urllib.error.HTTPError):
                    time.sleep(3)
        if not restarted:
            print("FAIL  Keycloak did not start — ssh auth-qa-guru 'sudo docker start auth-qa-guru-keycloak-1'", file=sys.stderr)
        elif not ready:
            print("FAIL  Keycloak did not become ready", file=sys.stderr)
    if not restarted or not ready:
        return 1
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "command",
        choices=("inventory", "ensure-idp-client", "install-proxy", "apply-nginx", "login-check", "verify", "break-glass"),
    )
    args = parser.parse_args()
    dispatch = {
        "inventory": cmd_inventory,
        "ensure-idp-client": cmd_ensure_idp_client,
        "install-proxy": cmd_install_proxy,
        "apply-nginx": cmd_apply_nginx,
        "login-check": cmd_login_check,
        "verify": cmd_verify,
        "break-glass": cmd_break_glass,
    }
    return dispatch[args.command]()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except urllib.error.HTTPError as exc:
        print(f"HTTP {exc.code} {exc.url} {exc.read()[:300]!r}", file=sys.stderr)
        raise
