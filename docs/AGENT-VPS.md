# AGENT-VPS.MD: Runtime окружение развернутого проекта на VPS

> **ИНСТРУКЦИЯ ДЛЯ ИИ-АГЕНТА:**
> Этот документ — «Карта операционной среды» развернутого Olc-cost-l на VPS.
> - **Твоя роль:** Ты — Site Reliability Engineer (SRE).
> - **Правило безопасности:** Изменения конфигов в `/etc/olcrtc-manager/` требуют рестарта сервиса.
> - **Правило отладки:** Сначала логи (`journalctl`), потом код.
> - **Цель:** Стабильность сервисов, быстрое восстановление при сбоях.

**Дата написания:** 2026-06-30  
**VPS:** `<YOUR_VPS_IP>` (VPS, profile: ru-full)  

---

## 0. УСТАНОВЛЕННЫЕ ВЕРСИИ И ВЕРСИОНИРОВАНИЕ

### 0.1 Установленные бинарники

| Бинарник | Версия/SHA | Источник |
|----------|-----------|----------|
| `/usr/local/bin/olcrtc` | pinned `52aea2d` | [openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc) master + патчи |
| `/usr/local/bin/olcrtc-manager` | `d862ad6cc52b` (+dirty) | [local-panel-version stable-v1](https://github.com/krygag1234-a11y/local-panel-version) + патчи |

### 0.2 Подход к версионированию

**BigDaddy3334 (upstream панели):**
- Всегда клонирует **HEAD master** из `openlibrecommunity/olcrtc` без пиннинга
- Риск: новый коммит может сломать сборку

**Этот VPS (через Olc-cost-l):**
- **olcrtc:** Pinned SHA `52aea2d` из `data/upstream-pins.json`
- **olcrtc-manager:** Установлен с флагом `` → форк `local-panel-version` stable-v1
- **Преимущество:** Контролируемое обновление, стабильность production

**Важно:** olcrtc-manager **НЕ хардкодит** версию olcrtc — панель запускает бинарник по пути `OLCRTC_PATH=/usr/local/bin/olcrtc`. Сборка olcrtc и manager — независимые процессы.

---

## 0.3 СТРУКТУРА ДИРЕКТОРИЙ (временные vs постоянные)

### ⚠️ ВАЖНО: Не все директории постоянные!

**ВРЕМЕННЫЕ (удаляются после сборки):**
```
/tmp/olcrtc-src/                # Upstream olcrtc (Go core)
/tmp/olcrtc-manager-panel/      # Upstream panel (клонируется → патчится → собирается → УДАЛЯЕТСЯ)
```

**ПОСТОЯННЫЕ:**
```
/opt/Olc-cost-l/                          # Git репо проекта (НЕ удаляется)
/opt/Olc-cost-l/packaging/golden-panel/   # Эталон панели (патчится перед копированием)
/usr/local/bin/olcrtc-manager             # Скомпилированный бинарь
/etc/olcrtc-manager/                      # Runtime конфиги
/var/lib/olcrtc/                          # Runtime данные
/var/log/olcrtc-apply-patches.log         # Лог применения патчей
```

### ❌ Частая ошибка AI-агентов

**Неправильно:**
```bash
grep "pattern" /tmp/olcrtc-manager-panel/src/main.tsx
# ❌ Файла УЖЕ НЕТ! Удалён после сборки
```

**Правильно:**
```bash
grep "pattern" /opt/Olc-cost-l/packaging/golden-panel/main.tsx
# ✅ Этот файл НЕ удаляется
```

### Где искать что патч применился

**НЕ ищи в `/tmp/`** — там ничего нет после сборки.

**Ищи в:**
1. `/opt/Olc-cost-l/packaging/golden-panel/main.tsx` — эталон (патчится перед копированием)
2. `/var/log/olcrtc-apply-patches.log` — логи применения

---

## 1. ПРОЦЕССЫ И ИХ ВЗАИМОДЕЙСТВИЕ

### 1.1 Активные процессы (реальные данные с VPS)

**На момент анализа работают:**

```
root  <PID>  olcrtc-manager
  Команда: /usr/local/bin/olcrtc-manager -config /etc/olcrtc-manager/config.json
  Память: ~16 MB
  Порт: :8888 (слушает на 0.0.0.0)
  
root  <PID>  olcrtc (клиент 1)
  Команда: /usr/local/bin/olcrtc /var/lib/olcrtc/manager-run/olcrtc-manager-srv-<HASH>.yaml
  Память: ~35 MB
  Parent: olcrtc-manager
  
root  <PID>  olcrtc (клиент 2)
  Команда: /usr/local/bin/olcrtc /var/lib/olcrtc/manager-run/olcrtc-manager-srv-<HASH>.yaml
  Память: ~32 MB
  Parent: olcrtc-manager

debian-tor  <PID>  tor
  Команда: /usr/bin/tor --defaults-torrc ... -f /etc/tor/torrc --RunAsDaemon 0
  Память: ~82 MB
  SOCKS порт: 127.0.0.1:9050
  Control порт: (не открыт публично)
  Bridges: активны (obfs4 + webtunnel)
```

**Архитектура процессов:**
```
systemd
├─ olcrtc-manager.service
│  ├─ spawn olcrtc процесс для каждого клиента
│  │  ├─ olcrtc srv-<HASH_1>
│  │  └─ olcrtc srv-<HASH_2>
│  └─ REST API :8888
│
└─ tor@default.service
   └─ SOCKS proxy :9050 для EXIT_PROXY
```

### 1.2 Как manager спавнит клиентов

**Процесс создания olcrtc клиента:**

1. **Пользователь создает клиента через UI** → POST /api/clients
2. **Backend (main.go):**
   ```go
   func spawnOlcrtcProcess(client Client, location Location) {
       // Генерирует YAML конфиг
       yamlPath := fmt.Sprintf("/var/lib/olcrtc/manager-run/olcrtc-manager-srv-%d.yaml", 
                                hash(client.ID + location.Name))
       
       config := olcrtcConfig{
           Mode: "server",
           Auth: AuthConfig{Type: "none"},
           Room: RoomConfig{
               ID:  location.Endpoint.RoomID,
               Key: location.Endpoint.Key,
           },
           Net: NetConfig{
               Listen: "0.0.0.0:0", // динамический порт
               Public: getPublicIP(),
           },
       }
       
       // Если link=tor и Tor работает
       if location.Link == "tor" && isTorRunning() {
           config.SOCKS = SOCKSConfig{
               Proxy: "127.0.0.1:9050",
           }
       }
       
       writeYAML(yamlPath, config)
       
       // Запуск процесса
       cmd := exec.Command("/usr/local/bin/olcrtc", yamlPath)
       cmd.Stdout = logFile
       cmd.Stderr = logFile
       cmd.Start()
       
       // Сохранение PID
       clientPIDs[client.ID] = append(clientPIDs[client.ID], cmd.Process.Pid)
   }
   ```

3. **olcrtc процесс:**
   - Читает YAML конфиг
   - Подключается к Jitsi/WB/Telemost через WebRTC
   - Если SOCKS настроен — весь TCP через Tor
   - Если split включен — загружает списки из `/var/lib/olcrtc/`

---

## 2. SYSTEMD ЮНИТЫ (полный разбор 8 юнитов)

### 2.1 olcrtc-manager.service

**Файл:** `/etc/systemd/system/olcrtc-manager.service`

**Содержимое:**
```ini
[Unit]
Description=OlcRTC Manager Panel
Documentation=https://github.com/BigDaddy3334/olcrtc-manager-panel
After=network-online.target tor@default.service
Wants=network-online.target tor@default.service

[Service]
Type=simple
EnvironmentFile=-/etc/olcrtc-manager/panel.env
Environment=OLCRTC_PATH=/usr/local/bin/olcrtc
Environment=OLCRTC_MANAGER_ADDR=0.0.0.0
Environment=OLCRTC_HOST_NETWORK=1
Environment=OLCRTC_EXIT_PROXY=127.0.0.1:9050
ExecStart=/usr/local/bin/olcrtc-manager -config /etc/olcrtc-manager/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s
KillSignal=SIGTERM
TimeoutStopSec=10s

[Install]
WantedBy=multi-user.target
```

**Что делает:**
- Стартует после сети и Tor
- Читает environment из `/etc/olcrtc-manager/panel.env`
- Устанавливает EXIT_PROXY=127.0.0.1:9050 (SOCKS Tor)
- При падении — автоматический рестарт через 5 секунд
- Graceful shutdown: SIGTERM с таймаутом 10s

**Проверка статуса:**
```bash
systemctl status olcrtc-manager
journalctl -u olcrtc-manager -f
```

### 2.2 olcrtc-tor-bridge-pool.{timer,service}

**Timer:** `/etc/systemd/system/olcrtc-tor-bridge-pool.timer`
```ini
[Unit]
Description=Update Tor bridge pool every 6 hours

[Timer]
OnBootSec=5min
OnUnitActiveSec=6h
Persistent=true

[Install]
WantedBy=timers.target
```

**Service:** `/etc/systemd/system/olcrtc-tor-bridge-pool.service`
```bash
ExecStart=/opt/Olc-cost-l/scripts/fetch-bridge-extra-sources.sh
```

**Что делает:**
1. Каждые 6 часов запускается fetch-bridge-extra-sources.sh
2. Скрипт скачивает мосты из:
   - https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/.../TOR_BRIDGES_ALL.txt
3. Обновляет `/var/lib/olcrtc/tor-bridges-pool.txt`
4. Обновляет `/var/lib/olcrtc/bridge-pool-status.json`

### 2.3 olcrtc-tor-bridge-monitor.{timer,service}

**Интервал:** Каждые 30 минут

**Что делает:**
1. Проверяет connectivity текущих мостов
2. Обновляет `/var/lib/olcrtc/tor-bridge-health.tsv`
3. Если >50% мостов падают — отправляет уведомление

**Реальное состояние:**
```
Статус: active, интервал каждые 30мин
```

### 2.4 olcrtc-tor-bridge-deep.{timer,service}

**Интервал:** Каждые 24 часа

**Что делает:**
1. Deep check — реальный Tor bootstrap через каждый мост
2. Запускает tor-bridge-deep-check.sh --from-pool --limit 10
3. Обновляет `/var/lib/olcrtc/tor-bridges-good.txt`

**Реальное состояние:**
```
Статус: active, интервал каждые 24ч
```

### 2.5 olcrtc-network-recovery.service

**Type:** oneshot (не постоянный демон)

**Что делает:**
- Проверяет ping до 8.8.8.8
- Если сеть упала — пытается перезапустить интерфейсы
- Перезапускает olcrtc-manager и tor при необходимости

---

## 3. КОНФИГУРАЦИОННАЯ МАТРИЦА VPS (все файлы)

### 3.1 Основная конфигурация панели

**Директория:** `/etc/olcrtc-manager/`

**Файлы:**
```
-rw-------  audit.log (1224 байт)           # Лог изменений конфига
drwx------  backups/                        # Бэкапы config.json
-rw-------  config.json (3456 байт)         # Главный конфиг клиентов
-rw-------  deploy-profile.json (430 байт)  # Профиль установки
-rw-r--r--  features.env (239 байт)         # Состояние компонентов
-rw-r--r--  panel.env (177 байт)            # Environment переменные
```

#### config.json (структура)

```json
{
  "version": 1,
  "name": "olcrtc-vps",
  "port": 8888,
  "subscription_path": "sub",
  "refresh": "10m",
  "active_location_id": "",
  "clients": [
    {
      "client-id": "<YOUR_CLIENT_ID>",
      "refresh": "10m",
      "quota": {},
      "locations": [
        {
          "name": "Default location",
          "client-id": "<YOUR_CLIENT_ID>",
          "endpoint": {
            "room_id": "https://<JITSI_HOST>/<ROOM_NAME>",
            "key": "<YOUR_ENCRYPTION_KEY>"
          },
          "carrier": "jitsi",
          "transport": {
            "type": "datachannel"
          },
          "link": "tor",
          "data": "data",
          "dns": "8.8.8.8:53"
        }
      ]
    }
  ]
}
```

**Как изменяется:**
- POST /api/config → перезаписывает файл
- Backup создается в `backups/` перед каждым изменением
- После изменения требуется HUP signal или полный restart

#### features.env (реальное содержимое)

```bash
# /etc/olcrtc-manager/features.env
# Values: 1 = enabled, 0 = disabled
OLCRTC_ENABLE_ZAPRET=1
OLCRTC_ENABLE_TOR=1
OLCRTC_ENABLE_SPLIT=1
OLCRTC_ENABLE_WEBTUNNEL=1
OLCRTC_ENABLE_WARP=0
```

**Изменяется через:**
- POST /api/features/:name/toggle
- CLI: `olc-feature tor --disable`

#### deploy-profile.json (реальное содержимое)

```json
{
  "schema": 1,
  "profile_id": "ru-full",
  "label": "RU VPS: Tor + Split + Zapret + Мосты",
  "components": {
    "tor": false,
    "split": false,
    "zapret": false,
    "bridges": true,
    "warp": false
  },
  "panel": {
    "access": "ip",
    "listen_addr": "0.0.0.0"
  },
  "ru_vps": true,
  "update_mode": "incremental",
  "created_at": "<INSTALL_TIMESTAMP>",
  "install_script_fingerprint": "agent-bootstrap"
}
```

**Назначение:** Сохраняет историю установки для resume и update режимов

---

### 3.2 Runtime данные

**Директория:** `/var/lib/olcrtc/`

**Файлы:**
```
-rw-r--r--  bridge-pool-status.json (4031 байт)    # Статистика пула мостов
-rw-r--r--  bridge-profiles.json (209 байт)        # Профили мостов
-rw-r--r--  bridge-rotation.idx (2 байт)           # Индекс ротации
drwxr-xr-x  feature-backups/                       # Бэкапы features
-rw-r--r--  force-tor-domains.txt (456 байт)       # Домены через Tor
-rw-------  install-state.json (378 байт)          # Состояние установки
drwxr-xr-x  lists/                                 # Дополнительные списки
drwx------  manager-run/                           # YAML конфиги olcrtc
-rw-------  manager-sessions.json (181 байт)       # Сессии админа
-rw-r--r--  notifications-state.json (2610 байт)   # Состояние уведомлений
-rw-r--r--  notifications.json (2 байт)            # Активные уведомления
-rw-r--r--  ru-blocked-tor-domains.txt (516KB)     # Заблокир. RU домены
-rw-r--r--  ru-cidrs.txt (178KB)                   # RU CIDR для split
-rw-r--r--  ru-direct-domains.txt (472KB)          # RU домены direct
-rw-r--r--  ru-domains-extra.txt (661 байт)        # Дополнительные RU
-rw-r--r--  ru-geosite-domains.txt (470KB)         # GeoSite RU
-rw-r--r--  ru-player-cdn-domains.txt (1684 байт)  # CDN плееров
-rw-r--r--  tor-bridge-health.tsv (5427 байт)      # Здоровье мостов
-rw-------  tor-bridges-good.txt (8532 байт)       # Проверенные мосты
-rw-------  tor-bridges-good.txt.lock              # Lock file deep-check
-rw-r--r--  tor-bridges-pool.txt (69KB)            # Пул всех мостов
-rw-r--r--  tor-monitor-state.txt (8 байт)         # Состояние монитора
-rw-r--r--  zapret-netrogat-staging.txt (401KB)    # Staging zapret
-rw-r--r--  zapret-sync-report.txt (136 байт)      # Отчет синхронизации
```

#### bridge-profiles.json (реальное содержимое)

```json
{
  "active_profile": "system",
  "profiles": [],
  "system": {
    "auto_update": false,
    "id": "system",
    "label": "Оригинальный",
    "readonly": true,
    "types": "obfs4,webtunnel"
  }
}
```

**Как используется:**
- UI → ComponentSettingsModal (feature="bridges")
- Backend читает при POST /api/bridges/refresh
- Типы мостов (obfs4,webtunnel) фильтруют пул

#### manager-run/ (YAML конфиги клиентов)

```
-rw-------  olcrtc-manager-srv-<HASH_1>.yaml (367 байт)
-rw-------  olcrtc-manager-srv-<HASH_2>.yaml (362 байт)
-rw-------  olcrtc-manager-srv-<HASH_3>.yaml (313 байт)  # старый
-rw-------  olcrtc-manager-srv-<HASH_4>.yaml (313 байт)  # старый
```

**Пример YAML:**
```yaml
mode: server
auth:
  type: none
room:
  id: "https://<JITSI_HOST>/<ROOM_NAME>"
  key: "<YOUR_ENCRYPTION_KEY>"
net:
  listen: "0.0.0.0:0"
  public: "<YOUR_VPS_IP>"
socks:
  proxy: "127.0.0.1:9050"
```

**Жизненный цикл:**
- Создается при POST /api/clients
- Удаляется при DELETE /api/clients/:id
- Читается процессом olcrtc при запуске

---

### 3.3 Tor конфигурация

**Файл:** `/etc/tor/torrc`

**Ключевые параметры (из установки):**
```
SocksPort 127.0.0.1:9050
ControlPort 127.0.0.1:9051

# Bridges (добавляются скриптом)
UseBridges 1
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy
ClientTransportPlugin webtunnel exec /usr/local/bin/webtunnel-client

Bridge obfs4 <BRIDGE_IP>:<PORT> <FINGERPRINT> ...
Bridge webtunnel <BRIDGE_ADDR>:<PORT> <FINGERPRINT> ...
```

**Как обновляются мосты:**
1. UI → "Обновить пул" → POST /api/bridges/refresh
2. Backend вызывает fetch-bridge-extra-sources.sh
3. Скрипт обновляет tor-bridges-pool.txt
4. Backend применяет лучшие N мостов в torrc
5. `systemctl reload tor@default` или restart

---

### 3.4 Zapret конфигурация

**Файл:** `/opt/zapret/config` (реальное, 25KB конфига)

**Ключевые параметры:**
```bash
FWTYPE=iptables
SET_MAXELEM=522288
NFQWS_ENABLE=1
NFQWS_PORTS_TCP=80,443,2053,2083,2087,2096,8443
NFQWS_PORTS_UDP=443
MODE_FILTER=none

# Стратегии для разных сервисов (YouTube, Discord, RKN листы)
NFQWS_OPT="
  --filter-tcp=443,8443 --hostlist=/opt/zapret/extra_strats/TCP/User/1.txt ...
  --filter-udp=443 --hostlist=/opt/zapret/extra_strats/UDP/YT/1.txt ...
"
```

**Изменяется через:**
- POST /api/settings/zapret → backend вызывает `olc-zapret-apply-strategy.sh`
- Рестарт не требуется (iptables обновляются на лету)

---

## 4. ПОРТЫ И СЕТЕВАЯ АРХИТЕКТУРА

### 4.1 Открытые порты (реальные с VPS)

**Проверка:** `ss -tlnp | grep -E "(:8888|:9050|:9051|:40000)"`

```
LISTEN  127.0.0.1:9050   tor                    # Tor SOCKS proxy
LISTEN  *:8888           olcrtc-manager          # Panel HTTP API
```

**Полная матрица портов:**

| Порт | Процесс | Bind | Назначение |
|------|---------|------|------------|
| 8888 | olcrtc-manager | 0.0.0.0 | HTTP API панели (публичный) |
| 9050 | tor | 127.0.0.1 | SOCKS5 proxy (внутренний) |
| 9051 | tor | 127.0.0.1 | Control port (внутренний) |
| 40000 | warp-svc | 127.0.0.1 | WARP SOCKS (если установлен) |
| random | olcrtc (каждый) | 0.0.0.0 | WebRTC STUN/TURN |

**Траффик flow:**
```
Пользователь (Olcbox)
    ↓
http://<YOUR_VPS_IP>:8888/<YOUR_CLIENT_ID>/
    ↓
olcrtc-manager :8888 (REST API)
    ↓ spawn
olcrtc процесс (WebRTC)
    ↓ (если link=tor)
SOCKS proxy 127.0.0.1:9050 (Tor)
    ↓ (если split enabled)
Проверка домена в ru-direct-domains.txt
    ├─ RU домен → Direct VPS
    └─ Foreign → Tor exit node
```

---

## 5. ЛОГИ И ДИАГНОСТИКА

### 5.1 Основные логи

**olcrtc-manager:**
```bash
journalctl -u olcrtc-manager -f
journalctl -u olcrtc-manager --since "1 hour ago"
```

**Tor:**
```bash
journalctl -u tor@default -f
```

**olcrtc процессы клиентов:**
```bash
# Если есть отдельные лог-файлы
ls -la /var/log/olcrtc/
tail -f /var/log/olcrtc/olcrtc-<client-id>-<hash>.log
```

**Системные события:**
```bash
journalctl -xe --since "30 minutes ago"
```

### 5.2 Проверка здоровья компонентов

**Tor connectivity:**
```bash
curl --socks5 127.0.0.1:9050 https://check.torproject.org/api/ip
# Ожидается: {"IsTor": true}
```

**Panel API:**
```bash
curl http://localhost:8888/api/capabilities
```

**Bridges status:**
```bash
cat /var/lib/olcrtc/tor-bridge-health.tsv
```

**Split routing lists:**
```bash
wc -l /var/lib/olcrtc/ru-direct-domains.txt
wc -l /var/lib/olcrtc/ru-cidrs.txt
```

---

## 5.5 DEBUG ПАТЧЕЙ НА VPS

### Проверка логов применения

```bash
# Последние 100 строк лога патчей:
tail -100 /var/log/olcrtc-apply-patches.log

# Найти конкретный патч:
grep 'patch-selective-randomization-ui' /var/log/olcrtc-apply-patches.log

# Найти ошибки:
grep -E 'error|failed|ERROR|not found' /var/log/olcrtc-apply-patches.log | tail -20
```

### Проверка что патч применился к golden-panel

```bash
# Проверить наличие маркера:
grep -n 'SelectiveRandomizationPanel' /opt/Olc-cost-l/packaging/golden-panel/main.tsx

# Посчитать упоминания (должно быть конкретное число):
grep -c 'selectiveRandomizationOpen' /opt/Olc-cost-l/packaging/golden-panel/main.tsx
# Expected output: 6

# Показать контекст вокруг маркера:
grep -A 5 -B 5 'SelectiveRandomizationPanel' \
  /opt/Olc-cost-l/packaging/golden-panel/main.tsx | head -20
```

### Ручное тестирование патча на чистом upstream

```bash
# 1. Клонировать чистый upstream
cd /tmp && rm -rf test-panel
git clone --depth 1 \
  https://github.com/krygag1234-a11y/local-panel-version.git test-panel

# 2. Запустить патч
bash /opt/Olc-cost-l/scripts/patch-NAME.sh /tmp/test-panel/src/main.tsx

# 3. Проверить результат
grep -n 'ExpectedPattern' /tmp/test-panel/src/main.tsx

# 4. Проверить idempotency (запустить 2 раза)
bash /opt/Olc-cost-l/scripts/patch-NAME.sh /tmp/test-panel/src/main.tsx
# Output должен быть: [patch-NAME] already applied ✓

# 5. Cleanup
rm -rf /tmp/test-panel
```

### Проверка SHA256SUMS

```bash
# Текущие хэши:
cat /opt/Olc-cost-l/packaging/golden-panel/SHA256SUMS

# Пересчитать вручную для сравнения:
cd /opt/Olc-cost-l/packaging/golden-panel
sha256sum main.go main.tsx

# Хэши ДОЛЖНЫ совпадать с файлом SHA256SUMS!
```

### Типичные проблемы на VPS

**Проблема 1: "Патч в логах, но UI нет в панели"**

```bash
# Диагностика:
grep -c 'PatternFromPatch' /opt/Olc-cost-l/packaging/golden-panel/main.tsx
# Output: 0 ❌

# Root cause: патч применился к /tmp/, но не к golden-panel
# Fix: создать wrapper патч (см. patch-golden-panel-randomization-ui.sh)
```

**Проблема 2: "SHA256 mismatch при копировании"**

```bash
# Лог показывает:
[golden-panel] error: SHA256 mismatch for main.tsx

# Root cause: патч изменил main.tsx но не обновил SHA256SUMS
# Fix: добавить в конец патча:
#   (cd "$GOLDEN_DIR" && sha256sum main.go main.tsx > SHA256SUMS)
```

**Проблема 3: "Git pull не работает (uncommitted changes)"**

```bash
# Error: Your local changes would be overwritten by merge

# Fix 1: stash перед pull
cd /opt/Olc-cost-l && git stash && git pull

# Fix 2: force reset (ОСТОРОЖНО!)
cd /opt/Olc-cost-l && git fetch && git reset --hard origin/main
```

**Проблема 4: "/tmp/olcrtc-manager-panel не существует"**

```bash
# Это НЕ проблема! Директория удаляется после сборки.

# ❌ НЕ делай:
grep 'pattern' /tmp/olcrtc-manager-panel/src/main.tsx
# Error: No such file or directory

# ✅ Делай:
grep 'pattern' /opt/Olc-cost-l/packaging/golden-panel/main.tsx
# ✅ Работает
```

### Полная пересборка после изменения патчей

```bash
# 1. Обновить код на VPS:
cd /opt/Olc-cost-l && git pull

# 2. Запустить полную пересборку:
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | \
  sudo bash -s -- --full

# 3. Проверить что патч применился:
grep -c 'ExpectedPattern' /opt/Olc-cost-l/packaging/golden-panel/main.tsx

# 4. Проверить UI в панели (Ctrl+Shift+R в браузере для очистки кэша)
```

---

## 6. DEVELOPER NAVIGATION (Runtime)

### Задача: "Перезапустить компонент после изменений"

**Tor:**
```bash
systemctl restart tor@default
# Проверка
systemctl status tor@default
journalctl -u tor@default -n 50
```

**Panel:**
```bash
systemctl restart olcrtc-manager
# Все olcrtc процессы клиентов будут перезапущены автоматически
```

**Только конкретный клиент:**
```bash
# Найти PID
ps aux | grep olcrtc | grep <client-id>
# Kill
kill <PID>
# Manager автоматически перезапустит через 5 секунд
```

### Задача: "Проверить почему Split routing не работает"

**Шаги:**
1. Проверить включен ли:
   ```bash
   cat /etc/olcrtc-manager/features.env | grep SPLIT
   # Должно быть: OLCRTC_ENABLE_SPLIT=1
   ```

2. Проверить списки:
   ```bash
   ls -lh /var/lib/olcrtc/ru-*.txt
   # ru-direct-domains.txt должен быть ~472KB
   # ru-cidrs.txt должен быть ~178KB
   ```

3. Проверить olcrtc процессы загружают списки:
   ```bash
   # Посмотреть YAML конфиг клиента
   cat /var/lib/olcrtc/manager-run/olcrtc-manager-srv-*.yaml
   # Должен быть socks.proxy если link=tor
   ```

4. Синхронизировать списки:
   ```bash
   /opt/Olc-cost-l/scripts/fetch-ru-direct-domains.sh
   /opt/Olc-cost-l/scripts/fetch-ru-cidrs.sh
   # Или через UI: Split settings → Sync RU lists
   ```

### Задача: "Мосты Tor не подключаются"

**Диагностика:**
1. Проверить статус Tor:
   ```bash
   systemctl status tor@default
   journalctl -u tor@default -n 100
   ```

2. Проверить мосты в конфиге:
   ```bash
   grep "^Bridge" /etc/tor/torrc
   ```

3. Проверить health мостов:
   ```bash
   cat /var/lib/olcrtc/tor-bridge-health.tsv
   ```

4. Обновить пул:
   ```bash
   systemctl start olcrtc-tor-bridge-pool.service
   # Или через UI: Bridges → Refresh
   ```

5. Применить лучшие мосты:
   ```bash
   # Скрипт автоматически выберет лучшие
   /opt/Olc-cost-l/scripts/tor-bridge-pool.sh --apply
   systemctl restart tor@default
   ```

### Задача: "Изменить стратегию Zapret"

**Через UI:**
1. Settings → Zapret → strategy_id dropdown
2. Выбрать стратегию → Save

**Через CLI:**
```bash
/opt/Olc-cost-l/scripts/olc-zapret-apply-strategy.sh \
  --strategy zeefeer-update-19.02.26
```

**Список доступных стратегий:**
```bash
ls /opt/Olc-cost-l/data/zapret-strategies/
```

---

## 7. BACKUP И RECOVERY

### 7.1 Автоматический backup

**Что бэкапится автоматически:**
- `/etc/olcrtc-manager/backups/` — config.json перед каждым изменением
- `/var/lib/olcrtc/feature-backups/` — features.env перед toggle

### 7.2 Ручной backup

```bash
/opt/Olc-cost-l/scripts/olc-vps-backup.sh
# Создает: /var/backups/olc-vps/backup-YYYY-MM-DD-HHMMSS.tar.gz
```

**Содержимое backup:**
- /etc/olcrtc-manager/
- /var/lib/olcrtc/ (без больших списков)
- /etc/tor/torrc
- /opt/zapret/config

### 7.3 Восстановление

```bash
tar -xzf /var/backups/olc-vps/backup-*.tar.gz -C /tmp/restore
# Ручное копирование нужных конфигов
systemctl restart olcrtc-manager tor@default
```

---

## 8. МОНИТОРИНГ И АЛЕРТЫ

### 8.1 Systemd таймеры (проверка)

```bash
systemctl list-timers | grep olcrtc
```

**Должны быть активны:**
- olcrtc-tor-bridge-pool.timer (каждые 6ч)
- olcrtc-tor-bridge-monitor.timer (каждые 30мин)
- olcrtc-tor-bridge-deep.timer (каждые 24ч)

### 8.2 Автодетектор ошибок

**Конфиг:** `/opt/Olc-cost-l/data/error-catalog.json`

**Скрипт:** `/opt/Olc-cost-l/scripts/olc-error-scan.sh`

**Запуск вручную:**
```bash
/opt/Olc-cost-l/scripts/olc-error-scan.sh
# Результаты в /var/lib/olcrtc/notifications.json
```

**Через UI:**
- Notifications → Autodetector settings → Enable

---

## 9. PRODUCTION CHECKLIST

**Перед запуском в production:**

- [ ] Проверить firewall открыт только :8888
- [ ] Включить SSH-туннель режим (--ssh) если нужна безопасность
- [ ] Настроить автобэкапы через cron
- [ ] Проверить swap (минимум 1GB если RAM < 2GB)
- [ ] Настроить monitoring (опционально)
- [ ] Проверить Tor connectivity
- [ ] Проверить Split routing списки актуальны
- [ ] Настроить deploy-profile для быстрого восстановления

**Регулярное обслуживание:**

- Каждую неделю: проверять логи на ошибки
- Каждый месяц: обновление через `olc-update`
- При проблемах: проверять health мостов
- Backup: автоматически при изменениях, ручной раз в неделю

---

**Документ создан:** 2026-06-30  
**VPS:** `<YOUR_VPS_IP>` (VPS, ru-full profile)  
**Версия:** 1.0  
**Парный документ:** AGENT-REPO.MD (структура кода)
