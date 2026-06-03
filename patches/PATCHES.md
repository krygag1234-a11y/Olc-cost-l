# Патчи относительно upstream (обязательны для Jitsi + панель + RU VPS)

**Обновлено:** 2026-06-03  
**Ветка olcrtc:** [`master`](https://github.com/openlibrecommunity/olcrtc/tree/master) (default в `apply-olcrtc-patches.sh` из `data/upstream-pins.json`)  
**Панель upstream:** [`main`](https://github.com/BigDaddy3334/olcrtc-manager-panel)  
**Панель stable fork:** [`stable-v1`](https://github.com/krygag1234-a11y/local-panel-version) (рекомендуется для установки)  
**Применение:** `scripts/apply-olcrtc-patches.sh` или `upstream-sync.sh --apply`

---

## Версии панели при установке

- **`--manager-stable`** (рекомендуется): Клонирует из stable fork https://github.com/krygag1234-a11y/local-panel-version с уже применёнными патчами
- **`--manager-latest`**: Клонирует HEAD из upstream BigDaddy3334 и применяет патчи
- **без флага**: Клонирует pinned SHA из `upstream-pins.json` и применяет патчи

При использовании `--manager-stable` патчи для панели уже применены в форке, но патчи для `olcrtc` применяются как обычно.

---

## Как применяются патчи (2026-06)

Старый monolithic `olcrtc-core.patch` **не применяется первым** — он ломался на свежем upstream. Вместо этого:

1. Клон `olcrtc` + `olcrtc-manager-panel` в `/tmp/olcrtc-src`, `/tmp/olcrtc-manager-panel`
2. **Idempotent shell-скрипты** `patch-olcrtc-*.sh` (можно гонять повторно)
3. Файлы целиком: `olcrtc-routing-cidr.go`, `olcrtc-routing-domains.go`
4. `install-go-toolchain.sh` → Go ≥1.23, `GOTOOLCHAIN=auto`
5. Сборка в `/usr/local/bin/olcrtc`, `/usr/local/bin/olcrtc-manager`
6. UI панели: `npm ci && npm run build` в clone manager (если есть `npm`)

---

## Архитектура фильтрации типов мостов (obfs4/webtunnel)

**Проблема:** До 2026-06-03 выбор типа моста в UI игнорировался — всегда загружались оба типа.

**Исправлено в 6 коммитах:** `e337cac`, `b51916c`, `20d0e1f`, `e228fd8`, `496817c`, `6e71a34`

### 3 места где было захардкожено `obfs4,webtunnel`:

#### 1. Backend manager (Go патчи)
**Файлы:** `patch-olcrtc-manager-bridge-profiles.sh`, `patch-olcrtc-manager-bridge-pool-job.sh`, `patch-olcrtc-manager-bridge-profiles-v2.sh`

**Было:**
\`\`\`go
types := "obfs4,webtunnel"  // дефолт игнорировал профиль
\`\`\`

**Стало:**
\`\`\`go
types := "obfs4"
prof := readBridgeProfiles()
if sys, ok := prof["system"].(map[string]any); ok {
    if t, ok := sys["types"].(string); ok && strings.TrimSpace(t) != "" {
        types = strings.TrimSpace(t)
    }
}
\`\`\`

**Эффект:** Кнопка "Обновить сейчас" в UI теперь читает `types` из `/var/lib/olcrtc/bridge-profiles.json`

---

#### 2. Bash скрипты (pool merge)
**Файл:** `scripts/tor-bridge-pool.sh` (строка ~78)

**Было:**
\`\`\`bash
# merge с ВСЕ старыми мостами из пула
grep -E '^Bridge ' "\$POOL_FILE" || true
\`\`\`

**Стало:**
\`\`\`bash
# фильтр старого пула по BRIDGE_TYPES
if [[ "\$BRIDGE_TYPES" == *"obfs4"* ]] && [[ "\$BRIDGE_TYPES" != *"webtunnel"* ]]; then
    grep -E '^Bridge (obfs4|vanilla) ' "\$POOL_FILE" || true
elif [[ "\$BRIDGE_TYPES" == *"webtunnel"* ]] && [[ "\$BRIDGE_TYPES" != *"obfs4"* ]]; then
    grep -E '^Bridge webtunnel ' "\$POOL_FILE" || true
else
    grep -E '^Bridge ' "\$POOL_FILE" || true
fi
\`\`\`

**Эффект:** При смене `obfs4` → `webtunnel` старые obfs4 мосты НЕ попадают в новый пул

---

#### 3. Bash скрипты (selection)
**Файл:** `scripts/tor-bridge-pool.sh` функция `select_active_bridges()` (строка ~168)

**Было:**
\`\`\`bash
# выбор ВСЕХ мостов из пула без фильтрации
for line in "\${candidates[@]}"; do
\`\`\`

**Стало:**
\`\`\`bash
for line in "\${candidates[@]}"; do
    # Фильтр по BRIDGE_TYPES
    if [[ "\$BRIDGE_TYPES" == *"obfs4"* ]] && [[ "\$BRIDGE_TYPES" != *"webtunnel"* ]]; then
        [[ "\$line" == *" webtunnel "* ]] && continue
    elif [[ "\$BRIDGE_TYPES" == *"webtunnel"* ]] && [[ "\$BRIDGE_TYPES" != *"obfs4"* ]]; then
        [[ "\$line" == *" obfs4 "* ]] && continue
    fi
\`\`\`

**Эффект:** В `/etc/tor/bridges.conf` попадают ТОЛЬКО мосты нужного типа

---

### Поток данных:

\`\`\`
UI селект → bridge-profiles.json → Manager API → runBridgePoolRefresh(types)
                                                         ↓
                    tor-bridge-pool.sh --fetch --types \$types
                                                         ↓
              fetch-bridge-extra-sources.sh (фильтр URL по типу)
                                                         ↓
                         parse + merge (фильтр старого пула)
                                                         ↓
                              /var/lib/olcrtc/tor-bridges-pool.txt
                                                         ↓
                    select_active_bridges() (фильтр по BRIDGE_TYPES)
                                                         ↓
                                   /etc/tor/bridges.conf
\`\`\`

### UI патч (TypeScript):
**Файл:** `patch-olcrtc-manager-panel-ui-v6.sh` (строка 149)

**Было:**
\`\`\`tsx
value={String(sys.types ?? "obfs4,webtunnel")}
\`\`\`

**Стало:**
\`\`\`tsx
value={String(sys.types ?? "obfs4")}
\`\`\`

**Дополнительный патч:** `patch-olcrtc-manager-panel-ui-bridges-types-fix.sh` исправляет дефолты в v7-v10

---

### Тестирование:

\`\`\`bash
# Проверка текущего типа
cat /var/lib/olcrtc/bridge-profiles.json | jq -r '.system.types'

# Пересборка пула
bash /opt/Olc-cost-l/scripts/tor-bridge-pool.sh --fetch --types obfs4

# Проверка пула
grep -c "Bridge obfs4" /var/lib/olcrtc/tor-bridges-pool.txt
grep -c "Bridge webtunnel" /var/lib/olcrtc/tor-bridges-pool.txt

# Применение в torrc
bash /opt/Olc-cost-l/scripts/tor-bridge-pool.sh --apply --types obfs4

# Проверка bridges.conf
grep "^Bridge" /etc/tor/bridges.conf
\`\`\`

---

### Связанные скрипты:

| Скрипт | Роль |
|--------|------|
| `tor-bridge-lib.sh` | Читает types из bridge-profiles.json, load_bridges_extra_urls() фильтрует URL |
| `fetch-bridge-extra-sources.sh` | Вызывает load_bridges_extra_urls() с фильтром |
| `tor-bridge-pool.sh` | Fetch + merge + select + apply |
| `patch-olcrtc-manager-bridge-profiles.sh` | Backend API refresh_pool |
| `patch-olcrtc-manager-bridge-pool-job.sh` | runBridgePoolRefresh() читает профиль |
| `patch-olcrtc-manager-panel-ui-bridges-types-fix.sh` | UI дефолт obfs4 |

---

## olcrtc ([openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc))

| Скрипт / файл | Зачем |
|---------------|--------|
| \`patch-olcrtc-core.sh\` | Jitsi payload **16K−12**; SOCKS split в server |
| \`olcrtc-routing-cidr.go\` | GeoIP RU CIDR matcher |
| \`olcrtc-routing-domains.go\` | Direct по домену |
| \`patch-olcrtc-server-domains.sh\` | \`direct_domains_file\` в server (domain-first) |
| \`patch-olcrtc-server-blocked-tor.sh\` | RF-blocked \`.ru\` → direct + zapret |
| \`patch-olcrtc-server-force-tor.sh\` | YouTube/global → always Tor |
| \`patch-olcrtc-server-route-log.sh\` | Лог \`connect HOST route=direct\|tor\` |
| \`patch-olcrtc-server-reconnect-debounce.sh\` | Debounce smux reconnect (**5s**) |
| \`patch-olcrtc-server-jitsi-no-smux-reconnect.sh\` | Jitsi bridge reconnect **без** smux tear-down |
| \`patch-j-xmpp-bind-fastfail.sh\` | Быстрый fail при Prosody \`bind\` error (не ждать 60s EOF) |
| \`patch-olcrtc-jitsi-join-retry.sh\` v4 | 6 ретраев, nick jitter, **28s** per-attempt (медленный WS cryptopro), cap=2 WS-dial-timeout, **fail-fast** на «no anonymous XMPP», \`Insecure\` из \`OLCRTC_JITSI_INSECURE_TLS\` |
| \`patch-olcrtc-jitsi-extras.sh\` | \`jitsiJoinInsecureTLS()\`, \`bridgeOpenTimeout\` 60s (SCTP / hyperia) |
| \`patch-olcrtc-manager-features-split-tolerant.sh\` | Split toggle не отдаёт 500, если флаг уже записан |
| \`patch-olcrtc-manager-panel-features-v2.sh\` | RU UI + подсказка Logs / panel.env |
| \`patch-olcrtc-manager-stop-action.sh\` | API \`/api/actions/stop\` (остановка инстанса без удаления) |
| \`patch-olcrtc-manager-panel-stop-button.sh\` | Кнопка \`Stop\` в действиях локации |
| \`patch-olcrtc-goolom-reconnect-stable.sh\` | Стабильный reconnect carrier |
| \`patch-olcrtc-goolom-reconnect-no-early-callback.sh\` | Без раннего \`onReconnect(nil)\` |
| \`olcrtc-session-direct-cidrs.patch\` | (legacy) проброс \`direct_cidrs_file\` в session |

Legacy \`.patch\` в \`patches/\` — справочно; при конфликте ориентир на \`patch-*.sh\`.

---

## olcrtc-manager ([BigDaddy3334/olcrtc-manager-panel](https://github.com/BigDaddy3334/olcrtc-manager-panel))

| Скрипт | Зачем |
|--------|--------|
| \`patch-olcrtc-manager-core.sh\` | Логи API, liveness, базовые хуки |
| \`olcrtc-manager-main.go.patch\` | Fallback если нет \`exitProxyReachable\` |
| \`patch-olcrtc-manager-socks.sh\` | SOCKS + \`ForceTorDomainsFile\`, exit proxy |
| \`patch-olcrtc-manager-domains.sh\` | \`direct_domains_file\`, \`blocked_tor\`, force-tor |
| \`patch-olcrtc-manager-link-direct.sh\` | \`link: direct\` на локации |
| \`patch-olcrtc-manager-default-link-tor.sh\` | Новые локации → \`link: tor\` |
| \`patch-olcrtc-manager-panel-link.sh\` | UI шлёт \`link\` в API |
| \`patch-olcrtc-manager-panel-transports.sh\` | Transports Olcbox (DC/VP8/SEI) |
| \`patch-olcrtc-manager-panel-vp8-defaults.sh\` | VP8 **50/50** по умолчанию |
| \`patch-olcrtc-manager-sessions.sh\` | Сессии на диск |
| \`patch-olcrtc-manager-host-network.sh\` | \`HOST_NETWORK\` |
| \`patch-olcrtc-manager-vps-extras.sh\` | \`PUBLIC_URL\`, VPS extras |
| \`patch-olcrtc-manager-room-binding.sh\` | Room ID без лишнего URL |
| \`patch-olcrtc-manager-runtime-dir.sh\` | YAML в \`/var/lib/olcrtc/manager-run\` |
| \`patch-olcrtc-manager-postcss.sh\` | PostCSS для сборки UI |
| \`patch-olcrtc-manager-features.sh\` | \`/api/features\` + \`/api/features/{name}\` для toggle zapret/tor/split/webtunnel |
| \`patch-olcrtc-manager-panel-backend-v4.sh\` | Updates API, jobs, notifications |
| \`patch-olcrtc-manager-git-safe-dir.sh\` | \`runGitShort\`: \`git -c safe.directory=…\` (root manager + deploy-user repo) |
| \`patch-olcrtc-manager-project-status*.sh\` | \`GET /api/project/status\` — Git SHA, stack, patch counters |
| \`patch-olcrtc-manager-panel-project-ui-fix.sh\` | Модалка «Проект»: стек + Git (идемпотентно после ui-v7) |
| \`lib-git-safe.sh\` | \`olc_git\` / \`olc_git_safe_register\` для shell-скриптов`fetch-force-tor-domains.sh\` | YouTube → Tor |
| \`configure-tor-exit.sh\` | ExitNodes EU, exclude RU/CIS |
| \`discover-page-hosts.sh\` | Домены со страницы плеера |
| \`install-zapret-vps.sh\` | Zapret nfqws на direct |
| \`install-warp.sh\` | Cloudflare WARP (proxy mode, SSH route guard) |
| \`sync-zapret-hostlist.sh\` | Hostlist zapret |
| \`data/ru-domains-extra.txt\` | CDN вне \`*.ru\` |

---

## Carriers (Jitsi / WB / Telemost)

| Carrier | Transport | Примечание |
|---------|-----------|------------|
| **jitsi** | datachannel | Стабильный baseline |
| **wbstream** | **vp8channel** 50/50 | Предпочтительнее seichannel |
| **telemost** | datachannel 45/45 | Reconnect debounce в olcrtc |

---

## Обновление upstream

\`\`\`bash
/opt/Olc-cost-l/scripts/upstream-sync.sh --check
sudo /opt/Olc-cost-l/scripts/upstream-sync.sh --apply
sudo /opt/Olc-cost-l/scripts/upstream-sync.sh --apply --zapret
\`\`\`

Логи неудач: \`/var/lib/olcrtc/upstream-review/\`

---

## Клиент Olcbox

| Сборка | URL |
|--------|-----|
| Nightly | https://github.com/alananisimov/olcbox/releases/tag/nightly |
| Releases | https://github.com/alananisimov/olcbox/releases |
