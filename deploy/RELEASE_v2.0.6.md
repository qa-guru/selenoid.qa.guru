# qa-guru Selenoid Stack — Release v2.0.6

| Компонент | Release | Документация |
|-----------|---------|--------------|
| **cm** | [v2.0.6](https://github.com/qa-guru/cm/releases/tag/v2.0.6) | установщик стека |
| Selenoid hub | [v2.0.6](https://github.com/qa-guru/selenoid/releases/tag/v2.0.6) | [selenoid v2.0.6](https://github.com/qa-guru/selenoid/releases/tag/v2.0.6) |
| Selenoid UI | [v2.0.6](https://github.com/qa-guru/selenoid-ui/releases/tag/v2.0.6) | [selenoid-ui v2.0.6](https://github.com/qa-guru/selenoid-ui/releases/tag/v2.0.6) |
| Playwright images | [playwright-image](https://github.com/qa-guru/playwright-image) | per-browser на Docker Hub |

Предыдущий стек: [v2.0.5](https://github.com/qa-guru/cm/releases/tag/v2.0.5)

Следующий: [v2.0.7](RELEASE_v2.0.7.md) — production deploy fixes (hub/UI остаются v2.0.6).

---

## Что нового в v2.0.6

| Изменение | Описание |
|-----------|----------|
| **browsers.json** | Все Playwright-браузеры через отдельные образы: `playwright-chromium`, `playwright-firefox`, `playwright-webkit`, `playwright-chrome`, `playwright-msedge` |
| **Production deploy** | `deploy.sh` применяет `browsers-production.json` и догружает все 5 Playwright-образов |
| **UI** | Capabilities показывает новые имена браузеров |

---

## Деплой на prod

Релиз **cm v2.0.6** автоматически запускает [deploy workflow](../.github/workflows/deploy.yml).

Вручную на сервере:

```bash
SELENOID_VERSION=v2.0.6 SELENOID_UI_VERSION=v2.0.6 ./deploy/deploy.sh
```

Образы для pull:

```bash
for img in playwright-chromium playwright-firefox playwright-webkit playwright-chrome playwright-msedge; do
  docker pull "qaguru/${img}:1.61.1"
done
```

---

## Эндпоинты (без изменений)

| Протокол | URL |
|----------|-----|
| Selenium | `https://selenoid.qa.guru/wd/hub` |
| Playwright | `wss://selenoid.qa.guru/playwright/playwright-chromium/1.61.1` |

Доступные Playwright-браузеры: `playwright-chromium`, `playwright-firefox`, `playwright-webkit`, `playwright-chrome`, `playwright-msedge`.
