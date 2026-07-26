# Release pin — hub v3.0.2 + UI v3.0.9

**Дата:** 27 июля 2026  
**Stack pins:** hub **v3.0.2** · UI **v3.0.9** · cm **v3.0.1** (без изменений)

---

## Что обновляется

| Компонент | Версия | Изменение |
|-----------|--------|-----------|
| selenoid (hub) | **v3.0.2** | `-playwright-access-key` → `-access-key` rename |
| selenoid-ui | **v3.0.9** | Hotfix: `@types/node` для Stage 1 release typecheck |
| cm | **v3.0.1** | Без изменений |

---

## Деплой

```bash
# GitHub Actions
gh workflow run deploy.yml -f version=v3.0.2 -f ui_version=v3.0.9

# или на сервере (defaults после bump)
./deploy/deploy.sh
```

Smoke: `./deploy/smoke-remote.sh https://selenoid.qa.guru`

Связанные: [selenoid v3.0.2](https://github.com/qa-guru/selenoid/releases/tag/v3.0.2), [selenoid-ui v3.0.9](https://github.com/qa-guru/selenoid-ui/releases/tag/v3.0.9), [cm v3.0.1](https://github.com/qa-guru/cm/releases/tag/v3.0.1).
