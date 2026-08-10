# Release pin — hub v3.0.8 (UI v3.0.24 + cm v3.0.2)

**Дата:** 10 августа 2026  
**Stack pins:** hub **v3.0.8** · UI **v3.0.24** · cm **v3.0.2**

## Что фиксируем

| Item | Деталь |
|------|--------|
| hub | finished-session list API: `sort` / `order` (`finished` default desc; also `id`, `duration`, `quota`, `name`) |
| UI | SessionArchive sortable table + URL state (needs hub sort API) |
| smoke | pin gate via release `wait_only` |

```bash
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.8 -f ui_version=v3.0.24
```

Verify:

```bash
curl -sf https://selenoid.qa.guru/hub/ping | jq .version
# → "v3.0.8"
curl -sf https://selenoid.qa.guru/ping | jq .version
# → "v3.0.24"
```
