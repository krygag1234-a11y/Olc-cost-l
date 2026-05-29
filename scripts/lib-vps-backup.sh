#!/usr/bin/env bash
# Unified local VPS backup helpers for Olc-cost-l entry scripts.
[[ -n "${_OLC_VPS_BACKUP_LOADED:-}" ]] && return 0
_OLC_VPS_BACKUP_LOADED=1

OLC_VPS_BACKUP_ROOT="${OLC_VPS_BACKUP_ROOT:-/var/backups/olc-vps}"
OLC_VPS_BACKUP_TTL_DAYS="${OLC_VPS_BACKUP_TTL_DAYS:-14}"
OLC_VPS_BACKUP_ONCE_PER_DAY="${OLC_VPS_BACKUP_ONCE_PER_DAY:-1}"
OLC_VPS_BACKUP_MIN_FREE_MB="${OLC_VPS_BACKUP_MIN_FREE_MB:-1200}"

_olc_backup_now() { date -u +%Y%m%dT%H%M%SZ; }
_olc_backup_day() { date -u +%Y%m%d; }

olc_backup_list() {
  install -d "$OLC_VPS_BACKUP_ROOT"
  ls -1 "$OLC_VPS_BACKUP_ROOT"/*.tar.gz 2>/dev/null || true
}

olc_backup_delete() {
  local name="${1:-}"
  [[ -n "$name" ]] || { echo "usage: olc_backup_delete <archive.tar.gz>" >&2; return 1; }
  rm -f "$OLC_VPS_BACKUP_ROOT/$name"
}

olc_backup_restore() {
  local archive="${1:-}"
  [[ -n "$archive" ]] || { echo "usage: olc_backup_restore <archive.tar.gz>" >&2; return 1; }
  [[ -f "$archive" ]] || archive="$OLC_VPS_BACKUP_ROOT/$archive"
  [[ -f "$archive" ]] || { echo "backup not found: $archive" >&2; return 1; }
  [[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; return 1; }
  tar -xpf "$archive" -C /
}

olc_preflight_vps_backup() {
  [[ "${OLC_VPS_BACKUP_DISABLE:-0}" == "1" ]] && return 0
  [[ "$(id -u)" -eq 0 ]] || return 0
  mkdir -p "$OLC_VPS_BACKUP_ROOT"

  local lock="$OLC_VPS_BACKUP_ROOT/.backup.lock"
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$lock"
    flock -n 9 || return 0
  fi

  local reason="${1:-run}"
  if [[ "$reason" == "olc-update" && "${OLC_VPS_BACKUP_FORCE:-0}" != "1" && "${OLC_VPS_BACKUP_UPDATE_FULL:-0}" != "1" ]]; then
    echo "[olc-vps-backup] skip full VPS backup for olc-update (use OLC_VPS_BACKUP_UPDATE_FULL=1 to force)" >&2
    return 0
  fi

  # Prune old/generated archives before deciding whether a new full backup is safe.
  find "$OLC_VPS_BACKUP_ROOT" -type f -name '*.tar.gz' -mtime +"$OLC_VPS_BACKUP_TTL_DAYS" -delete 2>/dev/null || true
  find "$OLC_VPS_BACKUP_ROOT" -type f -name '*.meta.txt' -mtime +"$OLC_VPS_BACKUP_TTL_DAYS" -delete 2>/dev/null || true
  find "$OLC_VPS_BACKUP_ROOT" -type f -name '*.tsv' -mtime +"$OLC_VPS_BACKUP_TTL_DAYS" -delete 2>/dev/null || true
  find "$OLC_VPS_BACKUP_ROOT" -type f -name '*.txt' -mtime +"$OLC_VPS_BACKUP_TTL_DAYS" -delete 2>/dev/null || true

  local avail
  avail="$(df -Pm / 2>/dev/null | awk 'NR==2 {print $4+0}')"
  if [[ -n "$avail" && "$avail" -lt "$OLC_VPS_BACKUP_MIN_FREE_MB" && "${OLC_VPS_BACKUP_FORCE:-0}" != "1" ]]; then
    echo "[olc-vps-backup] skip: мало места для full backup (~${avail} МБ свободно, нужно >= ${OLC_VPS_BACKUP_MIN_FREE_MB} МБ)" >&2
    return 0
  fi

  local day="$(_olc_backup_day)"
  local day_marker="$OLC_VPS_BACKUP_ROOT/.daily-${day}"
  if [[ "${OLC_VPS_BACKUP_FORCE:-0}" != "1" ]] && [[ "$OLC_VPS_BACKUP_ONCE_PER_DAY" == "1" && -f "$day_marker" ]]; then
    return 0
  fi

  local ts host archive meta
  ts="$(_olc_backup_now)"
  host="$(hostname -s 2>/dev/null || hostname || echo vps)"
  archive="$OLC_VPS_BACKUP_ROOT/vps-${host}-${reason}-${ts}.tar.gz"
  meta="$OLC_VPS_BACKUP_ROOT/vps-${host}-${reason}-${ts}.meta.txt"

  {
    echo "ts=$ts"
    echo "host=$host"
    echo "reason=$reason"
    uname -a 2>/dev/null || true
    echo "---"
  } >"$meta"

  dpkg-query -W -f='${Package}\t${Version}\n' >"$OLC_VPS_BACKUP_ROOT/packages-${ts}.tsv" 2>/dev/null || true
  systemctl list-unit-files >"$OLC_VPS_BACKUP_ROOT/systemd-units-${ts}.txt" 2>/dev/null || true

  # Broad local state snapshot for full rollback.
  tar -czpf "$archive" \
    --warning=no-file-changed \
    --exclude="$OLC_VPS_BACKUP_ROOT" \
    --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run --exclude=/tmp \
    --exclude=/mnt --exclude=/media --exclude=/lost+found \
    /etc /opt /usr/local /var/lib /var/log /root /home 2>/dev/null || true

  touch "$day_marker"
  echo "[olc-vps-backup] saved $archive ($(du -h "$archive" 2>/dev/null | awk '{print $1}')) reason=$reason" >&2

  # prune old backups after success too
  find "$OLC_VPS_BACKUP_ROOT" -type f -name '*.tar.gz' -mtime +"$OLC_VPS_BACKUP_TTL_DAYS" -delete 2>/dev/null || true
  find "$OLC_VPS_BACKUP_ROOT" -type f -name '*.meta.txt' -mtime +"$OLC_VPS_BACKUP_TTL_DAYS" -delete 2>/dev/null || true
  find "$OLC_VPS_BACKUP_ROOT" -type f -name '*.tsv' -mtime +"$OLC_VPS_BACKUP_TTL_DAYS" -delete 2>/dev/null || true
  find "$OLC_VPS_BACKUP_ROOT" -type f -name '*.txt' -mtime +"$OLC_VPS_BACKUP_TTL_DAYS" -delete 2>/dev/null || true
}
