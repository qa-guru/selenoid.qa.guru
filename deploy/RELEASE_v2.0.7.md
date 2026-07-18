# qa-guru Selenoid Stack — Release v2.0.7 (production verified)

| Компонент | Release | Статус |
|-----------|---------|--------|
| **cm** | [v2.0.7](https://github.com/qa-guru/cm/releases/tag/v2.0.7) | deploy + nginx + smoke |
| Selenoid hub | [v2.0.6](https://github.com/qa-guru/selenoid/releases/tag/v2.0.6) | без изменений |
| Selenoid UI | [v2.0.6](https://github.com/qa-guru/selenoid-ui/releases/tag/v2.0.6) | без изменений |
| Playwright images | `qaguru/playwright-*:1.61.1` | без изменений |

Предыдущий стек: [v2.0.6](RELEASE_v2.0.6.md)

Следующий: [v2.0.8](RELEASE_v2.0.8.md) — выровненный стек v2.0.8, `msedge`, flaky smoke fix.

**Проверено на prod:** `https://selenoid.qa.guru` — smoke `deploy/smoke-remote.sh` проходит.

---

## Что нового в v2.0.7

Патч-релиз **только cm/deploy**: доводка production-деплоя после v2.0.6. Hub и UI остаются на **v2.0.6**.

| Изменение | Описание |
|-----------|----------|
| **Nginx `/playwright/`** | Проксирование Playwright WS через UI |
| **sync-nginx.sh** | Скрипт в `/tmp` + passwordless sudo из `bootstrap.sh` |
| **deploy staging** | Файлы в `$HOME/.selenoid-deploy`, не в `/tmp` и не в `/opt/selenoid/bin` |
| **Docker network** | Пересоздание `selenoid` после `docker system prune` |
| **cm configure** | Принудительный pull всех образов из `browsers.json` |
| **smoke-remote.sh** | Проверяет `playwright-chromium`, публичный UI и `/wd/hub` |

---

## Деплой

Автоматически при публикации GitHub Release **cm v2.0.7**.

Вручную на сервере (от пользователя `selenoid`):

```bash
SELENOID_VERSION=v2.0.6 SELENOID_UI_VERSION=v2.0.6 ./deploy/deploy.sh
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

Playwright-браузеры: `playwright-chromium`, `playwright-firefox`, `playwright-webkit`, `playwright-chrome`, `playwright-msedge`.
