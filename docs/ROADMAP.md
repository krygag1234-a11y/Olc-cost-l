# Olc-cost-l — мастер-план разработки панели

> **Назначение:** единый живой документ. При работе над задачей — открывать этот файл, отмечать статус, не терять контекст на длинных сессиях.  
> **Последнее обновление плана:** 2026-05-26  
> **Текущая версия панели (репо):** `main` @ `365f267+` (фаза 0–2 в работе)

## Легенда статусов

| Статус | Значение |
|--------|----------|
| `[ ]` | не начато |
| `[~]` | в работе |
| `[x]` | сделано в репо + задеплоено на тест |
| `[!]` | блокер / нужно решение |
| `[-]` | отменено / не делаем |

## Принципы (не нарушать)

1. **Всё в одном SPA** — никаких отдельных страниц/сайтов; только модалки, выдвижные панели, drawer’ы поверх `/admin`.
2. **Условная видимость** — если на VPS нет Tor / Zapret / Split / Мостов, в UI **нет** их toggle, логов, настроек, кода установки (читаем `features.env`, `install-state.json`, live-проверки).
3. **Безопасность** — деструктивные действия: confirm + ввод имени функции; предупреждения о перезапуске инстансов; lock панели на время update.
4. **Не грузить VPS** — polling с backoff; один фоновый job на update; логи — tail + limit; error-detector — батч раз в N сек, не на каждый байт.
5. **Патчи manager** — как сейчас: `scripts/patch-olcrtc-manager-*.sh` → `apply-olcrtc-patches.sh` → `npm run build`.
6. **Upstream olcrtc** — только [`fix/all`](https://github.com/openlibrecommunity/olcrtc/tree/fix/all); `master` не использовать.

---

## Фаза 0 — Срочные баги (до больших фич)

| ID | Задача | Статус | Файлы / заметки |
|----|--------|--------|-----------------|
| 0.1 | **Копировать** в логах инстансов не работает | `[x]` | `copyLogs` теперь с `navigator.clipboard` + textarea/`execCommand` fallback (работает на http) |
| 0.2 | В логах **патчей** (Zp/Tor/Sp/Мосты): кнопки **Копировать** + **Обновить** (не live stream) | `[x]` | `FeatureLogsModal`: кнопки «Обновить» и «Копировать» с fallback |
| 0.3 | **Некорректный client_id** ломает всю панель (белый экран) | `[x]` | Backend: strict-валидация `client_id` (`a-zA-Z0-9_-`, до 64) для create/update/location |
| 0.4 | **Jitsi URL** без `https://` — автодобавление схемы; не ругаться на полный URL | `[x]` | Backend: `normalizeRoomID` добавляет `https://` для доменов без схемы |
| 0.5 | Синхронизация header ↔ «Сеть и обход» | `[x]` | `olc-features-changed` (v3) |
| 0.6 | Split только при включённом Tor | `[x]` | UI + `olc-feature.sh` |
| 0.7 | Удаление локации не блокирует всю панель | `[x]` | `pendingLocations` + async reload |
| 0.8 | Tor/Split toggle без HTTP 500 | `[x]` | deferred restart + api-v2 |

**Критерий приёмки фазы 0:** тестовый VPS, Ctrl+Shift+R; создать клиента `вркпгшкургш` → ошибка в toast, панель жива; копировать логи инстанса и zapret работает.

---

## Фаза 1 — Инфраструктура: «отпечаток» сценария и умный update

Сейчас `olc-update` → всегда `agent-bootstrap.sh --update` (полный сценарий для RU VPS). Нужен **профиль установки**, который записывается при первом install и читается при каждом update.

### 1.1 Файл отпечатка

| Поле | Путь | Описание |
|------|------|----------|
| Профиль | `/etc/olcrtc-manager/deploy-profile.json` | JSON, версия схемы |
| Зеркало в репо | `data/deploy-profiles/*.json` | шаблоны |

**Пример `deploy-profile.json`:**

```json
{
  "schema": 1,
  "profile_id": "ru-full",
  "label": "RU VPS: Tor + Split + Zapret + Мосты",
  "components": {
    "tor": true,
    "split": true,
    "zapret": true,
    "bridges": true,
    "webtunnel": true
  },
  "update_mode": "incremental",
  "created_at": "2026-05-26T12:00:00Z",
  "install_script_fingerprint": "install.sh:--no-tor"
}
```

### 1.2 Запись отпечатка (первым делом в скриптах)

| ID | Задача | Статус |
|----|--------|--------|
| 1.2.1 | `install.sh` — после разбора argv писать профиль (`--no-tor`, `--no-zapret`, `--no-split`, …) | `[~]` bootstrap пишет при первом install |
| 1.2.2 | `agent-bootstrap.sh` — при `--update` читать профиль, пропускать чужие шаги | `[x]` `state_step_profile` + `profile_apply_env` |
| 1.2.3 | `olc-update.sh` — опции `--profile`, `--set-profile`, `--show-profile` | `[x]` `--show-profile`, `--profile <id>` |
| 1.2.4 | Симлинк/хелпер `olc-profile` — смена профиля без переустановки | `[x]` `/usr/local/bin/olc-profile` |
| 1.2.5 | Документация в `docs/VPS-SETUP.md`, `docs/FEATURES.md` | `[~]` |

**Профили (минимум):**

| `profile_id` | Tor | Split | Zapret | Мосты | Когда |
|--------------|-----|-------|--------|-------|-------|
| `ru-full` | ✓ | ✓ | ✓ | ✓ | RU VPS по умолчанию |
| `ru-no-zapret` | ✓ | ✓ | ✗ | ✓ | тест без DPI |
| `foreign-minimal` | ✗ | ✗ | ✗ | ✗ | зарубежный relay |
| `foreign-tor` | ✓ | ✗ | ✗ | ✓ | Tor-only |
| `custom` | … | … | … | … | из UI «±» |

**Критерий:** `olc-update` на foreign VPS не тянет 6 минут zapret/split; на RU — тянет только включённые компоненты.

---

## Фаза 2 — Capability API (что показывать в UI)

Единый endpoint для всей панели (не плодить десятки страниц):

```
GET /api/capabilities
```

**Ответ (черновик):**

```json
{
  "panel_version": "0.9.0-alpha",
  "repo_sha": "39f4c61",
  "components": {
    "zapret": { "installed": true, "enabled": true, "configurable": true },
    "tor": { "installed": true, "enabled": false, "configurable": true },
    "split": { "installed": true, "enabled": true, "requires": ["tor"] },
    "bridges": { "installed": true, "enabled": true, "label": "Мосты" },
    "olcrtc": { "version": "...", "branch": "fix/all" }
  },
  "deploy_profile": "ru-full",
  "update_available": false
}
```

| ID | Задача | Статус |
|----|--------|--------|
| 2.1 | Go: `capabilitiesHandler` — читает `features.env`, systemd, файлы, `install-state` | `[x]` |
| 2.2 | UI: `useCapabilities()` — скрывает блоки Zp/Tor/Sp/Мосты | `[x]` |
| 2.3 | При `split` без `tor` — split скрыт или disabled с tooltip | `[x]` splitBlocked + requires tor |

---

## Фаза 3 — Реальные настройки слоёв (модалки)

Заменить `FeatureSettingsModal` (сейчас только текст-подсказка) на **формы с сохранением**.

Общий паттерн UI: `FeatureSettingsDrawer` → вкладки «Основное | Списки | Расширенное | Опасная зона».

Общий паттерн backend:

```
GET  /api/settings/{component}     → текущие значения (без секретов)
PUT  /api/settings/{component}     → применить (валидация + backup + reload если нужно)
POST /api/settings/{component}/test → dry-run / проверка синтаксиса списков
```

### 3.1 Zapret (источник: [zapret4rocket](https://github.com/IndeecFOX/zapret4rocket))

| ID | Настройка | Реализация | Статус |
|----|-----------|------------|--------|
| 3.1.1 | Вкл/выкл, reload | уже `olc-feature` | `[x]` |
| 3.1.2 | Выбор **стратегии** / пресета (из `data/zapret4rocket`, `lib/strategies.sh`) | UI select → запись в managed snippet `/etc/olcrtc-manager/zapret.override` | `[ ]` |
| 3.1.3 | Параметры nfqws (repeats, fooling, …) — ограниченный whitelist полей | форма + валидация | `[ ]` |
| 3.1.4 | **Кастом хосты/IP**: include / exclude / «только через zapret» | файлы в `/var/lib/olcrtc/zapret-custom/` + merge в `zapret-sync-excludes.sh` | `[ ]` |
| 3.1.5 | Автообновление z4r / списков (cron) | toggle + `OLCRTC_ZAPRET_AUTO_SYNC` | `[ ]` |
| 3.1.6 | Полная переустановка | кнопка с confirm → `OLCRTC_ZAPRET_REINSTALL=1` + lock | `[ ]` |
| 3.1.7 | Предупреждение: restart zapret → краткий разрыв DPI | modal | `[ ]` |

**Изучить:** `data/zapret4rocket/lib/strategies.sh`, `lib/actions.sh`, `z4r.sh`, наш `install-zapret-vps.sh`, `zapret-sync-excludes.sh`.

### 3.2 Tor

| ID | Настройка | Статус |
|----|-----------|--------|
| 3.2.1 | SOCKS порт (default 9050) | `[ ]` — смена → warning + restart all instances |
| 3.2.2 | ExitNodes / ExcludeExitNodes | `[ ]` — уже в torrc, вынести в UI |
| 3.2.3 | Кастом **direct** / **force-tor** домены и CIDR | `[ ]` — файлы + merge с split lists |
| 3.2.4 | Автообновление bridge pool / webtunnel binary | `[ ]` |
| 3.2.5 | Экспериментальные PT (obfs4, snowflake, webtunnel) | `[ ]` — чекбоксы в `bridges.conf` |
| 3.2.6 | Отключение Tor → auto-off split | `[ ]` — логика в `olc-feature` |

**Изучить:** `install-tor-pluggable-transports.sh`, `tor-bridge-pool.sh`, `docs/TOR-BRIDGES.md`.

### 3.3 Split routing

| ID | Настройка | Статус |
|----|-----------|--------|
| 3.3.1 | Вкл/выкл (quick vs full refresh) | `[x]` partial |
| 3.3.2 | Редактор **ru-direct-domains**, **panel-carrier-hosts**, CDN lists | `[ ]` |
| 3.3.3 | Кастом direct / force-tor / blocked-tor | `[ ]` |
| 3.3.4 | CIDR-only mode toggle | `[ ]` — `setup-split-ru.sh` |
| 3.3.5 | Кнопка «полное обновление списков» → фоновый job + progress | `[ ]` |
| 3.3.6 | Зависимость от Tor | `[x]` |

**Изучить:** `setup-split-ru.sh`, `patches/olcrtc-routing-*.go`, player CDN lists.

### 3.4 Мосты (переименовать WebTunnel → **«Мосты»**)

| ID | Настройка | Статус |
|----|-----------|--------|
| 3.4.1 | Переименование в UI (Wt → **Мосты** или **Br**) | `[x]` |
| 3.4.2 | Список мостов: obfs4 / snowflake / webtunnel | `[ ]` |
| 3.4.3 | Добавить свой мост (строка `Bridge …`) | `[ ]` — append `bridges.conf` + validate |
| 3.4.4 | Приоритет / ротация / pool service | `[ ]` |
| 3.4.5 | Удаление мостов → confirm + рекомендация удалить split | `[ ]` |
| 3.4.6 | Предупреждение: нет нод, только Tor PT | `[ ]` |

### 3.5 OlcRTC (сервер / инстансы)

| ID | Настройка | Источник | Статус |
|----|-----------|----------|--------|
| 3.5.1 | `panel.env`: `OLCRTC_JITSI_INSECURE_TLS`, reconnect, timeouts | manager settings | `[~]` частично |
| 3.5.2 | Дефолты VP8/SEI (fps, batch, frag, ack-ms) | [olcbox](https://github.com/alananisimov/olcbox), panel transports | `[x]` defaults |
| 3.5.3 | Глобальные лимиты reconnect / debounce | olcrtc `fix/all` server patches | `[ ]` — только если есть в server config |
| 3.5.4 | Поведение для **клиента olcbox** | olcbox README — subscription export only; **не дублировать** клиентский UI | `[-]` |
| 3.5.5 | jitsi join retry, fail-fast hosts | наш `patch-jitsi-*` | `[x]` |

**Изучить:** [olcrtc-manager-panel](https://github.com/BigDaddy3334/olcrtc-manager-panel) `/api/settings`, [olcrtc fix/all](https://github.com/openlibrecommunity/olcrtc/tree/fix/all) `docs/`, [j](https://github.com/zarazaex69/j) — только carrier-specific опции.

**Критерий фазы 3:** каждая модалка «Настройки» сохраняет на диск и отражается после reload; секреты (пароли) не отдаются в GET.

---

## Фаза 4 — Панель «±» (добавление/удаление компонентов)

Кнопка в шапке **слева от Panel mem** (символ ± или `Layers` icon).

| ID | Задача | Статус |
|----|--------|--------|
| 4.1 | Drawer «Компоненты VPS» — карточки Tor, Zapret, Split, Мосты | `[ ]` |
| 4.2 | Показать установлено / включено / версия | `[ ]` — из `capabilities` |
| 4.3 | **Добавить** компонент → confirm (ввод `zapret` и т.д.) → `agent-bootstrap` только нужный step | `[ ]` |
| 4.4 | **Удалить** → GitHub-style confirm | `[ ]` |
| 4.5 | Удаление мостов → объединённый confirm мосты+split | `[ ]` |
| 4.6 | После изменения — обновить `deploy-profile.json` | `[ ]` |

**Backend:**

```
POST /api/components/{name}/install
POST /api/components/{name}/uninstall
```

Долгие операции → `202` + `job_id` + polling `/api/jobs/{id}` (логи в JSON lines).

---

## Фаза 5 — Обновление панели из UI + релизы

### 5.1 GitHub Releases (рекомендуется)

| Вопрос | Ответ |
|--------|-------|
| Обязательны ли релизы? | **Нет** для `git pull` update; **да** для удобной проверки версии и артефактов |
| Что в релизе | `version.json`, опционально prebuilt `olcrtc-manager` + checksum; основной путь — `git pull` + build на VPS |
| Версия | semver + суффикс `-alpha.N` / `-prealpha.N` |

| ID | Задача | Статус |
|----|--------|--------|
| 5.1.1 | `version.json` в репо: `{ "panel": "0.9.0-alpha.1", "min_manager": "...", "channel": "alpha" }` | `[ ]` |
| 5.1.2 | GitHub Action: tag → release notes + attach `version.json` | `[ ]` |
| 5.1.3 | `GET /api/updates/check` → сравнение с `origin/main` или release API | `[ ]` |

### 5.2 UI «Состояние проекта»

Кнопка рядом с «Обновить» (или внутри неё) → **большая модалка**:

- версия панели, olcrtc sha, профиль deploy, компоненты
- кнопка **Проверить обновления**
- кнопка **Обновить сейчас** (основная)

### 5.3 Процесс update из UI

| Шаг | Поведение |
|-----|-----------|
| 1 | Confirm: блокировка панели N мин, переподключение инстансов |
| 2 | `POST /api/updates/run` → создаёт lockfile `/var/lib/olcrtc/update.lock` |
| 3 | Фон: `olc-update` с профилем; stdout/stderr в `/var/log/olcrtc-panel-update.log` |
| 4 | UI: сворачиваемый лог + progress timer (оценка из истории `install-state`) |
| 5 | Polling раз в 3–5 с; по завершении — снять lock, reload page |

| ID | Задача | Статус |
|----|--------|--------|
| 5.3.1 | Lock middleware в manager — 503 на мутации кроме `/api/updates/*` | `[ ]` |
| 5.3.2 | Фоновый runner (systemd transient unit или `nohup` с pidfile) | `[ ]` |
| 5.3.3 | UI UpdateModal | `[ ]` |
| 5.3.4 | Периодическая проверка обновлений (раз в 6–24 ч, настраивается) | `[ ]` |
| 5.3.5 | Mini-toast «доступно обновление» — не исчезает сам, есть ✕ | `[ ]` |

---

## Фаза 6 — Уведомления и автодетектор ошибок

### 6.1 Справочник ошибок

| Путь | Назначение |
|------|------------|
| `data/error-catalog.json` | Паттерны regex → title, meaning, fixes[] |
| `data/error-catalog.md` | Человекочитаемая версия для контрибьюторов |

**Пример записи:**

```json
{
  "id": "jitsi-xmpp-auth-fail",
  "pattern": "not-authorized|service-unavailable",
  "sources": ["instance", "olcrtc"],
  "title": "Jitsi: нет anonymous XMPP",
  "meaning": "Хост не даёт гостевой вход",
  "fixes": ["Сменить carrier/хост", "Проверить room_id"],
  "severity": "warning"
}
```

| ID | Задача | Статус |
|----|--------|--------|
| 6.1.1 | Создать `data/error-catalog.json` с известными ошибками из сессий | `[ ]` |
| 6.1.2 | `scripts/olc-error-match.sh` — тест паттерна на строке | `[ ]` |
| 6.1.3 | Go: `errorDetector` — scan tail logs (инстансы, zapret, tor, journal) | `[ ]` |
| 6.1.4 | Cron или goroutine каждые 60 с (настраивается) | `[ ]` |
| 6.1.5 | `GET /api/notifications` — список активных | `[ ]` |
| 6.1.6 | `PATCH /api/notifications/{id}` — dismiss / read | `[ ]` |

### 6.2 UI уведомлений

| Элемент | Описание |
|---------|----------|
| Колокольчик справа сверху | Счётчик непрочитанных |
| Drawer уведомлений | Список; клик → развернуть detail + скрытые логи |
| Toast | Короткий текст, обрезка; крестик скрывает до следующего refresh |
| Настройки уведомлений | Звук, автодетект on/off, интервал, severity filter |

| ID | Задача | Статус |
|----|--------|--------|
| 6.2.1 | `NotificationBell` + `NotificationsDrawer` | `[ ]` |
| 6.2.2 | `NotificationSettingsModal` (из колокольчика и из Settings) | `[ ]` |
| 6.2.3 | В главных Settings — секция «Автодетектор ошибок» | `[ ]` |

### 6.3 Панель «Ошибки» (справа от «Выйти»)

| ID | Задача | Статус |
|----|--------|--------|
| 6.3.1 | Кнопка «Ошибки» — отдельный drawer | `[ ]` |
| 6.3.2 | Источники: инстансы / zapret / tor / split / мосты / olcrtc | `[ ]` |
| 6.3.3 | Только срабатывавшие с severity ≥ warning | `[ ]` |
| 6.3.4 | Разворот → логи **только строки с match** (+ кнопка «полный лог») | `[ ]` |
| 6.3.5 | Ссылка на настройки автодетектора | `[ ]` |

---

## Фаза 7 — Расширенные настройки панели (кнопка «Настройки»)

Сейчас: пароль, subscription path, panel.env частично.

| ID | Задача | Источник | Статус |
|----|--------|----------|--------|
| 7.1 | Аудит логов (retention, max lines) | manager-panel | `[ ]` |
| 7.2 | Публичный URL / TLS insecure | panel.env | `[~]` |
| 7.3 | Дефолты transport/link для новых локаций | manager-panel | `[ ]` |
| 7.4 | Session / auth timeout | `[ ]` |
| 7.5 | Ссылка → Notification settings | `[ ]` |
| 7.6 | Ссылка → Error detector settings | `[ ]` |
| 7.7 | Оптимизация: интервал metrics poll | `[ ]` |

---

## Фаза 8 — Оптимизация нагрузки

| ID | Мера | Статус |
|----|------|--------|
| 8.1 | `/api/metrics` — интервал 10–30 с, pause when tab hidden | `[ ]` |
| 8.2 | Error detector — один проход / мин, дедуп по fingerprint | `[ ]` |
| 8.3 | Update log tail — max 500 KB | `[ ]` |
| 8.4 | Capabilities cache 30 с | `[ ]` |
| 8.5 | Location delete reload — уже async | `[x]` |

---

## Порядок реализации (рекомендуемый)

```
Фаза 0 (баги) ──► Фаза 1 (профиль) + Фаза 2 (capabilities)
        │                    │
        │                    ▼
        │            Фаза 5.3 (UI update) — можно параллельно
        ▼
Фаза 3 по одному: Zapret → Tor → Split → Мосты → OlcRTC
        │
        ▼
Фаза 4 (± компоненты)
        │
        ▼
Фаза 6 (уведомления + каталог) ──► Фаза 7 (settings hub)
        │
        ▼
Фаза 8 (полировка perf)
```

---

## Чеклист перед каждым релизом в репо

- [ ] `BUILD=1 bash scripts/apply-olcrtc-patches.sh` без ошибок
- [ ] `scripts/smoke-test.sh` (если применимо)
- [ ] Обновить `docs/ROADMAP.md` (статусы)
- [ ] Обновить `version.json` + `data/upstream-pins.json` при смене pin
- [ ] `docs/FEATURES.md` / `PATCHES.md`
- [ ] Тест на foreign profile (`--no-tor --no-zapret`) и ru-full
- [ ] `sudo olc-update` на тестовом VPS `111.88.154.165`

---

## Связанные документы

| Документ | Содержание |
|----------|------------|
| [FEATURES.md](./FEATURES.md) | CLI `olc-feature`, текущий UI |
| [PATCHES.md](../patches/PATCHES.md) | Патчи olcrtc |
| [VPS-SETUP.md](./VPS-SETUP.md) | Установка |
| [TOR-BRIDGES.md](./TOR-BRIDGES.md) | Мосты |
| [RESUME-INSTALL.md](./RESUME-INSTALL.md) | install-state |

## Upstream для изучения

| Репозиторий | Зачем |
|-------------|-------|
| [zapret4rocket](https://github.com/IndeecFOX/zapret4rocket) | стратегии, списки, UI-идеи |
| [olcrtc fix/all](https://github.com/openlibrecommunity/olcrtc/tree/fix/all) | сервер, routing, carriers |
| [olcrtc-manager-panel](https://github.com/BigDaddy3334/olcrtc-manager-panel) | базовая панель, settings API |
| [olcbox](https://github.com/alananisimov/olcbox) | клиент: транспорты, VP8/SEI (не сервер) |
| [j](https://github.com/zarazaex69/j) | Jitsi carrier |

---

## Журнал изменений плана

| Дата | Изменение |
|------|-----------|
| 2026-05-26 | Создан документ; зафиксированы фазы 0–8; v3 UI отмечен частично готовым |
