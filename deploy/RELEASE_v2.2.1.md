# Release v2.2.1 — prod selenoid.qa.guru

**Дата:** 10 июля 2026  
**Предыдущий:** [v2.2.0](RELEASE_v2.2.0.md) (WebDriver chrome catalog)  
**Stack:** hub + UI + cm → **v2.2.1**

---

## Что обновляется

| Компонент | Версия | Изменение |
|-----------|--------|-----------|
| selenoid (hub) | **v2.2.1** | Patch: tag=HEAD, ecosystem README |
| selenoid-ui | **v2.2.1** | Patch: tag=HEAD, ecosystem README |
| cm | **v2.2.1** | Stack semver align (docs) |
| browser-image | image tags | Без изменений (`playwright/1.61.1`, `webdriver/*`) |
| browsers-production.json | — | Без изменений |

Runtime/catalog без изменений относительно v2.2.0 pin.

---

## Деплой

```bash
# GitHub Actions (рекомендуется)
# Actions → deploy → Run workflow → version: v2.2.1

# или на сервере
SELENOID_VERSION=v2.2.1 SELENOID_UI_VERSION=v2.2.1 CM_VERSION=v2.2.1 ./deploy/deploy.sh
```

Smoke: `./deploy/smoke-remote.sh https://selenoid.qa.guru`

Связанные: [selenoid v2.2.1](https://github.com/qa-guru/selenoid/releases/tag/v2.2.1), [selenoid-ui v2.2.1](https://github.com/qa-guru/selenoid-ui/releases/tag/v2.2.1), [cm v2.2.1](https://github.com/qa-guru/cm/releases/tag/v2.2.1).
