# qa-guru Selenoid Stack — Release v2.0.9

| Компонент | Release | Статус |
|-----------|---------|--------|
| **cm** | [v2.0.9](https://github.com/qa-guru/cm/releases/tag/v2.0.9) | deploy + smoke |
| Selenoid hub | [v2.0.9](https://github.com/qa-guru/selenoid/releases/tag/v2.0.9) | docs |
| Selenoid UI | [v2.0.9](https://github.com/qa-guru/selenoid-ui/releases/tag/v2.0.9) | docs + browsers.json path |
| Playwright images | `qaguru/playwright-*:1.61.1` | README (без нового тега) |

Предыдущий стек: [v2.0.8](RELEASE_v2.0.8.md)

---

## Что нового в v2.0.9

Единая версия **v2.0.9** для cm, hub и UI. Код hub без изменений — **обновление документации** во всей экосистеме.

| Изменение | Описание |
|-----------|----------|
| **README (все репо)** | Единый обзор экосистемы: selenoid → hub, selenoid-ui → UI, cm → установщик, playwright-image → browser nodes |
| **deploy/README.md** | Актуальные public endpoints без устаревших инструкций по basic auth |
| **cm README** | Структурированная установка, связанные репозитории, sync browsers.json |
| **playwright-image README** | Исправлены URL-пути Playwright (`playwright-firefox`, не `firefox`) |
| **deploy.sh** | Default pin `v2.0.9` |

---

## Деплой

Автоматически при публикации GitHub Release **cm v2.0.9**.

Вручную на сервере (от пользователя `selenoid`):

```bash
SELENOID_VERSION=v2.0.9 SELENOID_UI_VERSION=v2.0.9 ./deploy/deploy.sh
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

Следующий: [v2.1.0](RELEASE_v2.1.0.md) — единая версия стека, prod deploy repo.
