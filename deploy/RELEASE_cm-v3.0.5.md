# Release pin — cm v3.0.5 (hub v3.0.15 + UI v3.0.54)

**Дата:** 4 сентября 2026  
**Stack pins:** hub **v3.0.15** · UI **v3.0.54** · cm **v3.0.5**

`cm selenoid start` передаёт hub `DOCKER_API_VERSION=1.55` (литерал в cm был 1.45). Prod hub — native systemd, `DOCKER_API_VERSION` не пинится (moby auto-negotiate). Этот cut обновляет бинарник `~/cm` на Box1.

Hub/UI теги не менять: dispatch без `version` / `ui_version` (live probe). Не stop'ать pool compose.

```bash
gh workflow run deploy.yml -R qa-guru/selenoid.qa.guru \
  -f pull_browsers=never
```

Связанные: [cm v3.0.5](https://github.com/qa-guru/cm/releases/tag/v3.0.5), [selenoid v3.0.15](https://github.com/qa-guru/selenoid/releases/tag/v3.0.15), [selenoid-ui v3.0.54](https://github.com/qa-guru/selenoid-ui/releases/tag/v3.0.54).
