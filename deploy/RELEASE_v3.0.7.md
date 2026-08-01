# Release pin — hub v3.0.7 (UI v3.0.23 + cm v3.0.2)

**Дата:** 1 августа 2026  
**Stack pins:** hub **v3.0.7** · UI **v3.0.23** · cm **v3.0.2**

## Что фиксируем

| Item | Деталь |
|------|--------|
| hub | `warmReady` / `warmTotal` via `-warm-pool-url http://127.0.0.1:9090` |
| unit | `deploy/selenoid-hub.service` (sync from `selenoid-warm-pool/deploy/`) |
| warm-pool | **не** трогать `selenoid-warm-pool` / `warm-chrome-*` на hub-deploy |
| smoke | `smoke-remote.sh` требует `warmTotal >= 2` (override `EXPECT_WARM_METRICS=0`) |

```bash
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.7 -f ui_version=v3.0.23
```

Verify:

```bash
curl -sf https://selenoid.qa.guru/status | jq '{warmReady,warmTotal,used,total}'
# → warmReady/warmTotal 2/2 (or live slot count)
```
