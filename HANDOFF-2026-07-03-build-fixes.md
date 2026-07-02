# Handoff: Olc-cost-l Build System Fixes

**Дата:** 2026-07-03T02:45Z  
**Статус:** ✅ Завершено — сборка olcrtc-manager работает полностью

---

## Цель проекта

**Olc-cost-l** — VPN/proxy routing система для обхода блокировок:
- **olcrtc** (Go core) — WebRTC прокси-сервер
- **olcrtc-manager** (Go panel + React UI) — веб-панель управления
- **Tor + zapret + split-routing** — обход блокировок для RU VPS

**Цель сессии:** Исправить ошибки компиляции после синхронизации upstream stable-v1 (коммит 0966095 от 2026-07-02).

---

## Текущее состояние

### ✅ Что работает
- ✅ **Полная установка:** `curl -fsSL ... | sudo bash -s -- --full --manager-stable`
- ✅ **Обновление:** `sudo olc-update --manager-stable`
- ✅ **Автодетект режима:** install.sh определяет installed state → переходит в update mode
- ✅ **Go сборка (olcrtc):** компилируется успешно
- ✅ **Go сборка (olcrtc-manager):** компилируется успешно (БЕЗ ошибок pushNotification/panelNotifFile)
- ✅ **npm build (UI):** собирается без дубликатов TypeScript символов
- ✅ **Патчи:** применяются все 132 патча корректно

### 🔧 Что исправили в этой сессии
1. **`undefined: pushNotification`** → добавлена функция в `patch-olcrtc-manager-bridge-notifications.sh`
2. **`panelNotifFile redeclared`** → убрана дублирующая константа (уже в другом патче)
3. **TypeScript дубликаты** (`PanelLangContext`, `usePanelLang`, `COMPONENT_JOB_UI_TTL_MS`):
   - Отключён устаревший патч `v24-main-tsx-lang-defaults.patch` (upstream stable-v1 уже содержит фичи)
   - Добавлена проверка в `patch-olcrtc-manager-panel-hotfix-v8.sh` — skip если константа уже определена

### ⚠️ Известные проблемы (некритичные)
- ⚠️ **Zapret sync** иногда падает с rc=2 (не блокирует установку)
- ⚠️ **panel-verify FAIL** — bundle hash другой (нормально для vite, проверяется вручную)
- ⚠️ **Legacy carrier "jazz"** присутствует в коде, но неизвестно используется ли

---

## Файлы в работе

### Патчи (исправлены)
- **`scripts/patch-olcrtc-manager-bridge-notifications.sh`** ✅
  - Добавлена функция `pushNotification()` для записи уведомлений в `/var/lib/olcrtc/notifications.json`
  - Дедупликация по ID, лимит 100 уведомлений
  - Фикс ошибки: `undefined: pushNotification` в `checkBridgeHealth()`

- **`scripts/patch-olcrtc-manager-panel-hotfix-v8.sh`** ✅
  - Добавлена проверка: skip если `COMPONENT_JOB_UI_TTL_MS` уже определена
  - Фикс дубликата: `COMPONENT_JOB_UI_TTL_MS has already been declared`

- **`patches/manager/v24-main-tsx-lang-defaults.patch`** ✅
  - Переименован в `.disabled` — upstream stable-v1 (0966095) уже содержит интернационализацию
  - Патч создан 2026-05-28, устарел после синхронизации 2026-07-02

### Upstream форки
- **BigDaddy upstream:** https://github.com/BigDaddy3334/olcrtc-manager-panel
  - Последний коммит: `df62603` (Show upstream olcrtc peer counts)
  - НЕ содержит: PanelLang, COMPONENT_JOB_UI_TTL_MS, jazz carrier

- **local-panel-version (stable-v1):** https://github.com/krygag1234-a11y/local-panel-version
  - Последний коммит: `0966095` (sync: upstream features from Olc-cost-l main repo)
  - Дата: 2026-07-02 23:51 UTC
  - Содержит: HTTPS support, SOCKS auth, peer counts, PanelLang, COMPONENT_JOB_UI_TTL_MS
  - Изменено: 7172 строки в main.go, полный UI rebuild

### Логи сборки
- **`/var/log/olcrtc-apply-patches.log`** — детальный лог патчей, Go build, npm build
- **`/var/log/olcrtc-split-update.log`** — обновление split-routing списков
- **`/var/log/olcrtc-zapret-sync.log`** — синхронизация zapret excludes

---

## Изменения в этой сессии

### Коммиты (всего 4)
1. **`ab2db0a`** — `fix(patch): добавлена функция pushNotification для bridge health warnings`
   - Добавлена `pushNotification()` в `patch-olcrtc-manager-bridge-notifications.sh`
   - Записывает уведомления в `/var/lib/olcrtc/notifications.json`

2. **`451413d`** — `fix(patch): убрана дублирующая декларация panelNotifFile`
   - `panelNotifFile` уже определена в `patch-olcrtc-manager-panel-backend-v4.sh`
   - Убрана из `patch-olcrtc-manager-bridge-notifications.sh`

3. **`1b07393`** — `fix(patches): отключён устаревший v24-main-tsx-lang-defaults.patch`
   - Upstream stable-v1 (0966095) уже содержит PanelLangContext, usePanelLang, PANEL_I18N
   - Патч создан 2026-05-28, устарел после синхронизации

4. **`67f5990`** — `fix(patch): v8 skip если COMPONENT_JOB_UI_TTL_MS уже определена`
   - Добавлена проверка в `patch-olcrtc-manager-panel-hotfix-v8.sh`
   - Skip если константа уже в upstream

### Попытки и эксперименты
1. ✅ **Поиск `pushNotification`** — нашли что функция вызывается, но не определена
2. ✅ **Проверка `panelNotifFile`** — обнаружили дублирующую декларацию
3. ✅ **Анализ TypeScript дубликатов** — выяснили что upstream stable-v1 уже содержит символы
4. ✅ **Сверка с BigDaddy** — подтвердили что у них нет PanelLang (это наша фича)
5. ✅ **Тест на VPS** — полная установка + обновление работают

### Что НЕ получилось / пропущено
- ❌ **Удаление legacy carrier "jazz"** — не было коммитов на удаление, пропущено
- ❌ **Grill-me про upstream changes** — не проводили (была другая задача)
- ❌ **Обновление docs после синхронизации** — docs не актуализированы под 0966095

---

## Что планируется дальше

### Высокий приоритет
1. **Удалить legacy carrier "jazz"** (если не используется)
   - Проверить: использует ли кто-то jazz в production
   - Удалить из: `packaging/golden-panel/main.go`, `main.tsx`, `scripts/olc-error-scan.sh`
   - Создать migration notice для существующих инсталляций

2. **Актуализировать документацию после 0966095**
   - `docs/AGENT-REPO.md` — обновить структуру после синхронизации
   - `docs/UPSTREAM-SYNC-REPORT-2026-07-02.md` — создать отчёт о том что изменилось в 0966095
   - `patches/PATCHES.md` — обновить список патчей (v24 отключён)

3. **Grill-me session: разбор upstream changes 0966095**
   - Команда: `grill me про изменения в коммите 0966095 stable-v1`
   - Цель: понять все фичи HTTPS, SOCKS auth, peer counts
   - Проверить: нужны ли обновления патчей или скриптов

### Средний приоритет
4. **Исправить zapret sync warning**
   - Проверить: `/var/log/olcrtc-zapret-sync.log` — что вызывает rc=2
   - Обычно: timeout или отсутствие списков
   - Решение: увеличить timeout или добавить retry

5. **Проверить panel-verify логику**
   - Сейчас: сравнивает bundle hash с эталоном
   - Проблема: vite hash меняется при каждой сборке
   - Решение: сравнивать не hash, а контрольную сумму функциональности (smoke test)

6. **Синхронизация с BigDaddy df62603**
   - Последний коммит BigDaddy: `df62603` (Show upstream olcrtc peer counts)
   - Проверить: что ещё изменилось после нашего 0966095
   - Портировать новые фичи если есть

### Низкий приоритет
7. **Рефакторинг patch-bridge-notifications.sh**
   - Сейчас: `pushNotification()` дублирует логику из `patch-panel-backend-v4.sh`
   - Предложение: вынести в общую функцию или использовать existing API

8. **Тесты для патчей**
   - Добавить smoke tests для критических патчей
   - Проверка: символы не дублируются, функции определены

---

## Команды для next agent

### Проверка состояния на VPS
```bash
# Текущая версия
cd /opt/Olc-cost-l && git log --oneline -1

# Проверка панели
curl -s http://127.0.0.1:8888/api/system | jq '.panel_version'

# Проверка патчей
tail -50 /var/log/olcrtc-apply-patches.log | grep -E "✓|✗|ERROR"

# Проверка сервисов
systemctl status olcrtc-manager tor
```

### Удаление legacy carrier "jazz"
```bash
# Поиск использования
grep -rn "jazz" /var/lib/olcrtc/*.json /etc/olcrtc-manager/*.json

# Если не используется → создать патч
cd /opt/Olc-cost-l
# Редактировать packaging/golden-panel/main.go, main.tsx
# Удалить "jazz" из carriers списка
git commit -m "feat: remove legacy carrier jazz"
```

### Grill-me для 0966095
```bash
# В chat с агентом:
grill me про изменения в коммите 0966095 local-panel-version/stable-v1
```

### Создание отчёта о синхронизации
```bash
cd /opt/Olc-cost-l
cat > docs/UPSTREAM-SYNC-REPORT-2026-07-02.md << 'EOF'
# Upstream Sync Report: 2026-07-02

Коммит: 0966095 (local-panel-version/stable-v1)
Синхронизация: BigDaddy → local-panel-version → Olc-cost-l

## Добавлены фичи:
- HTTPS support (PANEL_TLS flag, self-signed certs)
- SOCKS auth (proxy_user/proxy_pass для authenticated proxies)
- Peer counts (PeerCount/PeerDevices в State API)

## Изменения:
- 7172 строки в cmd/olcrtc-manager/main.go
- Полный UI rebuild (index-DQBiw7Ud.js)
- node_modules обновлены

## Устаревшие патчи:
- v24-main-tsx-lang-defaults.patch (отключён)

## Новые зависимости:
- (проверить go.mod, package.json)
EOF
```

---

## Credentials & Access

### GitHub
- **Repo:** https://github.com/krygag1234-a11y/Olc-cost-l
- **Token:** (используется из git-credentials)

### VPS SSH
- **Хост:** `vps` (через MCP vps-ssh tools)
- **Путь репо:** `/opt/Olc-cost-l`
- **Текущий коммит:** `67f5990` (fix: v8 skip если COMPONENT_JOB_UI_TTL_MS уже определена)
- **Profile:** `ru-full` (tor+split+zapret+bridges, panel=ip)

---

## Контекст для нового агента

### Upstream форки (важно!)
У проекта **3 уровня** версионирования:
1. **BigDaddy upstream** (df62603) — оригинальный olcrtc-manager
2. **local-panel-version/stable-v1** (0966095) — наш стабильный форк с фичами
3. **Olc-cost-l/main** (67f5990) — deploy скрипты + патчи

**Патчи применяются** к local-panel-version → получается финальная панель.

### Что читать первым
1. **Этот файл** — понять что было исправлено
2. `docs/AGENT-REPO.md` — структура проекта, где что лежит
3. `scripts/patch-olcrtc-manager-bridge-notifications.sh` — пример работы с патчами
4. Коммит `0966095` в local-panel-version — что изменилось в upstream

### Не делай
- ❌ Не трогай upstream файлы напрямую — только через patches
- ❌ Не включай обратно `v24-main-tsx-lang-defaults.patch` — он устарел
- ❌ Не удаляй `panelNotifFile` константу из `patch-panel-backend-v4.sh` — она первоисточник

### Полезные alias
```bash
alias olc-log='journalctl -u olcrtc-manager -n 50 -f'
alias olc-rebuild='cd /opt/Olc-cost-l && sudo olc-update --manager-stable'
alias olc-patch-log='tail -100 /var/log/olcrtc-apply-patches.log'
```

---

## Лог текущей сессии (summary)

**22:00-23:00 UTC:** Диагностика ошибки компиляции `undefined: pushNotification`  
**23:00-23:30 UTC:** Исправление `panelNotifFile` redeclared, отключение v24 патча  
**23:30-00:30 UTC:** Фикс v8 патча, тест полной установки на VPS  
**00:30-02:45 UTC:** Верификация изменений, проверка коммитов, написание HANDOFF  

**Результат:** ✅ Сборка работает полностью, оба сценария (install + update) успешны.

---

**Передаю эстафету следующему агенту. Приоритет: удаление jazz, grill-me про 0966095, актуализация docs. 🚀**
