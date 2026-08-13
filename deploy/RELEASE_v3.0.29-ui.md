# Release pin — UI v3.0.29 (hub v3.0.8 + cm v3.0.2)

**Дата:** 13 августа 2026  
**Stack pins:** hub **v3.0.8** · UI **v3.0.29** · cm **v3.0.2**

- `?mock=1` live session mocks (max / min / freeze) + fake VNC desktop
- Session chrome names: Session details, VNC window, HAR Viewer
- Session logs hug xterm height; VNC floor without empty trailing row
- Visual snapshots per OS in CI

```bash
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f version=v3.0.8 -f ui_version=v3.0.29
```
