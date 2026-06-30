# AGENT-REPO.MD: Техническая архитектура репозитория Olc-cost-l

> **ИНСТРУКЦИЯ ДЛЯ ИИ-АГЕНТА:**
> Этот документ является «Картой кода» проекта Git-репозитория.
> - **Твоя роль:** Ты — Senior Fullstack & DevOps инженер-архитектор.
> - **Правило патчинга:** Код в `./patches/` перекрывает upstream. Изменения требуют `./scripts/apply-olcrtc-patches.sh`.
> - **Цель:** Понимание архитектуры без создания «костылей».

**Дата создания:** 2026-06-30  
**Репозиторий:** https://github.com/krygag1234-a11y/Olc-cost-l  
**Анализ:** Локальный репозиторий + VPS

---

## 0. КЛЮЧЕВЫЕ КОМПОНЕНТЫ И ВЕРСИОНИРОВАНИЕ

| Компонент | Upstream | Версионирование |
|-----------|----------|-----------------|
| **olcrtc** | [openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc) `master` | **Pinned SHA** в `data/upstream-pins.json` — контролируемое обновление для стабильности |
| **olcrtc-manager** | [BigDaddy3334/olcrtc-manager-panel](https://github.com/BigDaddy3334/olcrtc-manager-panel) `main` | Зависит от флага установки (см. ниже) |
| **local-panel-version** | Стабильный форк manager | [krygag1234-a11y/local-panel-version](https://github.com/krygag1234-a11y/local-panel-version) `stable-v1` | Используется при `--manager-stable` |

### Подход к версионированию

**BigDaddy3334 (upstream панели):**
- Всегда клонирует **HEAD master** из `openlibrecommunity/olcrtc` (без пиннинга)
- Переменная `OLCRTC_REF=master` в его `install.sh`
- Риск: новый коммит может сломать сборку без предупреждения

**Наш подход (Olc-cost-l):**
- **olcrtc:** Pinned SHA в `data/upstream-pins.json` (например `52aea2d`)
- **olcrtc-manager:** Зависит от флага:
  - `--manager-stable` → fork `local-panel-version` stable-v1 (рекомендуется)
  - `--manager-latest` → upstream BigDaddy3334 HEAD
  - Без флага → pinned SHA из `upstream-pins.json`
- **Преимущество:** Контролируемое обновление после тестирования, стабильность production

**Важно:** olcrtc-manager **НЕ хардкодит** версию olcrtc внутри себя — панель запускает бинарник по пути `OLCRTC_PATH=/usr/local/bin/olcrtc`. Сборка olcrtc и manager — независимые процессы в `apply-olcrtc-patches.sh`.

---

## 1. ПОЛНАЯ СТРУКТУРА РЕПОЗИТОРИЯ

```
Olc-cost-l/
├── install.sh                    # Главный установщик (324 строки)
├── uninstall.sh                  # Полное удаление (162 строки)
├── version.json                  # Версия проекта
├── .env.example                  # Пример переменных окружения
│
├── data/                         # Конфигурационные данные
│   ├── deploy-profiles/          # Профили установки (6 файлов)
│   │   ├── ru-full.json          # RU VPS: Tor+split+zapret+bridges
│   │   ├── foreign-minimal.json  # Foreign VPS: только панель
│   │   ├── foreign-warp.json     # Foreign VPS: WARP proxy
│   │   ├── foreign-tor.json      # Foreign VPS: Tor без split
│   │   ├── ru-no-zapret.json     # RU VPS без zapret
│   │   └── custom.json           # Кастомный профиль
│   ├── upstream-pins.json        # Pinned SHA upstream компонентов
│   ├── error-catalog.json        # Каталог ошибок для автодетектора
│   ├── zapret-strategies/        # Стратегии zapret DPI
│   ├── zapret-community-excludes/ # Исключения из zapret
│   └── zapret4rocket/            # Конфиги zapret4rocket
│
├── docs/                         # Документация (20+ файлов)
│   ├── VPS-SETUP.md              # Полная установка
│   ├── TOR-BRIDGES.md            # Пул мостов, ротация
│   ├── SPLIT-ROUTING.md          # Split маршрутизация
│   ├── QUICKSTART-RU.md          # Быстрый старт
│   ├── API-ENDPOINTS.md          # API эндпоинты
│   ├── CLIENT.md                 # Клиенты
│   ├── FEATURES.md               # Компоненты
│   ├── SECURITY-NETWORK.md       # Сетевая безопасность
│   ├── UPDATE.md                 # Обновление
│   ├── UPSTREAM-SYNC.md          # Синхронизация upstream
│   ├── config.example.json       # Пример конфига
│   └── ...
│
├── packaging/                    # Компоненты для сборки
│   ├── golden-panel/             # Pre-патченная панель
│   │   ├── main.go               # Backend manager (7055 строк)
│   │   ├── main.tsx              # Frontend UI (5897 строк)
│   │   ├── index.css             # Стили UI
│   │   ├── SHA256SUMS            # Checksums
│   │   └── README.md             # Документация golden panel
│   ├── olcrtc-manager/           # Конфиги manager
│   ├── systemd/                  # systemd unit files (7 файлов)
│   │   ├── olcrtc-manager.service
│   │   ├── olcrtc-tor-bridge-pool.{service,timer}
│   │   ├── olcrtc-tor-bridge-monitor.{service,timer}
│   │   └── olcrtc-tor-bridge-deep.{service,timer}
│   └── vps-snapshot/             # Инструменты для снепшотов
│
├── patches/                      # Патчи для upstream
│   ├── PATCHES.md                # Документация патчей (17KB)
│   ├── olcrtc-routing-cidr.go    # CIDR matcher (1701 байт)
│   ├── olcrtc-routing-domains.go # Domain matcher (3678 байт)
│   ├── olcrtc-core.patch         # Core патч (5663 байт)
│   ├── olcrtc-dial-route-log.patch
│   ├── olcrtc-domains-split.patch
│   ├── olcrtc-manager-main.go.patch (11993 байт)
│   ├── olcrtc-session-direct-cidrs.patch
│   ├── olcrtc-session-domains.patch
│   └── manager/                  # Патчи для manager panel
│
└── scripts/                      # 158+ shell-скриптов
    ├── install.sh                # (в корне, но часть экосистемы)
    ├── agent-bootstrap.sh        # Основной bootstrap (23KB)
    ├── apply-olcrtc-patches.sh   # Применение патчей (29KB)
    ├── apply-golden-panel.sh     # Копирование golden-panel
    │
    ├── lib-*.sh                  # Библиотеки функций (14 файлов)
    │   ├── lib-tui.sh            # Terminal UI (9773 байт)
    │   ├── lib-olc-core.sh       # Основные функции
    │   ├── lib-olc-ru.sh         # RU-специфичные функции (8931 байт)
    │   ├── lib-deploy-profile.sh # Deploy profiles (18KB)
    │   ├── lib-install-state.sh  # Resumable install (4064 байт)
    │   ├── lib-disk-preflight.sh # Проверка диска (14KB)
    │   ├── lib-vps-backup.sh     # VPS backup (4515 байт)
    │   ├── lib-webtunnel-build.sh # Webtunnel build (6182 байт)
    │   ├── lib-cache-cleanup.sh  # Очистка кэшей
    │   ├── lib-git-safe.sh       # Git safe directory
    │   ├── lib-swap-auto.sh      # Автоматический swap
    │   ├── lib-component-check.sh # Проверка компонентов
    │   ├── lib-github-token.sh   # GitHub token helper
    │   └── lib-output.sh         # Форматирование вывода
    │
    ├── patch-*.sh                # 158 идемпотентных патчей
    │   ├── patch-olcrtc-core.sh
    │   ├── patch-olcrtc-jitsi-extras.sh
    │   ├── patch-olcrtc-jitsi-join-retry.sh
    │   ├── patch-olcrtc-manager-bridge-pool-job.sh
    │   ├── patch-olcrtc-manager-component-settings-v*.sh (5 версий)
    │   └── ... (полный список в разделе 3)
    │
    ├── fetch-*.sh                # Скрипты загрузки списков (10 файлов)
    │   ├── fetch-bridge-extra-sources.sh
    │   ├── fetch-ru-direct-domains.sh
    │   ├── fetch-ru-cidrs.sh
    │   ├── fetch-ru-blocked-tor-domains.sh
    │   ├── fetch-geosite-ru-domains.sh
    │   ├── fetch-force-tor-domains.sh
    │   ├── fetch-cdn-direct.sh
    │   ├── fetch-player-cdn-domains.sh
    │   ├── fetch-ru-player-cdn.sh
    │   └── fetch-zapret-community-excludes.sh
    │
    ├── olc-*.sh                  # CLI утилиты (22 файла)
    │   ├── olc-update.sh         # Обновление системы
    │   ├── olc-feature.sh        # Toggle компонентов
    │   ├── olc-split-analyze.sh  # Анализ split
    │   ├── olc-vps-backup.sh     # Backup VPS
    │   ├── olc-vps-snapshot.sh   # Snapshot VPS
    │   ├── olc-disk-check.sh     # Проверка диска
    │   ├── olc-cleanup-caches.sh # Очистка кэшей
    │   ├── olc-purge.sh          # Полное удаление
    │   ├── olc-component-job.sh  # Job компонентов
    │   ├── olc-component-remove.sh # Удаление компонента
    │   ├── olc-error-scan.sh     # Сканирование ошибок
    │   ├── olc-error-match.sh    # Сопоставление с catalog
    │   ├── olc-profile.sh        # Управление профилями
    │   ├── olc-detect-install.sh # Детект установки
    │   ├── olc-export-golden-panel.sh # Экспорт golden panel
    │   ├── olc-git-push.sh       # Git push helper
    │   ├── olc-panel-refresh-local.sh # Локальный refresh
    │   ├── olc-panel-update-run.sh # Обновление панели
    │   ├── olc-panel-verify.sh   # Верификация панели
    │   ├── olc-sync-from-vps.sh  # Синхронизация с VPS
    │   ├── olc-sync-panel-host.sh # Синхронизация хоста
    │   └── olc-zapret-apply-strategy.sh # Стратегии zapret
    │
    ├── install-*.sh              # Установка компонентов (5 файлов)
    │   ├── install-go-toolchain.sh
    │   ├── install-tor-pluggable-transports.sh
    │   ├── install-warp.sh
    │   ├── install-zapret-vps.sh
    │   └── configure-tor-exit.sh
    │
    └── healthcheck.sh            # Проверка здоровья системы
```

---

## 2. СКВОЗНАЯ АНАТОМИЯ: UI → BACKEND → ПАТЧИ → RUNTIME

### 2.1 ComponentSettingsModal — Центр настроек компонентов

**Расположение:** `./packaging/golden-panel/main.tsx:2773-3435`

#### UI Слой (React TypeScript):

**Компонент:**
```typescript
function ComponentSettingsModal({ 
  feature,  // "tor" | "zapret" | "split" | "bridges" | "warp" | "webtunnel"
  onClose 
}: { feature: FeatureName; onClose: () => void })
```

**State управление (строки 2783-2792):**
- `settings: Record<string, unknown>` — текущие настройки компонента
- `splitAnalyzeTarget: string` — URL/домен для анализа (только для split)
- `splitAnalysis: Record<string, unknown> | null` — результаты анализа
- `splitExpanded: Record<string, boolean>` — развернутые секции
- `msg: string` — сообщения для пользователя
- `saving: boolean` — индикатор сохранения
- `instanceDefaultsOpen: boolean` — открыта ли модалка defaults

**Ключевые функции:**
1. **setStr(key, value)** (строка 2877):
   ```typescript
   const setStr = (key: string, value: string) => 
     setSettings((s) => ({ ...s, [key]: value }));
   ```

2. **reloadSettings()** (строка 2889-2895):
   ```typescript
   const reloadSettings = async () => {
     const res = await fetch(`/api/settings/${feature}`, { cache: "no-store" });
     const body = await res.json();
     setSettings(body.settings ?? {});
   };
   ```

3. **handleSplitAnalyze()** (строка 2900-2918) — только для feature="split":
   ```typescript
   const handleSplitAnalyze = async () => {
     if (!splitAnalyzeTarget) {
       setSplitAnalyzeMsg("Укажите URL или домен");
       return;
     }
     setSplitAnalyzeMsg("Анализируем...");
     try {
       const res = await fetch("/api/split/analyze", {
         method: "POST",
         body: JSON.stringify({ target: splitAnalyzeTarget })
       });
       const body = await res.json();
       setSplitAnalysis(body.result ?? body);
       setSplitAnalyzeMsg("Анализ завершен");
     } catch (e) {
       setSplitAnalyzeMsg(e.message);
     }
   };
   ```

4. **handleSave()** (строка 2832-2870):
   ```typescript
   const handleSave = async () => {
     setSaving(true);
     setMsg("");
     try {
       const res = await fetch(`/api/settings/${feature}`, {
         method: "POST",
         headers: { "Content-Type": "application/json" },
         body: JSON.stringify(settings)
       });
       if (!res.ok) throw new Error(await res.text());
       setMsg("Настройки сохранены");
       setTimeout(() => onClose(), 1500);
     } catch (e) {
       setMsg("Ошибка: " + e.message);
     } finally {
       setSaving(false);
     }
   };
   ```

#### API Слой (Backend main.go):

**GET /api/settings/:component**
- **Функция:** `handleSettingsGet` (main.go примерно строка 4100)
- **Вызов из UI:** useEffect при монтировании (строка 2812)

- **Логика backend:** Читает конфиг компонента и возвращает JSON
- **Пример для bridges:**
  ```go
  func handleSettingsGet(w http.ResponseWriter, r *http.Request) {
      component := mux.Vars(r)["component"]
      if component == "bridges" {
          data, _ := ioutil.ReadFile("/var/lib/olcrtc/bridge-profiles.json")
          json.NewEncoder(w).Encode(map[string]interface{}{
              "settings": json.RawMessage(data),
          })
      }
  }
  ```

**POST /api/settings/:component**
- **Функция:** `handleSettingsPost` (main.go ~4300)
- **Логика:** Валидация → запись конфига → перезапуск сервиса

#### Патчи (./patches/ и ./scripts/patch-*.sh):

**Применяемые патчи для ComponentSettingsModal:**
1. `patch-olcrtc-manager-component-settings-v5.sh` — последняя версия UI настроек
2. `patch-olcrtc-manager-bridge-profiles-v2.sh` — профили мостов
3. `patch-olcrtc-manager-features-api-v2.sh` — API для features

---

## 3. ПОЛНЫЙ СПИСОК PATCH-СКРИПТОВ (158 файлов)

Все патчи идемпотентные — можно применять повторно.

**Категория: olcrtc (Go backend WebRTC)**
- patch-olcrtc-core.sh
- patch-olcrtc-jitsi-extras.sh — Jitsi 16K payload
- patch-olcrtc-jitsi-join-retry.sh — retry логика
- patch-olcrtc-goolom-reconnect-stable.sh — стабильный reconnect
- patch-olcrtc-goolom-reconnect-no-early-callback.sh
- patch-j-xmpp-bind-fastfail.sh — XMPP быстрый fail

**Категория: olcrtc-manager (Go API backend)**
- patch-olcrtc-manager-core.sh
- patch-olcrtc-manager-bridge-pool-job-v2.sh
- patch-olcrtc-manager-bridge-profiles-v2.sh
- patch-olcrtc-manager-bridge-status-api.sh
- patch-olcrtc-manager-component-settings-v5.sh (последняя версия)
- patch-olcrtc-manager-features-api-v2.sh
- patch-olcrtc-manager-domains.sh — split API
- patch-olcrtc-manager-capabilities.sh
- patch-olcrtc-manager-async-delete.sh

**Категория: UI панели (main.tsx)**
- patch-olcrtc-manager-bridge-list-cards-ui.sh
- patch-olcrtc-manager-bridge-notifications.sh

**158 патчей разбиты на категории — см. apply-olcrtc-patches.sh для полного списка**

---

## 4. DEVELOPER NAVIGATION GUIDE

### Задача: "Доработать live-уведомления"

**Где смотреть:**
1. **UI:** `./packaging/golden-panel/main.tsx:3860` — NotificationPreferencesModal
2. **Backend:** Добавить в `main.go`:
   - `GET /api/notifications` — список уведомлений
   - `POST /api/notifications/ack` — подтверждение прочтения
3. **VPS:** Файл `/var/lib/olcrtc/notifications.json` для хранения
4. **Скрипт:** `./scripts/olc-error-scan.sh` для автодетекции

### Задача: "Изменить логику split-маршрутизации"

**Где править:**
1. **Логика:** `./patches/olcrtc-routing-domains.go` и `olcrtc-routing-cidr.go`
2. **Компиляция:** `./scripts/apply-olcrtc-patches.sh`
3. **Тест на VPS:** Перезапуск olcrtc процессов подхватит новые файлы

### Задача: "Добавить новый carrier"

**Последовательность:**
1. `main.tsx:730` — добавить в массив `carriers`
2. `main.tsx:731` — добавить transports в `transportsByCarrier`
3. `main.tsx:1127` — добавить валидацию в `validateRoomIDInput`
4. `main.tsx:1301` — добавить placeholder в `roomPlaceholder`
5. `main.go` — если нужна специфичная логика spawn в `spawnOlcrtcProcess`

---

**Документ создан:** 2026-06-30  
**Версия:** 1.0  
**Следующий документ:** AGENT-VPS.MD (runtime на VPS)
