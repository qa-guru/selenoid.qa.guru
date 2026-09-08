#!/usr/bin/env python3
"""Selenoid edge on selenoid.qa.guru: public UI, basic auth on machines.

UI is anonymous (guest hubAuth in the product). No oauth2-proxy, no redirect to
Keycloak. /wd/hub stays htpasswd. Prometheus stays loopback on Box2.

  python3 deploy/edge.py apply-nginx
  python3 deploy/edge.py uninstall-proxy
  python3 deploy/edge.py verify
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import shlex
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

try:
    import certifi
except ImportError:
    certifi = None  # type: ignore[assignment]

SELENOID_URL = os.environ.get("SELENOID_URL", "https://selenoid.qa.guru").rstrip("/")
BOX1 = os.environ.get("SELENOID_SSH", "selenoid-prod")
BOX2 = os.environ.get("PROMETHEUS_SSH", "box2-ci")
DEPLOY_DIR = Path(__file__).resolve().parent
NGINX_SRC = DEPLOY_DIR / "nginx-selenoid.conf"
STUDENT_HUB = ("user1", "1234")
PROXY_COMPOSE = "/opt/oauth2-proxy/docker-compose.yml"
FORBIDDEN_DIR = "/var/www/selenoid-auth"


def ssl_ctx() -> ssl.SSLContext:
    cafile = certifi.where() if certifi is not None else None
    ctx = ssl.create_default_context(cafile=cafile)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    return ctx


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


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ARG002
        return None


def http_status(url: str, *, auth: tuple[str, str] | None = None) -> tuple[int, dict[str, str]]:
    hdrs: dict[str, str] = {}
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
    except (urllib.error.URLError, TimeoutError):
        return 0, {}


def http_body(url: str, limit: int = 8000) -> tuple[int, dict[str, str], str]:
    opener = urllib.request.build_opener(
        urllib.request.HTTPSHandler(context=ssl_ctx()),
        _NoRedirect(),
    )
    req = urllib.request.Request(url, method="GET")
    try:
        with opener.open(req, timeout=20) as resp:
            raw = resp.read(limit)
            return resp.status, {k.lower(): v for k, v in resp.headers.items()}, raw.decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        raw = exc.read(limit)
        return exc.code, {k.lower(): v for k, v in exc.headers.items()}, raw.decode("utf-8", "replace")
    except (urllib.error.URLError, TimeoutError):
        return 0, {}, ""


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
    source = NGINX_SRC.read_text(encoding="utf-8")
    ui = source.split("location / {", 1)[1].split("server {", 1)[0]
    if "auth_request" in ui or "/oauth2/" in ui:
        raise SystemExit("nginx source still has oauth2-proxy on location /")
    if "auth_request" in source.split("location ^~ /wd/hub", 1)[1].split("location ", 1)[0]:
        raise SystemExit("nginx source must not put auth_request on /wd/hub")
    live = ssh(BOX1, "sudo cat /etc/nginx/sites-available/selenoid")
    conf = inject_ssl(live, steal_public_map(live, source))
    stamp = time.strftime("%Y%m%d-%H%M%S")
    with tempfile.TemporaryDirectory(prefix="nginx-selenoid.") as td:
        local = Path(td) / "nginx.conf"
        local.write_text(conf, encoding="utf-8")
        os.chmod(local, 0o600)
        remote_tmp = ssh(BOX1, 'mktemp -p "$HOME" nginx-selenoid.XXXXXX').strip()
        if (
            not remote_tmp.startswith("/")
            or "\n" in remote_tmp
            or "\r" in remote_tmp
            or ".." in remote_tmp.split("/")
        ):
            raise SystemExit(f"unexpected mktemp path: {remote_tmp!r}")
        scp_to(BOX1, local, remote_tmp)
        remote_q = shlex.quote(remote_tmp)
        script = f"""
set -euo pipefail
trap 'rm -f {remote_q}' EXIT
sudo cp /etc/nginx/sites-available/selenoid /etc/nginx/sites-available/selenoid.bak-public-ui-{stamp}
sudo cp {remote_q} /etc/nginx/sites-available/selenoid
if ! sudo nginx -t; then
  sudo cp /etc/nginx/sites-available/selenoid.bak-public-ui-{stamp} /etc/nginx/sites-available/selenoid
  sudo nginx -t
  echo "nginx -t failed, restored backup" >&2
  exit 1
fi
sudo systemctl reload nginx
echo OK
"""
        out = ssh(BOX1, script).strip()
    print(json.dumps({"ok": True, "backup": f"selenoid.bak-public-ui-{stamp}", "reload": out}, indent=2))
    return 0


def cmd_uninstall_proxy() -> int:
    down = ssh(
        BOX1,
        f"if sudo test -f {PROXY_COMPOSE}; then sudo docker compose -f {PROXY_COMPOSE} down; echo down; else echo absent; fi",
    ).strip()
    ping = ssh(BOX1, "curl -sf -o /dev/null -w '%{http_code}' --max-time 2 http://127.0.0.1:4180/ping || echo 000").strip()
    ssh(
        BOX1,
        f"sudo rm -f {FORBIDDEN_DIR}/403.html; sudo rmdir {FORBIDDEN_DIR} 2>/dev/null || true",
        check=False,
    )
    print(json.dumps({"compose": down, "ping": ping}, indent=2))
    if ping == "200":
        raise SystemExit("oauth2-proxy still answers /ping on :4180")
    return 0


def cmd_verify() -> int:
    checks: list[tuple[str, bool, str]] = []

    def check(name: str, ok: bool, detail: str = "") -> None:
        checks.append((name, bool(ok), detail))

    ui, ui_h, ui_body = http_body(f"{SELENOID_URL}/")
    loc = ui_h.get("location", "")
    check("UI anonymous 200", ui == 200, str(ui))
    check("UI does not redirect to IdP", "auth.qa.guru" not in loc and "/oauth2/" not in loc, loc[:80])
    check("UI is Selenoid, not Keycloak", "kc-form-login" not in ui_body, ui_body[:80].replace("\n", " "))
    hub_anon, hub_h = http_status(f"{SELENOID_URL}/wd/hub/status")
    check("/wd/hub anonymous 401", hub_anon == 401, str(hub_anon))
    check("/wd/hub WWW-Authenticate Basic", "basic" in hub_h.get("www-authenticate", "").lower(), hub_h.get("www-authenticate", ""))
    hub_ok, _ = http_status(f"{SELENOID_URL}/wd/hub/status", auth=STUDENT_HUB)
    check("/wd/hub user1 still 200", hub_ok == 200, str(hub_ok))
    st, _ = http_status(f"{SELENOID_URL}/status")
    check("/status public", st == 200, str(st))
    ui_st, _ = http_status(f"{SELENOID_URL}/ui/status")
    check("/ui/status public", ui_st == 200, str(ui_st))
    listen = ssh(BOX2, "ss -lntp | grep '127.0.0.1:9091' || true")
    check("Prometheus loopback :9091", "127.0.0.1:9091" in listen, listen.strip()[:80])
    # Prometheus speaks HTTP; a 2xx here means :9091 leaked past the firewall.
    prometheus_public = os.environ.get("PROMETHEUS_PUBLIC_IP", "89.248.193.83")
    pub, _ = http_status(f"http://{prometheus_public}:9091/-/healthy")  # NOSONAR python:S5332
    check("Prometheus not on the internet", pub == 0, str(pub))
    ping = ssh(BOX1, "curl -sf -o /dev/null -w '%{http_code}' --max-time 2 http://127.0.0.1:4180/ping || echo 000").strip()
    check("oauth2-proxy gone", ping != "200", ping)

    width = max(len(n) for n, _, _ in checks)
    for name, ok, detail in checks:
        print(f"{'ok  ' if ok else 'FAIL'}  {name.ljust(width)}  {detail}".rstrip())
    failed = [n for n, ok, _ in checks if not ok]
    print(f"\n{len(checks) - len(failed)}/{len(checks)} checks passed")
    return 1 if failed else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=("apply-nginx", "uninstall-proxy", "verify"))
    args = parser.parse_args()
    dispatch = {
        "apply-nginx": cmd_apply_nginx,
        "uninstall-proxy": cmd_uninstall_proxy,
        "verify": cmd_verify,
    }
    return dispatch[args.command]()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except urllib.error.HTTPError as exc:
        print(f"HTTP {exc.code} {exc.url} {exc.read()[:300]!r}", file=sys.stderr)
        raise
