# qa-guru Selenoid Stack — Release v2.1.3 (UI fix)

| Компонент | Release | Статус |
|-----------|---------|--------|
| **Deploy** | main @ deploy defaults | prod-деплой |
| **cm** | [v2.1.6](https://github.com/qa-guru/cm/releases/tag/v2.1.6) | без изменений |
| Selenoid hub | [v2.1.7](https://github.com/qa-guru/selenoid/releases/tag/v2.1.7) | `-min` rewrite для geckodriver |
| Selenoid UI | [v2.1.3](https://github.com/qa-guru/selenoid-ui/releases/tag/v2.1.3) | capabilities SSE fix |

Предыдущий стек: [v2.1.2](RELEASE_v2.1.2.md)

---

## Что нового в v2.1.3

| Изменение | Описание |
|-----------|----------|
| **capabilities** | Форма не сбрасывается при SSE/status ticks; dropdown не закрывается каждые ~4s |
| **browser list** | Fallback на `browserProtocols` (browsers.json), если `/status` отдаёт пустой список |
| **hub / cm** | Без изменений — v2.1.1 |

---

## Деплой

GitHub Actions → [deploy](https://github.com/qa-guru/selenoid.qa.guru/actions/workflows/deploy.yml):

- **version:** hub `v2.1.7` (default в `deploy.sh`) или пусто
- **UI:** `SELENOID_UI_VERSION=v2.1.3` (default в `deploy.sh`)

```bash
SELENOID_VERSION=v2.1.7 SELENOID_UI_VERSION=v2.1.3 ./deploy/deploy.sh
./deploy/smoke-remote.sh https://selenoid.qa.guru
```
