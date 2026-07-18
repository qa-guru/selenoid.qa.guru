# qa-guru Selenoid Stack — Release v2.0.2

| Компонент | Release | Документация |
|-----------|---------|--------------|
| **cm** | [latest](https://github.com/qa-guru/cm/releases/latest) | [cm/docs/RELEASE_v2.0.1.md](https://github.com/qa-guru/cm/blob/main/docs/RELEASE_v2.0.1.md) |
| Selenoid hub | [v2.0.2](https://github.com/qa-guru/selenoid/releases/tag/v2.0.2) | [selenoid v2.0.2](https://github.com/qa-guru/selenoid/blob/main/docs/RELEASE_v2.0.2.md) |
| Selenoid UI | [latest](https://github.com/qa-guru/selenoid-ui/releases/latest) | [selenoid-ui](https://github.com/qa-guru/selenoid-ui/releases) |

Предыдущий стек: [v2.0.1](RELEASE_v2.0.1.md)

---

## Что нового в v2.0.2

Патч hub — без изменений протоколов Playwright / WebDriver.

| Изменение | Описание |
|-----------|----------|
| **DELETE Playwright session** | Завершение ручных Playwright-сессий из UI без 500 |
| **Docker inspect** | Стабильный старт контейнеров на хосте (не in-docker hub) |

---

## Деплой на selenoid.qa.guru

По умолчанию `deploy.sh` тянет **v2.0.2**:

```bash
./deploy/deploy.sh
```

Явный pin:

```bash
SELENOID_VERSION=v2.0.2 ./deploy/deploy.sh
```

Подробнее: [deploy/README.md](README.md)

---

## Обновление на сервере

```bash
./cm selenoid stop && ./cm selenoid-ui stop
./cm selenoid update -c /opt/selenoid
./cm selenoid-ui update -c /opt/selenoid
```

Или `./deploy/remote-update.sh` (тот же сценарий через `cm update`).
