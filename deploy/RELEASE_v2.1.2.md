# qa-guru Selenoid Stack — Release v2.1.2 (UI)

| Компонент | Release | Статус |
|-----------|---------|--------|
| **Deploy** | main @ deploy defaults | prod-деплой |
| **cm** | [v2.1.1](https://github.com/qa-guru/cm/releases/tag/v2.1.1) | без изменений |
| Selenoid hub | [v2.1.1](https://github.com/qa-guru/selenoid/releases/tag/v2.1.1) | без изменений |
| Selenoid UI | [v2.1.2](https://github.com/qa-guru/selenoid-ui/releases/tag/v2.1.2) | vanilla JS ui-v2 + QA.GURU header |

Предыдущий стек: [v2.1.0](RELEASE_v2.1.0.md)

---

## Что нового в v2.1.2

| Изменение | Описание |
|-----------|----------|
| **selenoid-ui** | Vanilla JS ui-v2 вместо React; QA.GURU header shell, capabilities, sessions |
| **statik** | Сборка CI/release встраивает `ui-v2/` в бинарник |
| **hub / cm** | Без изменений — v2.1.1 |

---

## Деплой

GitHub Actions → [deploy](https://github.com/qa-guru/selenoid.qa.guru/actions/workflows/deploy.yml):

- **version:** `v2.1.1` (hub/cm) или пусто — default в `deploy.sh`
- **UI:** `SELENOID_UI_VERSION=v2.1.2` (default в `deploy.sh`)

```bash
SELENOID_VERSION=v2.1.1 SELENOID_UI_VERSION=v2.1.2 ./deploy/deploy.sh
./deploy/smoke-remote.sh https://selenoid.qa.guru
```
