# selenoid.qa.guru

Production-деплой публичного Selenoid: **https://selenoid.qa.guru**

| Компонент | GitHub | Роль на prod |
|-----------|--------|--------------|
| **cm** | [qa-guru/cm](https://github.com/qa-guru/cm) | Установщик: скачивает hub/UI, `browsers.json`, browser-образы |
| **selenoid** | [qa-guru/selenoid](https://github.com/qa-guru/selenoid) | Hub (релизы → бинарник на сервере) |
| **selenoid-ui** | [qa-guru/selenoid-ui](https://github.com/qa-guru/selenoid-ui) | UI (релизы → бинарник на сервере) |
| **browser-image** | [qa-guru/browser-image](https://github.com/qa-guru/browser-image) | Playwright + WebDriver browser nodes (`docker pull`) |
| **этот репозиторий** | [qa-guru/selenoid.qa.guru](https://github.com/qa-guru/selenoid.qa.guru) | Скрипты деплоя, nginx, CI, release notes стека |

В **cm** остаются только сборка, релиз и публикация Docker-образа. Деплой на сервер — отсюда.

## Быстрый старт

| Действие | Как |
|----------|-----|
| **Ручной деплой** | GitHub → Actions → [deploy](https://github.com/qa-guru/selenoid.qa.guru/actions/workflows/deploy.yml) → Run workflow |
| **Post-deploy prod smoke** | Actions → [trigger-deploy-smoke](https://github.com/qa-guru/selenoid.qa.guru/actions/workflows/trigger-deploy-smoke.yml) (async → [selenoid-tests](https://github.com/qa-guru/selenoid-tests) `deploy-smoke`, profile `selenoid_qa_guru_api`) |
| **Перезагрузка nginx** | Actions → [nginx-reload](https://github.com/qa-guru/selenoid.qa.guru/actions/workflows/nginx-reload.yml) |
| **Деплой на сервере** | `./deploy/deploy.sh` (из клона этого репозитория) |
| **Smoke test** | `./deploy/smoke-remote.sh https://selenoid.qa.guru` |

Полная документация: [`deploy/README.md`](deploy/README.md).

## browsers.json на prod

Канонический конфиг стека: [`qa-guru/selenoid/config/browsers.json`](https://github.com/qa-guru/selenoid/blob/main/config/browsers.json).

На сервер кладётся копия из [`deploy/browsers-production.json`](deploy/browsers-production.json) → `/opt/selenoid/browsers.json` (см. [`deploy/deploy.sh`](deploy/deploy.sh)). Встроенный конфиг **cm** (`selenoid/data/browsers-qaguru.json`) используется при установке без `-j`; для prod deploy приоритет у `browsers-production.json`.
