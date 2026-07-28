# Release pin — hub v3.0.5 + UI v3.0.14 + cm v3.0.2

**Дата:** 28 июля 2026  
**Stack pins:** hub **v3.0.5** · UI **v3.0.14** · cm **v3.0.2**

---

## Что обновляется

| Компонент | Версия | Изменение |
|-----------|--------|-----------|
| selenoid (hub) | **v3.0.5** | Go module `github.com/qa-guru/selenoid`; HAR bodies `content.size` fix |
| selenoid-ui | **v3.0.14** | Go module `github.com/qa-guru/selenoid-ui` (embed server) |
| cm | **v3.0.2** | Go module `github.com/qa-guru/cm`; selenoid dep без aerokube replace |

Runtime / WebDriver / Playwright WS без breaking changes.

---

## Деплой

```bash
# GitHub Actions (явные pins)
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.5 -f ui_version=v3.0.14

# или на сервере (defaults после bump)
SELENOID_VERSION=v3.0.5 SELENOID_UI_VERSION=v3.0.14 CM_VERSION=v3.0.2 \
  ./deploy/deploy.sh
```

Smoke public: `EXPECTED_HUB_VERSION=v3.0.5 EXPECTED_UI_VERSION=v3.0.14 ./deploy/smoke-remote.sh https://selenoid.qa.guru`

Связанные: [selenoid v3.0.5](https://github.com/qa-guru/selenoid/releases/tag/v3.0.5), [selenoid-ui v3.0.14](https://github.com/qa-guru/selenoid-ui/releases/tag/v3.0.14), [cm v3.0.2](https://github.com/qa-guru/cm/releases/tag/v3.0.2).
