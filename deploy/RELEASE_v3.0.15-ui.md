# Release pin — UI v3.0.15 (hub v3.0.5 + cm v3.0.2)

**Дата:** 29 июля 2026  
**Stack pins:** hub **v3.0.5** · UI **v3.0.15** · cm **v3.0.2**

---

## Что обновляется

| Компонент | Версия | Изменение |
|-----------|--------|-----------|
| selenoid-ui | **v3.0.15** | Full TypeScript UI (`strict`, `allowJs: false`); Vite bundler retained |
| selenoid (hub) | **v3.0.5** | без изменений |
| cm | **v3.0.2** | без изменений |

UI tooling cut — без breaking wire / protocol changes.

---

## Деплой

```bash
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.5 -f ui_version=v3.0.15

# или на сервере
SELENOID_VERSION=v3.0.5 SELENOID_UI_VERSION=v3.0.15 CM_VERSION=v3.0.2 \
  ./deploy/deploy.sh
```

Smoke public: `EXPECTED_HUB_VERSION=v3.0.5 EXPECTED_UI_VERSION=v3.0.15 ./deploy/smoke-remote.sh https://selenoid.qa.guru`

Связанные: [selenoid-ui v3.0.15](https://github.com/qa-guru/selenoid-ui/releases/tag/v3.0.15).
