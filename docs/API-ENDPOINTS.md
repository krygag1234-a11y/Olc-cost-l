# OlcRTC Manager — API endpoints (golden panel)

Эталон: `packaging/golden-panel/main.go` (тестовый VPS, синк через внутренние dev-скрипты).

Все `/api/*` (кроме auth login/setup) требуют сессию администратора.

## Auth

| Method | Path | Описание |
|--------|------|----------|
| POST | `/api/auth/login` | Вход |
| POST | `/api/auth/setup` | Первичная настройка |
| POST | `/api/auth/logout` | Выход |
| GET | `/api/auth/me` | Текущий пользователь |
| PUT | `/api/auth/password` | Смена пароля |

## Панель и настройки

| Method | Path | Описание |
|--------|------|----------|
| GET, PUT | `/api/settings` | Имя сервера, порт, subscription path, refresh |
| GET, PUT | `/api/panel/lang` | Язык UI → `OLC_PANEL_LANG` в `panel.env` |
| GET, PUT | `/api/settings/{zapret,tor,split,bridges,olcrtc,warp}` | Настройки компонентов |
| GET, PUT | `/api/instance-defaults` | Дефолты инстансов (`/var/lib/olcrtc/instance-defaults.json`) |
| GET, PUT | `/api/notification-settings` | Уведомления автодетектора |

## Состояние и клиенты

| Method | Path | Описание |
|--------|------|----------|
| GET | `/api/state` | Клиенты, локации, runtime |
| GET | `/api/metrics` | Память, PID менеджера |
| GET | `/api/audit` | Аудит |
| GET, POST | `/api/clients` | Список / создание |
| GET, PUT, DELETE | `/api/clients/{id}` | Клиент |
| GET, POST | `/api/clients/{id}/locations` | Локации |
| PUT, DELETE | `/api/clients/{id}/locations/{room}/{transport}` | Локация |

## Действия и логи

| Method | Path | Описание |
|--------|------|----------|
| POST | `/api/actions/restart` | Рестарт инстанса |
| POST | `/api/actions/stop` | Стоп |
| POST | `/api/actions/regenerate-room` | Новая комната |
| POST | `/api/actions/rotate-key` | Ротация ключа |
| GET | `/api/logs/{client}/{room}/{transport}` | Логи локации |
| GET | `/api/tools/generate-room` | Генерация room id |

## Фичи сети

| Method | Path | Описание |
|--------|------|----------|
| GET | `/api/features` | Флаги zapret/tor/split/bridges/warp |
| POST | `/api/features/{name}` | Вкл/выкл |
| GET | `/api/features/logs/{name}` | Логи фичи |
| GET | `/api/capabilities` | Профиль, компоненты, deploy fingerprint |

## Компоненты и обновления

| Method | Path | Описание |
|--------|------|----------|
| GET | `/api/components/jobs` | Jobs install/uninstall |
| POST | `/api/components/{name}/install` | Установка |
| POST | `/api/components/{name}/uninstall` | Удаление |
| GET | `/api/project/status` | Версия, stack manifest |
| GET | `/api/updates/check` | Проверка GitHub |
| GET | `/api/updates/status` | Статус job обновления |
| POST | `/api/updates/run` | Запуск обновления |
| GET | `/api/jobs/{id}/log` | Лог job |

## Прочее

| Method | Path | Описание |
|--------|------|----------|
| GET | `/api/notifications` | Список уведомлений |
| POST | `/api/notifications/scan` | Скан |
| PATCH | `/api/notifications/{id}` | Прочитано |
| GET | `/api/jitsi/preflight` | Preflight Jitsi URL |
| POST | `/api/reload` | Reload supervisor |
| GET | `/admin`, `/assets/*` | SPA панели |
| GET | `/{subscription_path}/` | Subscription |
