# Release pin — cm v3.0.3 (hub v3.0.12 + UI v3.0.36)

**Дата:** 17 августа 2026  
**Stack pins:** hub **v3.0.12** · UI **v3.0.36** · cm **v3.0.3**

- `cm selenoid start --pool` / `--warm-pool` / `--hot-pool` (sidecar [selenoid-pool](https://github.com/qa-guru/selenoid-pool), image `qaguru/selenoid-pool:min`)
- Go toolchain **1.26.6**
- Prod box1: pool compose stays up; deploy does **not** `docker stop` warm/hot slots. Hub still `-warm-pool-url`.

```bash
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.12 -f ui_version=v3.0.36 -f pull_browsers=never
```

Связанные: [cm v3.0.3](https://github.com/qa-guru/cm/releases/tag/v3.0.3), [selenoid v3.0.12](https://github.com/qa-guru/selenoid/releases/tag/v3.0.12), [selenoid-ui v3.0.36](https://github.com/qa-guru/selenoid-ui/releases/tag/v3.0.36).
