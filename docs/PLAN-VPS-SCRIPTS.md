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
- [ ] **Push на GitHub `main`** — коммит `5207b62` локально; push нужен с машины с токеном/gh
- [x] Локальный / VPS rsync: `apply-olcrtc-patches.sh` + `go build` OK

## Фаза 2 — Скрипт полного удаления

- [x] `uninstall.sh` + `scripts/olc-purge.sh` (одна команда)
- [x] Остановка: manager, olcrtc, timers, zapret
- [x] Удаление: бинарии, `/etc/olcrtc-manager`, `/var/lib/olcrtc`, units, cron, sysctl drop-in
- [x] Флаги: `--purge-repo`, `--keep-tor`, `--dry-run`
- [x] README: секция uninstall
- [x] Повторный purge после успешного install (e2e): `--purge-repo` → чисто

## Фаза 3 — Тест на чистой VPS

- [x] `agent-bootstrap.sh --full` после rsync — **olcrtc-manager active**, `:8888/admin` → **200**
- [ ] `curl | bash` install **с GitHub после push**
- [x] Повторный `uninstall.sh --purge-repo` — manager inactive, бинарии/репо удалены
- [x] Полный цикл: purge → rsync/bootstrap → manager **200** (без GitHub push)

## Фаза 4 — Остальные скрипты репо

- [x] `agent-bootstrap.sh` (full path на тестовой VPS)
- [ ] `install.sh` / `olc-detect-install.sh` end-to-end с GitHub
- [ ] `upstream-sync.sh` / update path (`--update`)
- [ ] Tor: `tor-bridge-pool.sh`, `fetch-bridge-extra-sources.sh` (smoke)
- [ ] `install-zapret-vps.sh` (RU full — частично вызывается из bootstrap)
- [ ] Документация: PATCHES.md, VPS-SETUP.md актуальны

## Фаза 5 — Закрытие

- [ ] Все пункты выше отмечены
- [ ] Краткий отчёт пользователю + команды install/uninstall

---

## Журнал

| Дата | Действие | Результат |
|------|----------|-----------|
| 2026-05-24 | Создан план | — |
| 2026-05-24 | Диагностика 111.88.149.45 | `BASH_SOURCE` unbound; старый apply с `.patch`; manager domains; go 1.26; webtunnel gitlab timeout |
| 2026-05-24 | Фиксы в репо + rsync на VPS | Патчи idempotent; Go 1.23.6; `olc-purge.sh` / `uninstall.sh` |
| 2026-05-24 | `agent-bootstrap.sh --full` | manager **active**, HTTP **200** на `/admin`; webtunnel skip при ошибке SSL |
| 2026-05-24 | `uninstall.sh --purge-repo` | VPS чистая; повторный bootstrap → снова **200** |
| 2026-05-24 | git commit `5207b62` | push с этой VM не удался (нет gh/credentials) |

### Корневые причины (кратко)

1. `set -u` + `curl \| bash` → `BASH_SOURCE[0]` unbound в `install.sh`
2. GitHub `main` без push → старый `apply-olcrtc-patches.sh` с `olcrtc-core.patch`
3. Частичный `main.go.patch` → manager без `ForceTorDomainsFile`
4. Ubuntu `go1.22` vs upstream `go 1.26` в go.mod
5. `webtunnel` clone с gitlab.torproject.org — SSL timeout; раньше ронял весь install

### Команды

```bash
# Установка (после push на GitHub)
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash

# Полное удаление
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/uninstall.sh | sudo bash -s -- --purge-repo

# Из клона
sudo bash /opt/Olc-cost-l/scripts/agent-bootstrap.sh --full
sudo bash /opt/Olc-cost-l/scripts/olc-purge.sh --purge-repo
```
