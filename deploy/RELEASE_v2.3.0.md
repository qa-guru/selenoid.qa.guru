# Release v2.3.0 — prod selenoid.qa.guru

**Дата:** 13 июля 2026  
**Предыдущий:** [v2.2.1](RELEASE_v2.2.1.md) (stack semver align)  
**Stack:** hub + UI + cm → **v2.3.0**  
**Pin ветка стека:** `selenoid2-1.55-engine29.6-go1.26-react18`

---

## Что обновляется

| Компонент | Версия | Изменение |
|-----------|--------|-----------|
| selenoid (hub) | **v2.3.0** | Docker API `1.45→1.55`, Engine `26.1.x→29.x`, Go 1.26 toolchain |
| selenoid-ui | **v2.3.0** | React 18 + Vite 6 (вместо CRA) + Vitest/RTL component layer |
| cm | **v2.3.0** | Stack semver align; передаёт hub `DOCKER_API_VERSION=1.55` |
| browser-image | image tags | Без изменений (`playwright/1.61.1`, `webdriver/*`) |
| browsers-production.json | — | Без изменений каталога |

Каталог браузеров без изменений: chrome **149.0**, firefox **151.0**, msedge **145.0**, Playwright **1.61.1**.

---

## Хост-предусловие (Window 1 — выполнено)

Prod-хост (тогда Hetzner Robot dedicated, **сейчас** Selectel Box1) уже апгрейднут под toolchain v2.3.0:

| Параметр | v2.2.x | v2.3.0 |
|----------|--------|--------|
| ОС | Debian 10 buster | **Debian 12 bookworm** |
| Docker | 26.1.4 / API 1.45 | **29.6.1 / API 1.55** |

Hub — native-бинарник под systemd (`selenoid-hub.service`), `DOCKER_API_VERSION` **не** пиннится (moby-клиент авто-договаривается с Engine 29.x → API 1.55).

---

## Деплой (Window 2)

```bash
# из dev/scripts (workspace) — precheck GitHub releases + recover-selenoid
./dev/scripts/deploy-v230.sh

# или напрямую на сервере из клона
SELENOID_VERSION=v2.3.0 SELENOID_UI_VERSION=v2.3.0 CM_VERSION=v2.3.0 ./deploy/deploy.sh
```

Smoke: `EXPECTED_HUB_VERSION=v2.3.0 EXPECTED_UI_VERSION=v2.3.0 ./deploy/smoke-remote.sh https://selenoid.qa.guru`

**OUT (не трогается):** Jenkins (controller + agents), nginx-конфиг, `jenkins_home`. Docker/Debian откат — отдельная host-операция.

---

## Rollback → v2.2.1

```bash
./dev/scripts/rollback-v221.sh
```

Перепинивает hub/UI/cm на `v2.2.1` через `recover-selenoid.sh` + smoke. Бэкапы на хосте: `/tmp/agents.env.backup-*`, `/tmp/selenoid-config-backup-*.tgz`.

Связанные: [selenoid v2.3.0](https://github.com/qa-guru/selenoid/releases/tag/v2.3.0), [selenoid-ui v2.3.0](https://github.com/qa-guru/selenoid-ui/releases/tag/v2.3.0), [cm v2.3.0](https://github.com/qa-guru/cm/releases/tag/v2.3.0).
