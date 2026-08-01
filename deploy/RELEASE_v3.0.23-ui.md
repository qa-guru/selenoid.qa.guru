# Release pin — UI v3.0.23 (hub v3.0.6 + cm v3.0.2)

**Дата:** 1 августа 2026  
**Stack pins:** hub **v3.0.6** · UI **v3.0.23** · cm **v3.0.2**

- Playwright Create: 15s grace on WebSocket close + `/ui/status` poll
- fetch/EventSource via `location.origin` (credentialed document URLs)

```bash
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.6 -f ui_version=v3.0.23
```
