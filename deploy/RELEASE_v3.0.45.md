# Release pin — UI v3.0.45 (hub v3.0.13 + cm v3.0.3)

**Дата:** 18 августа 2026  
**Stack pins:** hub **v3.0.13** · UI **v3.0.45** · cm **v3.0.3**

- Default stack URLs in UI mocks/snippets (autotests.ai java-spring + typescript-react)
- Empty-default `ui_version` in `deploy.yml` / `deploy.sh` → **v3.0.45** (hub-only dispatch must not roll UI back)
- Do not stop box1 pool compose

```bash
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.13 -f ui_version=v3.0.45 -f pull_browsers=never
```

Связанные: [selenoid v3.0.13](https://github.com/qa-guru/selenoid/releases/tag/v3.0.13), [cm v3.0.3](https://github.com/qa-guru/cm/releases/tag/v3.0.3), [selenoid-ui v3.0.45](https://github.com/qa-guru/selenoid-ui/releases/tag/v3.0.45).
