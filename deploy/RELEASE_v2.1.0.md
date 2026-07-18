# qa-guru Selenoid Stack — Release v2.1.0

| Компонент | Release | Статус |
|-----------|---------|--------|
| **Deploy** | [v2.1.0](https://github.com/qa-guru/selenoid.qa.guru/releases/tag/v2.1.0) | prod-деплой |
| **cm** | [v2.1.0](https://github.com/qa-guru/cm/releases/tag/v2.1.0) | установщик |
| Selenoid hub | [v2.1.0](https://github.com/qa-guru/selenoid/releases/tag/v2.1.0) | hub |
| Selenoid UI | [v2.1.0](https://github.com/qa-guru/selenoid-ui/releases/tag/v2.1.0) | UI |
| Playwright images | `qaguru/playwright-*:1.61.1` | без изменений |

Предыдущий стек: [v2.0.9](RELEASE_v2.0.9.md)

---

## Что нового в v2.1.0

Единая версия **v2.1.0** для cm, hub, UI и deploy-репозитория.

| Изменение | Описание |
|-----------|----------|
| **selenoid.qa.guru** | Скрипты деплоя, nginx, CI (`deploy.yml`), release notes стека |
| **cm** | Только сборка, релиз и Docker-образ — без prod-деплоя |
| **GitHub Actions** | Prod-деплой: Actions → [deploy](https://github.com/qa-guru/selenoid.qa.guru/actions/workflows/deploy.yml) |
| **Код hub/UI/cm** | Без изменений относительно v2.0.9 — выравнивание версии стека |

---

## Деплой

GitHub Actions в [qa-guru/selenoid.qa.guru](https://github.com/qa-guru/selenoid.qa.guru):

- **ref:** `v2.1.0`
- **version:** `v2.1.0` (или пусто — default в `deploy.sh`)

Вручную на сервере (от пользователя `selenoid`):

```bash
SELENOID_VERSION=v2.1.0 SELENOID_UI_VERSION=v2.1.0 ./deploy/deploy.sh
```

Проверка:

```bash
./deploy/smoke-remote.sh https://selenoid.qa.guru
```

---

## Эндпоинты

| Протокол | URL |
|----------|-----|
| Selenium | `https://selenoid.qa.guru/wd/hub` |
| Playwright | `wss://selenoid.qa.guru/playwright/playwright-chromium/1.61.1` |
| UI | `https://selenoid.qa.guru/` |
| Status | `https://selenoid.qa.guru/status` |

WebDriver Edge: `browserName: msedge` или `MicrosoftEdge`, `browserVersion: 145.0`.
