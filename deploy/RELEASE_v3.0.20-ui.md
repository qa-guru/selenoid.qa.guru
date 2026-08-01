# Release pin — UI v3.0.20 (hub v3.0.6 + cm v3.0.2)

**Дата:** 1 августа 2026  
**Stack pins:** hub **v3.0.6** · UI **v3.0.20** · cm **v3.0.2**

Rebuild: bake-time `HUB_*` secrets synced with `selenoid-production` public guest via `sync-ui-hub-auth.yml`.

```bash
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.6 -f ui_version=v3.0.20
```
