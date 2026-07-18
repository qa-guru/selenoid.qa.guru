# qa-guru Selenoid Stack — Release v2.0.0

Общие release notes для стека **selenoid.qa.guru** и локальной разработки.

| Компонент | Release | Документация |
|-----------|---------|--------------|
| **cm** | [v2.0.0](https://github.com/qa-guru/cm/releases/tag/v2.0.0) | установщик стека |
| Selenoid hub | [v2.0.0](https://github.com/qa-guru/selenoid/releases/tag/v2.0.0) | [selenoid v2.0.0](https://github.com/qa-guru/selenoid/releases/tag/v2.0.0) |
| Selenoid UI | [v2.0.0](https://github.com/qa-guru/selenoid-ui/releases/tag/v2.0.0) | [selenoid-ui v2.0.0](https://github.com/qa-guru/selenoid-ui/releases/tag/v2.0.0) |
| Playwright image | [qaguru/playwright-chromium](https://hub.docker.com/r/qaguru/playwright-chromium) и др. | [playwright-image](https://github.com/qa-guru/playwright-image) |

---

## Endpoints

| Назначение | URL |
|------------|-----|
| Selenium | `https://selenoid.qa.guru/wd/hub` |
| Playwright | `wss://selenoid.qa.guru/playwright/playwright-chromium/1.61.1` |
| UI | `https://selenoid.qa.guru/` |
| Status | `https://selenoid.qa.guru/status` |
| Video | `https://selenoid.qa.guru/video/` |

---

## Переменные для тестов

```bash
export SELENOID_URL=https://selenoid.qa.guru/wd/hub
export PW_TEST_CONNECT_WS_ENDPOINT=wss://selenoid.qa.guru/playwright/playwright-chromium/1.61.1
```

Деплой: [README.md](README.md)
