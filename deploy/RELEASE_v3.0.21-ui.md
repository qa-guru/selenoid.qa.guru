# Release pin — UI v3.0.21 (hub v3.0.6 + cm v3.0.2)

**Дата:** 1 августа 2026  
**Stack pins:** hub **v3.0.6** · UI **v3.0.21** · cm **v3.0.2**

Create Session: `waitForLiveSession` polls `/ui/status` so navigation no longer hangs when the page SSE connection is stale.

```bash
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.6 -f ui_version=v3.0.21
```
