# Release pin — hub v3.0.9 (UI v3.0.29 + cm v3.0.2)

**Дата:** 13 августа 2026  
**Stack pins:** hub **v3.0.9** · UI **v3.0.29** · cm **v3.0.2**

## Что фиксируем

| Item | Деталь |
|------|--------|
| hub | Chrome WD container-reuse via `-warm-pool-url` (`loopback:true` reserve, cold fallback) |
| orchestrator | box1 rebuilt from [selenoid-warm-pool v1.0.0](https://github.com/qa-guru/selenoid-warm-pool/releases/tag/v1.0.0) — loopback filter; `config.hub.yaml` still docker-DNS → **409 → cold** |
| metrics | `warmReady`/`warmTotal` 2/2 unchanged |
| smoke | pin gate via release `wait_only` + deploy-smoke `api,smoke` |

```bash
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.9 -f ui_version=v3.0.29
```

Verify:

```bash
curl -sf https://selenoid.qa.guru/hub/ping | jq .version
# → "v3.0.9"
curl -sf https://selenoid.qa.guru/status | jq '{warmReady,warmTotal}'
# → 2/2
curl -sf https://selenoid.qa.guru/ping | jq .version
# → "v3.0.29"
```
