# Release pin — hub v3.0.13 (UI v3.0.36 + cm v3.0.3)

**Дата:** 17 августа 2026  
**Stack pins:** hub **v3.0.13** · UI **v3.0.36** · cm **v3.0.3**

- Hub `-pool-url` alias for `-warm-pool-url` (prod unit stays `-warm-pool-url`)
- Docs: sidecar [qa-guru/selenoid-pool](https://github.com/qa-guru/selenoid-pool)
- Do not stop box1 pool compose

```bash
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.13 -f ui_version=v3.0.36 -f pull_browsers=never
```

Связанные: [selenoid v3.0.13](https://github.com/qa-guru/selenoid/releases/tag/v3.0.13), [cm v3.0.3](https://github.com/qa-guru/cm/releases/tag/v3.0.3), [selenoid-ui v3.0.36](https://github.com/qa-guru/selenoid-ui/releases/tag/v3.0.36).
