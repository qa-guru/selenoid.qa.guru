# Release pin — hub v3.0.4 + UI v3.0.13

**Дата:** 28 июля 2026  
**Stack pins:** hub **v3.0.4** · UI **v3.0.13** · cm **v3.0.1** (без изменений)

---

## Что обновляется

| Компонент | Версия | Изменение |
|-----------|--------|-----------|
| selenoid (hub) | **v3.0.4** | `harContent` meta\|bodies поверх `enableHAR` (default meta) |
| selenoid-ui | **v3.0.13** | Capabilities `harContent` + session UX; HarViewer без регресса meta |
| cm | **v3.0.1** | Без изменений |

---

## Деплой

```bash
# GitHub Actions (явные pins)
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.4 -f ui_version=v3.0.13

# или на сервере (defaults после bump)
SELENOID_VERSION=v3.0.4 SELENOID_UI_VERSION=v3.0.13 CM_VERSION=v3.0.1 \
  ./deploy/deploy.sh
```

Smoke public: `EXPECTED_HUB_VERSION=v3.0.4 EXPECTED_UI_VERSION=v3.0.13 ./deploy/smoke-remote.sh https://selenoid.qa.guru`

HAR content smoke (отдельно, не dual-writer): WD/PW meta + bodies — см. worker Step 5 / MATRIX.

Связанные: [selenoid v3.0.4](https://github.com/qa-guru/selenoid/releases/tag/v3.0.4), [selenoid-ui v3.0.13](https://github.com/qa-guru/selenoid-ui/releases/tag/v3.0.13), [cm v3.0.1](https://github.com/qa-guru/cm/releases/tag/v3.0.1), ADR 009.
