# Release pin — hub v3.0.6 + UI v3.0.16 + cm v3.0.2

**Дата:** 30 июля 2026  
**Stack pins:** hub **v3.0.6** · UI **v3.0.16** · cm **v3.0.2**

---

## Что обновляется

| Компонент | Версия | Изменение |
|-----------|--------|-----------|
| selenoid (hub) | **v3.0.6** | Playwright manual UI: bootstrap CDP page before HAR attach; metadata HAR linking in finished sessions |
| selenoid-ui | **v3.0.16** | Capabilities Create Session navigates when Playwright session has custom name; Vite entry `index.tsx` |
| cm | **v3.0.2** | без изменений |

Fixes manual Capabilities path: enableHar + Create Session (WebDriver + Playwright) → HAR icon in Finished sessions + HarViewer.

---

## Деплой

```bash
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.6 -f ui_version=v3.0.16

# или на сервере
SELENOID_VERSION=v3.0.6 SELENOID_UI_VERSION=v3.0.16 CM_VERSION=v3.0.2 \
  ./deploy/deploy.sh
```

Smoke public:

```bash
EXPECTED_HUB_VERSION=v3.0.6 EXPECTED_UI_VERSION=v3.0.16 \
  ./deploy/smoke-remote.sh https://selenoid.qa.guru
```

E2e manual HAR (selenoid-tests):

```bash
SELENOID_TEST_ENV=selenoid_qa_guru_e2e go test -v -p 1 -run TestUiManualHar ./tests/e2e/ui/...
```

Связанные: [selenoid v3.0.6](https://github.com/qa-guru/selenoid/releases/tag/v3.0.6), [selenoid-ui v3.0.16](https://github.com/qa-guru/selenoid-ui/releases/tag/v3.0.16).
