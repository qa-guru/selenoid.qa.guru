# qa-guru Selenoid Stack — Release v2.0.8

| Компонент | Release | Статус |
|-----------|---------|--------|
| **cm** | [v2.0.8](https://github.com/qa-guru/cm/releases/tag/v2.0.8) | deploy + smoke |
| Selenoid hub | [v2.0.8](https://github.com/qa-guru/selenoid/releases/tag/v2.0.8) | msedge alias |
| Selenoid UI | [v2.0.8](https://github.com/qa-guru/selenoid-ui/releases/tag/v2.0.8) | msedge в UI |
| Playwright images | `qaguru/playwright-*:1.61.1` | без изменений |

Предыдущий стек: [v2.0.7](RELEASE_v2.0.7.md)  
Следующий: [v2.0.9](RELEASE_v2.0.9.md) — обновление документации экосистемы.

---

## Что нового в v2.0.8

Единая версия **v2.0.8** для cm, hub и UI.

| Изменение | Описание |
|-----------|----------|
| **`msedge` в browsers.json** | Ключ Edge выровнен с chrome/firefox (`MicrosoftEdge` → `msedge`) |
| **Hub alias** | `browserName: MicrosoftEdge` в Selenium caps по-прежнему работает |
| **smoke-remote.sh** | Retry (5×) + timeout Playwright 20s; проверка `msedge:145.0` |
| **Session limit** | Production hub `-limit 20` |

---

## Деплой

Автоматически при публикации GitHub Release **cm v2.0.8**.

Вручную на сервере (от пользователя `selenoid`):

```bash
SELENOID_VERSION=v2.0.8 SELENOID_UI_VERSION=v2.0.8 ./deploy/deploy.sh
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
