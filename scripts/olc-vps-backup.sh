#!/usr/bin/env bash
# Manage local VPS state backups created by olc_preflight_vps_backup().
#
# Usage:
#   olc-vps-backup list
#   olc-vps-backup create [reason]     # force new archive (ignores once/day)
#   olc-vps-backup restore <archive>
#   olc-vps-backup delete <archive>
#   olc-vps-backup prune [days]        # default TTL from lib
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-vps-backup.sh
source "$SCRIPT_DIR/lib-vps-backup.sh"

need_root() {
  [[ "$(id -u)" -eq 0 ]] || exec sudo -E bash "$0" "$@"
}

usage() {
  sed -n '3,10p' "$0"
}

cmd="${1:-list}"
shift || true

case "$cmd" in
  list|-l)
    olc_backup_list
    ;;
  create|-c)
    need_root "$@"
    export OLC_VPS_BACKUP_FORCE=1
    export OLC_VPS_BACKUP_ONCE_PER_DAY=0
    olc_preflight_vps_backup "${1:-manual}"
    echo "Backup dir: $OLC_VPS_BACKUP_ROOT"
    olc_backup_list | tail -3
    ;;
  restore|-r)
    need_root "$@"
    archive="${1:-}"
    [[ -n "$archive" ]] || { usage; exit 1; }
    echo "Restoring from $archive ..."
    olc_backup_restore "$archive"
    echo "Restore complete."
    ;;
  delete|-d)
    need_root "$@"
    name="${1:-}"
    [[ -n "$name" ]] || { usage; exit 1; }
    olc_backup_delete "$name"
    echo "Deleted $name"
    ;;
  prune)
    need_root "$@"
    days="${1:-$OLC_VPS_BACKUP_TTL_DAYS}"
    find "$OLC_VPS_BACKUP_ROOT" -type f \( -name '*.tar.gz' -o -name '*.meta.txt' -o -name '*.tsv' \) -mtime +"$days" -delete 2>/dev/null || true
    echo "Pruned backups older than ${days}d in $OLC_VPS_BACKUP_ROOT"
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage
    exit 1
    ;;
esac
