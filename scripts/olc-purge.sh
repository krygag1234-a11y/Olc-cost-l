#!/usr/bin/env bash
# Full removal of Olc-cost-l / olcrtc-manager / olcrtc stack from this host.
# Safe to run after failed install or for clean re-test.
#
# Usage (from repo root or anywhere):
#   sudo olc-purge                       # полное удаление стека (репо остаётся)
#   sudo olc-purge --yes                 # без интерактивного подтверждения
#   sudo olc-purge --keep-tor            # оставить tor@default + мосты
#   sudo olc-purge --keep-warp           # оставить пакет cloudflare-warp
#   sudo olc-purge --purge-repo          # также удалить /opt/Olc-cost-l
#   sudo olc-purge --purge-all           # repo + go toolchain + все кэши
#   sudo olc-purge --dry-run             # показать, что будет удалено
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
INSTALL_DIR="${OLC_INSTALL_DIR:-/opt/Olc-cost-l}"

KEEP_TOR=0
KEEP_WARP=0
PURGE_REPO=0
PURGE_ALL=0
DRY_RUN=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-tor) KEEP_TOR=1 ;;
    --keep-warp) KEEP_WARP=1 ;;
    --purge-repo) PURGE_REPO=1 ;;
    --purge-all) PURGE_REPO=1; PURGE_ALL=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      sed -n '1,14p' "$0"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
  shift
done

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

# --purge-repo: скрипт лежит внутри удаляемого репо — перезапуститься из /tmp,
# чтобы rm -rf /opt/Olc-cost-l не выбил землю из-под ног у работающего bash.
if [[ "$PURGE_REPO" -eq 1 && -z "${OLC_PURGE_REEXEC:-}" ]]; then
  case "$SCRIPT_DIR" in
    "$INSTALL_DIR"/*)
      SELF_TMP="$(mktemp -d /tmp/.olc-purge-self-XXXXXX)"
      cp -a "$SCRIPT_DIR" "$SELF_TMP/scripts"
      exec env OLC_PURGE_REEXEC=1 OLC_PURGE_SELF_TMP="$SELF_TMP" \
        bash "$SELF_TMP/scripts/$(basename "${BASH_SOURCE[0]}")" \
        $( ((KEEP_TOR)) && echo --keep-tor ) \
        $( ((KEEP_WARP)) && echo --keep-warp ) \
        $( ((PURGE_ALL)) && echo --purge-all || echo --purge-repo ) \
        $( ((ASSUME_YES)) && echo --yes ) \
        $( ((DRY_RUN)) && echo --dry-run )
      ;;
  esac
fi

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

log() { echo "[purge] $*"; }

# Подтверждение (кроме --yes / --dry-run). Терминал ищем через /dev/tty —
# работает и при `curl | sudo bash` (stdin — pipe).
if [[ "$ASSUME_YES" -eq 0 && "$DRY_RUN" -eq 0 ]]; then
  if { [[ -e /dev/tty ]] && : </dev/tty; } 2>/dev/null; then
    echo "" >&2
    echo "⚠️  Будет ПОЛНОСТЬЮ удалён стек Olc-cost-l (панель, olcrtc, zapret, split, мосты)." >&2
    [[ "$KEEP_TOR" -eq 0 ]] && echo "   Tor drop-in'ы olcrtc тоже будут убраны (пакет tor останется)." >&2
    [[ "$PURGE_REPO" -eq 1 ]] && echo "   Репозиторий $INSTALL_DIR тоже будет удалён." >&2
    echo -n "Продолжить? Введите yes: " >&2
    ans=""
    read -r ans </dev/tty || ans=""
    case "${ans,,}" in
      yes|y|да) ;;
      *) echo "Отменено." >&2; exit 0 ;;
    esac
  else
    echo "[purge] Нет терминала для подтверждения. Запустите с --yes для неинтерактивного удаления." >&2
    exit 1
  fi
fi

if [[ -f "$SCRIPT_DIR/lib-disk-preflight.sh" ]]; then
  # shellcheck source=lib-disk-preflight.sh
  source "$SCRIPT_DIR/lib-disk-preflight.sh"
  olc_preflight_disk_space "purge" || exit 1
fi
if [[ -f "$SCRIPT_DIR/lib-cache-cleanup.sh" ]]; then
  # shellcheck source=lib-cache-cleanup.sh
  source "$SCRIPT_DIR/lib-cache-cleanup.sh"
fi
if [[ -f "$SCRIPT_DIR/lib-vps-backup.sh" ]]; then
  # shellcheck source=lib-vps-backup.sh
  source "$SCRIPT_DIR/lib-vps-backup.sh"
  # Skip backup creation during purge to avoid hanging on large backup dirs
  export OLC_VPS_BACKUP_DISABLE=1
fi

stop_unit() {
  local u="$1"
  systemctl stop "$u" 2>/dev/null || true
  systemctl disable "$u" 2>/dev/null || true
}

log "stop services"
stop_unit olcrtc-manager.service
stop_unit olcrtc-network-recovery.service
for u in olcrtc-tor-bridge-pool olcrtc-tor-bridge-monitor olcrtc-tor-bridge-deep; do
  stop_unit "${u}.timer"
  stop_unit "${u}.service"
done
# zapret if we installed it (sysv stop снимает iptables/NFQUEUE правила)
if [[ -x /opt/zapret/init.d/sysv/zapret && "$DRY_RUN" -eq 0 ]]; then
  timeout 60 /opt/zapret/init.d/sysv/zapret stop 2>/dev/null || true
fi
stop_unit zapret.service
stop_unit zapret4rocket.service 2>/dev/null || true

log "kill olcrtc processes"
if [[ "$DRY_RUN" -eq 0 ]]; then
  pkill -f '/usr/local/bin/olcrtc-manager' 2>/dev/null || true
  pkill -f '/usr/local/bin/olcrtc ' 2>/dev/null || true
  sleep 1
  pkill -9 -f '/usr/local/bin/olcrtc' 2>/dev/null || true
fi

log "remove systemd units (olcrtc-* + zapret, включая drop-in каталоги)"
if [[ "$DRY_RUN" -eq 1 ]]; then
  ls -d /etc/systemd/system/olcrtc-* /etc/systemd/system/zapret.service 2>/dev/null | sed 's/^/[dry-run] rm -rf /' || true
else
  rm -rf /etc/systemd/system/olcrtc-* 2>/dev/null || true
  rm -f /etc/systemd/system/zapret.service /etc/systemd/system/zapret4rocket.service 2>/dev/null || true
  rm -f /etc/systemd/system/multi-user.target.wants/olcrtc-* \
        /etc/systemd/system/multi-user.target.wants/zapret.service 2>/dev/null || true
fi
run systemctl daemon-reload
if [[ "$DRY_RUN" -eq 0 ]]; then
  systemctl reset-failed 2>/dev/null || true
fi

log "remove cron"
run rm -f /etc/cron.d/olcrtc-healthcheck \
          /etc/cron.d/olcrtc-bridge-pool \
          /etc/cron.d/olcrtc-zapret-sync \
          /etc/cron.d/zapret-sync
if [[ "$DRY_RUN" -eq 0 ]] && grep -qE 'healthcheck\.sh|olcrtc|Olc-cost-l' /etc/crontab 2>/dev/null; then
  sed -i -e '\|healthcheck\.sh|d' -e '\|olcrtc|d' -e '\|Olc-cost-l|d' /etc/crontab || true
fi

log "remove binaries and CLI symlinks"
run rm -f /usr/local/bin/olcrtc /usr/local/bin/olcrtc-manager /usr/local/bin/webtunnel-client
# Все olc-* команды — симлинки в репо (olc-update, olc-feature, olc-purge, …)
if [[ "$DRY_RUN" -eq 1 ]]; then
  ls /usr/local/bin/olc-* 2>/dev/null | sed 's/^/[dry-run] rm -f /' || true
else
  rm -f /usr/local/bin/olc-* 2>/dev/null || true
fi

log "remove config"
run rm -rf /etc/olcrtc-manager

log "remove zapret (/opt/zapret + ipset'ы)"
run rm -rf /opt/zapret
if [[ "$DRY_RUN" -eq 1 ]]; then
  ls -d /opt/zapret.uninstalled.* 2>/dev/null | sed 's/^/[dry-run] rm -rf /' || true
else
  rm -rf /opt/zapret.uninstalled.* 2>/dev/null || true
fi
if [[ "$DRY_RUN" -eq 0 ]] && command -v ipset >/dev/null 2>&1; then
  for s in $(ipset list -n 2>/dev/null | grep -Ei 'zapret|nozapret|ipban' || true); do
    ipset flush "$s" 2>/dev/null || true
    ipset destroy "$s" 2>/dev/null || true
  done
fi

if [[ "$KEEP_WARP" -eq 0 ]] && dpkg -s cloudflare-warp >/dev/null 2>&1; then
  log "remove cloudflare-warp (apt purge + apt source)"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    warp-cli --accept-tos disconnect 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive apt-get -y purge cloudflare-warp 2>/dev/null || true
  else
    echo "[dry-run] apt-get -y purge cloudflare-warp"
  fi
  run rm -f /etc/apt/sources.list.d/cloudflare-client.list \
            /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
elif [[ "$KEEP_WARP" -eq 1 ]]; then
  log "keeping cloudflare-warp"
fi

log "remove runtime state"
run rm -rf /var/lib/olcrtc
run find /tmp -maxdepth 1 -name 'olcrtc-manager-srv-*.yaml' -delete || true
if [[ "$DRY_RUN" -eq 1 ]]; then
  ls -d /tmp/olcrtc-* /tmp/olc-purge-* 2>/dev/null | sed 's/^/[dry-run] rm -rf /' || true
else
  rm -rf /tmp/olcrtc-* /tmp/olc-purge-* 2>/dev/null || true
fi

log "remove logs"
if [[ "$DRY_RUN" -eq 1 ]]; then
  ls /var/log/olcrtc* /var/log/olc-swap.log 2>/dev/null | sed 's/^/[dry-run] rm -f /' || true
else
  rm -f /var/log/olcrtc* /var/log/olc-swap.log 2>/dev/null || true
fi

log "remove build caches"
# Remove Go workspace and cloned repos from /root
run rm -rf /root/go /root/olcrtc
if [[ "$DRY_RUN" -eq 0 ]] && declare -f olc_cleanup_purge_caches >/dev/null 2>&1; then
  olc_cleanup_purge_caches
fi
if [[ "$PURGE_ALL" -eq 1 ]]; then
  log "remove go toolchain + deep caches (--purge-all)"
  run rm -rf /usr/local/go /root/.cache/go-build /root/.npm
fi

log "remove sysctl drop-in"
run rm -f /etc/sysctl.d/99-olcrtc-performance.conf

if [[ "$KEEP_TOR" -eq 0 ]]; then
  log "remove olcrtc tor drop-ins (tor package stays installed)"
  run rm -f /etc/tor/torrc.d/olcrtc-exit.conf
  run rm -f /etc/tor/bridges.conf
  if [[ "$DRY_RUN" -eq 1 ]]; then
    ls /etc/tor/bridges.conf.uninstalled.* 2>/dev/null | sed 's/^/[dry-run] rm -f /' || true
  else
    rm -f /etc/tor/bridges.conf.uninstalled.* 2>/dev/null || true
  fi
  # restore empty bridges only if file was ours (no user bridges)
  if [[ "$DRY_RUN" -eq 0 ]] && [[ -f /etc/tor/torrc ]]; then
    grep -q 'bridges.conf' /etc/tor/torrc 2>/dev/null && \
      sed -i '/^%include.*bridges\.conf/d' /etc/tor/torrc 2>/dev/null || true
  fi
  systemctl restart tor@default 2>/dev/null || true
else
  log "keeping tor@default and /etc/tor/bridges.conf"
fi

run rm -f /opt/olcrtc
if [[ "$PURGE_REPO" -eq 1 ]]; then
  log "remove install dir $INSTALL_DIR"
  run rm -rf "$INSTALL_DIR"
else
  log "keeping $INSTALL_DIR (use --purge-repo to delete)"
fi

# ── Проверка чистоты: что осталось от стека ──────────────────────────────────
if [[ "$DRY_RUN" -eq 0 ]]; then
  log "проверка чистоты…"
  leftovers=0
  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    echo "[purge]   ⚠ осталось: $item"
    leftovers=$((leftovers + 1))
  done < <(
    ls -d /etc/systemd/system/olcrtc-* /etc/systemd/system/zapret.service \
          /usr/local/bin/olcrtc /usr/local/bin/olcrtc-manager /usr/local/bin/olc-* \
          /usr/local/bin/webtunnel-client \
          /etc/olcrtc-manager /var/lib/olcrtc /opt/zapret \
          /etc/cron.d/olcrtc-* /etc/cron.d/zapret-sync 2>/dev/null || true
    if [[ "$KEEP_TOR" -eq 0 ]]; then
      ls -d /etc/tor/torrc.d/olcrtc-exit.conf /etc/tor/bridges.conf 2>/dev/null || true
    fi
    if [[ "$PURGE_REPO" -eq 1 ]]; then ls -d "$INSTALL_DIR" 2>/dev/null || true; fi
    systemctl list-units --all 2>/dev/null | awk '/olcrtc|zapret/ {print "unit: " $1}' || true
  )
  if [[ "$leftovers" -eq 0 ]]; then
    log "✓ чисто: следов стека не найдено"
  else
    log "⚠ найдено остатков: $leftovers (см. выше)"
  fi
fi

log "done — olcrtc stack removed"
[[ "$KEEP_TOR" -eq 0 ]] && log "note: пакеты tor/obfs4proxy остаются установлены (apt) — это безопасно"
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "dry-run only; nothing was deleted"
fi

# Убрать временную копию self после re-exec (--purge-repo)
if [[ -n "${OLC_PURGE_SELF_TMP:-}" && "$DRY_RUN" -eq 0 ]]; then
  ( sleep 1; rm -rf "$OLC_PURGE_SELF_TMP" ) &
  disown 2>/dev/null || true
fi
