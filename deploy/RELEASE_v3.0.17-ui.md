# Release pin — UI v3.0.17 (hub v3.0.6 + cm v3.0.2)

**Дата:** 31 июля 2026  
**Stack pins:** hub **v3.0.6** · UI **v3.0.17** · cm **v3.0.2**

---

## Что обновляется

| Компонент | Версия | Изменение |
|-----------|--------|-----------|
| selenoid-ui | **v3.0.17** | Kill in-place + artifact poll; Create Session waits for live SSE; DS public sync |
| selenoid (hub) | **v3.0.6** | без изменений |
| cm | **v3.0.2** | без изменений |

---

## Деплой

```bash
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.6 -f ui_version=v3.0.17

# или на сервере
SELENOID_VERSION=v3.0.6 SELENOID_UI_VERSION=v3.0.17 CM_VERSION=v3.0.2 \
  ./deploy/deploy.sh
```

Smoke public:

```bash
EXPECTED_HUB_VERSION=v3.0.6 EXPECTED_UI_VERSION=v3.0.17 \
  ./deploy/smoke-remote.sh https://selenoid.qa.guru
```

E2e (selenoid-tests):

```bash
SELENOID_TEST_ENV=selenoid_qa_guru_e2e go test -v -p 1 \
  -run 'TestUiManualHar|TestUiSessionKillSmooth' ./tests/e2e/ui/...
```

Связанные: [selenoid-ui v3.0.17](https://github.com/qa-guru/selenoid-ui/releases/tag/v3.0.17).
