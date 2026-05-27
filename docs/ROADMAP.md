# Olc-cost-l — мастер-план разработки панели

> **Назначение:** единый живой документ. При работе над задачей — открывать этот файл, отмечать статус, не терять контекст на длинных сессиях.  
> **Последнее обновление плана:** 2026-05-27 (полная сверка с репо `a65d9c9` + тест-VPS)  
> **Текущая версия панели (репо):** `0.9.0-pre-alpha.1` (см. `version.json`)

## Легенда статусов

| Статус | Значение |
|--------|----------|
| `[ ]` | не начато |
| `[~]` | частично / альтернатива вместо полного ТЗ |
| `[x]` | сделано в репо + задеплоено на тест |
| `[!]` | блокер / нужно решение |
| `[-]` | отменено / не делаем |

---

## Сводка сверки (2026-05-27)

Сверка: патчи `scripts/patch-olcrtc-manager-*`, shell-скрипты, `data/deploy-profiles/`, состояние тест-VPS (`ru-full`, `olc-update` OK, компоненты установлены, toggles в `features.env` часто `0`).

| Фаза | Готово | Частично | Не сделано | Комментарий |
|------|--------|----------|------------|-------------|
| **0** | 8/8 | — | — | Закрыта |
| **1** | 5/5 | — | — | Профиль + инкрементальный update работают |
| **2** | 3/3 | — | — | `GET /api/capabilities` |
| **3** | 12 | 10 | 5 | strategy select, cidr toggle, zapret reinstall; PT — скрипты |
| **4** | 7/7 | — | 0 | ± + bridges uninstall confirm |
| **5** | 8 | 2 | 0 | toast update 6h, lock 503; progress job — [~] |
| **6** | 9 | 2 | 1 | `olc-error-match.sh`, matched_lines в scan |
| **7** | 0 | 4 | 3 | Hub настроек не собран |
| **8** | 1 | 2 | 2 | Perf-полировка в backlog |

**Частые альтернативы (уже на VPS, не дублировать в UI):**

| В ROADMAP | Сделано иначе |
|-----------|----------------|
| Go `errorDetector` | `scripts/olc-error-scan.sh` + `POST /api/notifications/scan` |
| Whitelist nfqws поля | Raw `nfqws_config` → `data/zapret-olcrtc.config` |
| Редактор всех split-списков | Textarea кастомных доменов + `olc-update` / cron для полного refresh |
| PT checkboxes в UI | `BRIDGE_TYPES` + `tor-bridge-pool.sh` + тип моста в bridge-profiles |
| `--set-profile` в olc-update | `olc-profile set <id>` |
| Lock 503 на все мутации | Lockfile update + 409 на install во время update |

---

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
| 0.1 | **Копировать** в логах инстансов не работает | `[x]` | `patch-olcrtc-manager-panel-ui-v3.sh` — clipboard + fallback |
| 0.2 | В логах **патчей** (Zp/Tor/Sp/Мосты): **Копировать** + **Обновить** | `[x]` | `FeatureLogsModal` |
| 0.3 | **Некорректный client_id** ломает панель | `[x]` | `normalizePanelState` + `PanelErrorBoundary` |
| 0.4 | **Jitsi URL** без `https://` / мусор | `[x]` | `validateRoomIDStrict` |
| 0.5 | Синхронизация header ↔ «Сеть и обход» | `[x]` | `olc-features-changed` (v3) |
| 0.6 | Split только при включённом Tor | `[x]` | UI + `olc-feature.sh` |
| 0.7 | Удаление локации не блокирует панель | `[x]` | `pendingLocations` + async delete |
| 0.8 | Tor/Split toggle без HTTP 500 | `[x]` | deferred restart + api-v2 |

**Критерий приёмки:** Ctrl+Shift+R; bad `client_id` → toast, панель жива; копирование логов работает.

---

## Фаза 1 — Профиль сценария и умный update

`olc-update` → `agent-bootstrap.sh --update` **с учётом** `/etc/olcrtc-manager/deploy-profile.json` (инкрементально: foreign не тянет zapret/split).

### 1.1 Файл отпечатка

| Поле | Путь | Описание |
|------|------|----------|
| Профиль | `/etc/olcrtc-manager/deploy-profile.json` | JSON, schema 1 |
| Шаблоны | `data/deploy-profiles/*.json` | ru-full, foreign-*, custom |

### 1.2 Запись и чтение профиля

| ID | Задача | Статус | Заметки |
|----|--------|--------|---------|
| 1.2.1 | Запись профиля при первом install | `[x]` | `agent-bootstrap.sh` → `profile_from_flags` (не напрямую в `install.sh`) |
| 1.2.2 | `--update` читает профиль, пропускает лишние шаги | `[x]` | `state_step_profile`, `profile_apply_env` |
| 1.2.3 | `olc-update.sh` — `--show-profile`, `--profile <id>` | `[x]` | Смена профиля: `olc-profile set` |
| 1.2.4 | `/usr/local/bin/olc-profile` | `[x]` | symlink из `install.sh` |
| 1.2.5 | Документация | `[x]` | `FEATURES.md`, `VPS-SETUP.md`, `UPDATE.md`, `WARP-OPTIONAL.md` |

**Профили:** `ru-full`, `ru-no-zapret`, `foreign-minimal`, `foreign-tor`, `foreign-warp`, `custom`.

**На тест-VPS:** `profile_id: ru-full`, `update_mode: incremental`, `olc-update --show-profile` OK.

---

## Фаза 2 — Capability API

```
GET /api/capabilities
```

| ID | Задача | Статус | Evidence |
|----|--------|--------|----------|
| 2.1 | `capabilitiesHandler` | `[x]` | `patch-olcrtc-manager-capabilities.sh` |
| 2.2 | `useCapabilities()` в UI | `[x]` | `patch-olcrtc-manager-panel-capabilities.sh` |
| 2.3 | Split без Tor — disabled + tooltip | `[x]` | `requires: ["tor"]` |

---

## Фаза 3 — Настройки слоёв (модалки)

Паттерн backend: `GET/PUT /api/settings/{component}` (`patch-olcrtc-manager-component-settings*.sh`, `settings-actions.sh`).

UI: `FeatureSettingsModal` / формы в `panel-settings-forms*.sh`, `panel-ui-v6`–`v10` — **не** полноценный drawer с вкладками «Опасная зона».

### 3.1 Zapret

| ID | Настройка | Статус | Реально на VPS / в репо |
|----|-----------|--------|-------------------------|
| 3.1.1 | Вкл/выкл, reload | `[x]` | `olc-feature zapret` |
| 3.1.2 | Выбор **стратегии** / пресета | `[x]` | select + `olc-zapret-apply-strategy.sh` |
| 3.1.3 | nfqws параметры (whitelist) | `[~]` | Raw textarea `nfqws_config` → `data/zapret-olcrtc.config` |
| 3.1.4 | Кастом include/exclude хосты | `[x]` | textarea + `/var/lib/olcrtc/zapret-custom/` |
| 3.1.4b | Reload после save | `[x]` | `zapret-sync-excludes.sh --reload-zapret` |
| 3.1.5 | Авто sync списков (cron) | `[x]` | Toggle `auto_sync` → `/etc/cron.d/olcrtc-zapret-sync` |
| 3.1.6 | Полная переустановка из UI | `[x]` | Кнопка + `reinstall` → `olc-component-job.sh` |
| 3.1.7 | Warning: restart → разрыв DPI | `[x]` | Текст-предупреждение в форме zapret |

### 3.2 Tor

| ID | Настройка | Статус | Реально |
|----|-----------|--------|---------|
| 3.2.1 | SOCKS порт | `[~]` | Редактирование `SocksPort` + текст про restart инстансов |
| 3.2.2 | ExitNodes / ExcludeExitNodes | `[x]` | UI + `configure-tor-exit.sh` |
| 3.2.3 | Кастом direct / force-tor / CIDR | `[~]` | Редакторы в **split**, не в tor-модалке |
| 3.2.4 | Авто pool / webtunnel binary | `[~]` | Timers `olcrtc-tor-bridge-*` + кнопка «Обновить пул»; нет одного toggle |
| 3.2.5 | PT checkboxes (obfs4/snowflake/wt) | `[~]` | `BRIDGE_TYPES` в скриптах + select типа в bridge-profiles; snowflake **не** на VPS |
| 3.2.6 | Tor off → split off | `[x]` | `olc-feature.sh` |

**На тест-VPS:** ~23 моста в `bridges.conf`, webtunnel+obfs4, pool ~500 строк, mirror-cry binary.

### 3.3 Split routing

| ID | Настройка | Статус | Реально |
|----|-----------|--------|---------|
| 3.3.1 | Вкл/выкл | `[x]` | `olc-feature split` |
| 3.3.2 | Редактор ru-direct / CDN / carrier hosts | `[~]` | `panel_hosts`, `custom_direct_domains`; счётчик `ru_direct_count` read-only |
| 3.3.3 | force-tor / blocked-tor / custom direct | `[~]` | Textarea → файлы в `/var/lib/olcrtc/` |
| 3.3.4 | CIDR-only mode toggle | `[x]` | checkbox → `OLCRTC_SPLIT_CIDR_ONLY` + `setup-split-ru.sh` |
| 3.3.5 | «Полное обновление списков» + progress | `[~]` | `refresh_lists` → `setup-split-ru.sh` в фоне; **без** progress bar |
| 3.3.6 | Зависимость от Tor | `[x]` | |

### 3.4 Мосты

| ID | Настройка | Статус | Реально |
|----|-----------|--------|---------|
| 3.4.1 | UI «Мосты» (не WebTunnel) | `[x]` | |
| 3.4.2 | Список по типам PT | `[~]` | Tail `bridges.conf` + stats pool; не таблица obfs4/wt |
| 3.4.3 | Добавить свой `Bridge …` | `[x]` | append `bridges.conf` |
| 3.4.4 | Приоритет / ротация | `[~]` | `tor-bridge-pool.sh`, rotate, bridge-profiles — **CLI/timers** |
| 3.4.5 | Delete bridge + hint про split | `[ ]` | |
| 3.4.6 | Warning: только PT, нет exit | `[~]` | Warning если нет webtunnel-client |

### 3.5 OlcRTC

| ID | Настройка | Статус | Реально |
|----|-----------|--------|---------|
| 3.5.1 | panel.env (TLS, URL, timeouts) | `[~]` | OlcRTC settings modal — часть полей |
| 3.5.2 | VP8/SEI defaults | `[x]` | `panel-vp8-defaults.sh` |
| 3.5.3 | Reconnect debounce в UI | `[~]` | Только server patches olcrtc, не в панели |
| 3.5.4 | Клиент olcbox | `[-]` | |
| 3.5.5 | Jitsi join retry / fail-fast | `[x]` | `patch-jitsi-*` |

**Критерий фазы 3 (не достигнут полностью):** не все модалки = полные формы с вкладками; zapret strategy и CIDR-only — главные дыры.

---

## Фаза 4 — Панель «±»

| ID | Задача | Статус | Заметки |
|----|--------|--------|---------|
| 4.1 | Drawer Tor/Zapret/Split/Мосты/**WARP** | `[x]` | `panel-phase456-ui`, warp patches |
| 4.2 | installed / enabled / version | `[x]` | capabilities |
| 4.3 | Install → `olc-component-job.sh` | `[x]` | `POST /api/components/{name}/install` |
| 4.3b | Job log + polling | `[x]` | TTL ~2 мин UI + ~3 мин API (`components-jobs-v3`, `ui-ttl`) |
| 4.4 | Uninstall → feature off | `[x]` | |
| 4.5 | Combined confirm мосты+split | `[x]` | confirm при uninstall bridges |
| 4.6 | Обновление `deploy-profile.json` | `[x]` | `profile_after_component_job` |

**На тест-VPS:** все компоненты **установлены**, toggles в `features.env` = `0` (выкл в UI, пакеты остаются).

---

## Фаза 5 — Update из UI + релизы

### 5.1 GitHub Releases

| ID | Задача | Статус |
|----|--------|--------|
| 5.1.1 | `version.json` + stack | `[x]` |
| 5.1.2 | GitHub Action / `create-github-release.sh` | `[x]` |
| 5.1.3 | `GET /api/updates/check` | `[x]` prerelease-safe + `github.env` на VPS |

### 5.2 UI «Состояние проекта»

| Элемент | Статус |
|---------|--------|
| Модалка: версия, SHA, профиль, компоненты | `[x]` `panel-project-ui-v2` |
| Проверить обновления / Обновить сейчас | `[x]` |
| Релиз стека `v0.9.0-pre-alpha.1` | `[x]` на тест-VPS |

### 5.3 Процесс update

| ID | Задача | Статус | Реально |
|----|--------|--------|---------|
| 5.3.1 | Lock на мутации | `[x]` | `updateGuardMiddleware` → 503 + lockfile |
| 5.3.2 | Фоновый runner | `[x]` | `olc-panel-update-run.sh` |
| 5.3.3 | UI UpdateModal / «Проект» | `[x]` | |
| 5.3.4 | Фоновая проверка 6–24 ч | `[x]` | `UpdateAvailableToast` poll 6h |
| 5.3.5 | Persistent toast «есть update» | `[x]` | toast с ✕ + «Открыть» |

---

## Фаза 6 — Уведомления и автодетектор

| ID | Задача | Статус | Реально |
|----|--------|--------|---------|
| 6.1.1 | `data/error-catalog.json` | `[x]` | |
| 6.1.2 | `scripts/olc-error-match.sh` | `[x]` | CLI тест каталога |
| 6.1.3 | Scan логов | `[x]` | **`olc-error-scan.sh`** (shell), не Go goroutine |
| 6.1.4 | Интервал scan | `[x]` | UI poll 60s + `scan_interval_sec` в notification-settings |
| 6.1.5 | `GET /api/notifications` | `[x]` | |
| 6.1.6 | `PATCH /api/notifications/{id}` | `[x]` | |
| 6.2.1 | NotificationBell + drawer | `[x]` | |
| 6.2.2 | NotificationSettingsModal | `[x]` | `notification-settings.sh`, `panel-ui-v7` |
| 6.2.3 | Автодетектор в главных Settings | `[~]` | Inline panel + event `olc-open-autodetect-settings` |
| 6.3.1 | Кнопка «Ошибки» | `[x]` | |
| 6.3.2 | Источники из catalog | `[x]` | |
| 6.3.3 | severity ≥ warning | `[x]` | error + warning в drawer |
| 6.3.4 | Matched log lines в drawer | `[x]` | `matched_lines` из `olc-error-scan.sh` |
| 6.3.5 | Ссылка на настройки из Errors | `[x]` | кнопка «Настройки автодетектора» |

---

## Фаза 7 — Hub «Настройки»

| ID | Задача | Статус |
|----|--------|--------|
| 7.1 | Log retention / max lines | `[ ]` |
| 7.2 | PUBLIC_URL / insecure TLS | `[~]` в OlcRTC settings |
| 7.3 | Default transport/link для новых локаций | `[~]` в OlcRTC modal, не в hub |
| 7.4 | Session timeout | `[ ]` |
| 7.5 | Link → Notification settings | `[~]` |
| 7.6 | Link → Error detector | `[~]` |
| 7.7 | Metrics poll interval | `[ ]` |

---

## Фаза 8 — Оптимизация

| ID | Мера | Статус | Реально |
|----|------|--------|---------|
| 8.1 | Metrics interval + tab hidden | `[~]` | poll 15s, skip when tab hidden |
| 8.2 | Error dedup / throttle | `[x]` | fingerprint в `olc-error-scan.sh` |
| 8.3 | Update log tail limit | `[~]` | **500 строк**, не 500 KB |
| 8.4 | Capabilities cache 30s | `[x]` | refresh каждые 30s в `useCapabilities` |
| 8.5 | Async location delete | `[x]` | |

---

## Порядок реализации (актуальный backlog)

```
Закрыто: Фаза 0, 1, 2, 4 (кроме 4.5)
Дальше по приоритету:
  3.1.2 zapret strategy select
  3.3.4 CIDR-only toggle
  3.1.6 zapret reinstall button + lock
  4.5 bridges+split confirm
  5.3.4 фоновый check updates
  6.1.2 olc-error-match.sh (dev/test catalog)
  6.3.4 matched lines в Errors drawer
  7.x settings hub
  8.x perf
```

---

## Чеклист перед релизом

- [x] `BUILD=1 bash scripts/apply-olcrtc-patches.sh` на тест-VPS
- [ ] `scripts/smoke-test.sh` (если есть)
- [x] Обновить этот `ROADMAP.md`
- [x] `version.json` / `upstream-pins.json` актуальны для pre-alpha.1
- [x] `olc-update` на demo VPS (см. [PUBLIC-DEMO-VPS.md](./PUBLIC-DEMO-VPS.md))
- [ ] Smoke foreign profile (`--no-tor --no-zapret`) на отдельном хосте

---

## Связанные документы

| Документ | Содержание |
|----------|------------|
| [FEATURES.md](./FEATURES.md) | CLI `olc-feature`, deploy-profile |
| [PATCHES.md](../patches/PATCHES.md) | Патчи olcrtc / manager |
| [VPS-SETUP.md](./VPS-SETUP.md) | Установка, timers |
| [TOR-BRIDGES.md](./TOR-BRIDGES.md) | Пул, mirror-cry, IPv4+url |
| [UPDATE.md](./UPDATE.md) | olc-update, olc-git-push |
| [PUBLIC-DEMO-VPS.md](./PUBLIC-DEMO-VPS.md) | Общий VPS без секретов |
| [RESUME-INSTALL.md](./RESUME-INSTALL.md) | install-state |

## Upstream

| Репозиторий | Зачем |
|-------------|-------|
| [olcrtc fix/all](https://github.com/openlibrecommunity/olcrtc/tree/fix/all) | сервер, routing |
| [olcrtc-manager-panel](https://github.com/BigDaddy3334/olcrtc-manager-panel) | базовая панель |
| [zapret4rocket](https://github.com/IndeecFOX/zapret4rocket) | стратегии DPI |
| [mirror-cry](https://github.com/krygag1234-a11y/mirror-cry) | webtunnel-client binary |
| [olcbox](https://github.com/alananisimov/olcbox) | клиент |

---

## Журнал изменений плана

| Дата | Изменение |
|------|-----------|
| 2026-05-26 | Создан документ; фазы 0–8 |
| 2026-05-27 | Доки: fix/all, olc-update, PUBLIC-DEMO-VPS; TTL component jobs |
| 2026-05-27 | **Полная сверка** с репо + тест-VPS: статусы, таблица альтернатив, backlog |
| 2026-05-27 | ROADMAP backlog: strategy, cidr, errors, update toast, lock 503, `olc-error-match` |
