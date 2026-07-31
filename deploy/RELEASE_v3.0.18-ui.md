# Release pin — UI v3.0.18 (hub v3.0.6 + cm v3.0.2)

**Дата:** 31 июля 2026  
**Stack pins:** hub **v3.0.6** · UI **v3.0.18** · cm **v3.0.2**

---

## Что обновляется

| Компонент | Версия | Изменение |
|-----------|--------|-----------|
| selenoid-ui | **v3.0.18** | Kill DELETE Basic Auth + remember Create Session token |
| selenoid (hub) | **v3.0.6** | без изменений |
| cm | **v3.0.2** | без изменений |

---

## Деплой

```bash
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.6 -f ui_version=v3.0.18
```

Smoke:

```bash
EXPECTED_HUB_VERSION=v3.0.6 EXPECTED_UI_VERSION=v3.0.18 \
  ./deploy/smoke-remote.sh https://selenoid.qa.guru
```

E2e:

```bash
SELENOID_TEST_ENV=selenoid_qa_guru_e2e go test -v -p 1 \
  -run 'TestUiManualHar|TestUiSessionKillSmooth' ./tests/e2e/ui/...
```
