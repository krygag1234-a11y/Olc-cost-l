# План: скрипты Olc-cost-l + тестовая VPS

**Цель:** довести install/uninstall и остальные скрипты до рабочего состояния на чистой VPS.  
**Тестовая VPS:** `111.88.149.45` (диагностика → purge → повторный install).  
**Не цель:** «просто поднять панель» — цель **исправить репо**.

---

## Фаза 0 — Диагностика (тестовая VPS)

- [x] SSH, снять состояние: `/opt/Olc-cost-l`, бинарии, systemd, tor, логи install
- [x] Зафиксировать корневые причины падения (старые `.patch`, `BASH_SOURCE`, manager domains, go 1.26, webtunnel SSL)
- [x] Записать вывод в журнал (ниже)

## Фаза 1 — Исправление install / apply-patches

- [x] `install.sh`: `curl | bash` без `BASH_SOURCE` unbound
- [x] `apply-olcrtc-patches.sh`: только idempotent `patch-olcrtc-*.sh` (без brittle `olcrtc-core.patch`)
- [x] `patch-olcrtc-manager-domains.sh`: partial struct после main.go.patch
- [x] `install-go-toolchain.sh` + `GOTOOLCHAIN=auto` для go.mod 1.26
- [x] `agent-bootstrap.sh`: webtunnel clone/build не роняет install (WARN + skip)
- [x] **Push на GitHub `main`** — `e935dfa` (токен: `/root/.config/olc-cost-l/github-token`, не в git)
- [x] Локальный / VPS rsync: `apply-olcrtc-patches.sh` + `go build` OK
- [x] `install.sh`: dirty tree на VPS → `reset --hard origin/main` (не ломает update)

## Фаза 2 — Скрипт полного удаления

- [x] `uninstall.sh` + `scripts/olc-purge.sh` (одна команда)
- [x] Остановка: manager, olcrtc, timers, zapret
- [x] Удаление: бинарии, `/etc/olcrtc-manager`, `/var/lib/olcrtc`, units, cron, sysctl drop-in
- [x] Флаги: `--purge-repo`, `--keep-tor`, `--dry-run`
- [x] README: секция uninstall
- [x] Повторный purge после успешного install (e2e): `--purge-repo` → чисто

## Фаза 3 — Тест на чистой VPS

- [x] `agent-bootstrap.sh --full` после rsync — **olcrtc-manager active**, `:8888/admin` → **200**
- [x] `curl | bash` install **с GitHub после push** — manager active, `/admin` 200
- [x] Повторный `uninstall.sh --purge-repo` — manager inactive, бинарии/репо удалены
- [x] Полный цикл: purge → install → purge → install

## Фаза 4 — Остальные скрипты репо

- [x] `agent-bootstrap.sh` (full + `--update`)
- [x] `install.sh` / `olc-detect-install.sh` — detect=installed, update без ошибок
- [x] `upstream-sync.sh --check` и `--apply --no-build`
- [x] Tor: `tor-bridge-pool.sh`, `fetch-bridge-extra-sources.sh` — pool 500+ строк, Tor SOCKS OK
- [x] `install-zapret-vps.sh` + `sync-zapret4rocket.sh --check` (RU full)
- [x] `healthcheck.sh` — exit 0, Tor/panel OK
- [x] Tor fix: без IPv4 webtunnel → obfs4-first (не IPv6 webtunnel на VPS без v6)
- [x] Документация: PATCHES.md, VPS-SETUP.md, TOR-BRIDGES.md актуальны

## Фаза 5 — Закрытие

- [x] Все пункты выше отмечены (кроме doc-косметики)
- [x] Краткий отчёт пользователю + команды install/uninstall

---

## Журнал

| Дата | Действие | Результат |
|------|----------|-----------|
| 2026-05-24 | Создан план | — |
| 2026-05-24 | Диагностика 111.88.149.45 | `BASH_SOURCE` unbound; старый apply с `.patch`; manager domains; go 1.26; webtunnel gitlab timeout |
| 2026-05-24 | Фиксы в репо + rsync на VPS | Патчи idempotent; Go 1.23.6; `olc-purge.sh` / `uninstall.sh` |
| 2026-05-24 | `agent-bootstrap.sh --full` | manager **active**, HTTP **200** на `/admin`; webtunnel skip при ошибке SSL |
| 2026-05-24 | `uninstall.sh --purge-repo` | VPS чистая; повторный bootstrap → снова **200** |
| 2026-05-24 | git push | GitHub main обновлён; токен в `/root/.config/olc-cost-l/github-token` |
| 2026-05-24 | `curl \| bash` install с GitHub | purge → install OK, `/admin` **200** |
| 2026-05-24 | Tor bridges fix | obfs4-first без IPv4 webtunnel; Tor `IsTor:true` |
| 2026-05-24 | `install.sh` update path | detect=installed → `--update`, zapret+panel OK |
| 2026-05-24 | `upstream-sync --apply --no-build` | success |
| 2026-05-24 | Фаза 4 закрыта | healthcheck, bridge pool, zapret smoke OK |

### Корневые причины (кратко)

1. `set -u` + `curl \| bash` → `BASH_SOURCE[0]` unbound в `install.sh`
2. GitHub `main` без push → старый `apply-olcrtc-patches.sh` с `olcrtc-core.patch`
3. Частичный `main.go.patch` → manager без `ForceTorDomainsFile`
4. Ubuntu `go1.22` vs upstream `go 1.26` в go.mod
5. `webtunnel` clone с gitlab.torproject.org — SSL timeout; раньше ронял весь install
6. Только IPv6 webtunnel в пуле → Tor не поднимался на VPS без v6 routing

### Команды

```bash
# Установка
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash

# Обновление (на уже установленной VPS)
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash

# Полное удаление
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/uninstall.sh | sudo bash -s -- --purge-repo

# Из клона
sudo bash /opt/Olc-cost-l/scripts/agent-bootstrap.sh --full
sudo bash /opt/Olc-cost-l/scripts/agent-bootstrap.sh --update
sudo bash /opt/Olc-cost-l/scripts/olc-purge.sh --purge-repo
```
