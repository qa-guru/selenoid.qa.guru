# Release pin — UI v3.0.22 (hub v3.0.6 + cm v3.0.2)

**Дата:** 1 августа 2026  
**Stack pins:** hub **v3.0.6** · UI **v3.0.22** · cm **v3.0.2**

Playwright Create Session: poll `/ui/status` (do not abort on second EventSource error).

```bash
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.6 -f ui_version=v3.0.22
```
