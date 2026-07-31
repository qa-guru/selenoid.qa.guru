# Release pin — UI v3.0.19 (hub v3.0.6 + cm v3.0.2)

**Дата:** 1 августа 2026  
**Stack pins:** hub **v3.0.6** · UI **v3.0.19** · cm **v3.0.2**

Playwright Kill: remember `accessKey` (user:pass) for DELETE Basic Auth.

```bash
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.6 -f ui_version=v3.0.19
```
