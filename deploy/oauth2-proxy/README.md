# oauth2-proxy — Selenoid UI (class B)

OIDC к [auth.qa.guru](https://auth.qa.guru), nginx `auth_request`. Не SAML. Cookie — host-only `selenoid.qa.guru`, не `.qa.guru`.

Prometheus в этом окне **не** получает vhost: остаётся loopback на Box2 (`127.0.0.1:9091`), UI — Grafana.

**P3b — что видит человек.** Единственная страница входа — Keycloak. `--skip-provider-button` отправляет `/oauth2/sign_in` сразу к IdP, `--display-htpasswd-form=false` убирает публичную форму break-glass, `--footer=-` — версию proxy. Сам break-glass не тронут: htpasswd проверяется по заголовку `Authorization: Basic`, форма для этого не нужна (`verify` и `break-glass` так и работали). Кто вошёл, но не в `/staff`, получает [`403.html`](403.html) вместо встроенной страницы nginx; кнопка «Войти другим аккаунтом» гасит и сессию Keycloak, поэтому у клиента прописан post logout redirect.

```bash
python3 deploy/edge.py inventory
python3 deploy/edge.py ensure-idp-client
python3 deploy/edge.py install-proxy
python3 deploy/edge.py apply-nginx
python3 deploy/edge.py login-check
python3 deploy/edge.py verify
python3 deploy/edge.py break-glass
```

Секреты: `~/.config/selenoid/oauth2-proxy.env` (ноутбук) и `/etc/oauth2-proxy/` на Box1. Не git, не Vault.
