#!/usr/bin/env bash
# Проверка свободного места на диске перед тяжёлыми шагами Olc-cost-l.
[[ -n "${_OLC_DISK_PREFLIGHT_LOADED:-}" ]] && return 0
_OLC_DISK_PREFLIGHT_LOADED=1

# Минимум свободного места (МиБ) на корне и в /tmp
OLC_DISK_MIN_MB_ROOT="${OLC_DISK_MIN_MB_ROOT:-400}"
OLC_DISK_MIN_MB_TMP="${OLC_DISK_MIN_MB_TMP:-200}"
# Остановить скрипт, если занято >= N% (по df)
OLC_DISK_FAIL_USE_PCT="${OLC_DISK_FAIL_USE_PCT:-98}"
OLC_DISK_WARN_USE_PCT="${OLC_DISK_WARN_USE_PCT:-90}"
# 1 = только предупреждение, не выходить с ошибкой
OLC_DISK_CHECK_WARN_ONLY="${OLC_DISK_CHECK_WARN_ONLY:-0}"

olc_disk_available_mb() {
  local path="$1"
  df -Pm "$path" 2>/dev/null | awk 'NR==2 {print $4+0}'
}

olc_disk_use_pct() {
  local path="$1"
  df -P "$path" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5+0}'
}

olc_disk_size_human() {
  local path="$1"
  df -Ph "$path" 2>/dev/null | awk 'NR==2 {print $2" всего, "$4" свободно"}'
}

olc_disk_inode_use_pct() {
  local path="$1"
  df -Pi "$path" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5+0}'
}

# Печать отчёта на русском (в stderr).
olc_disk_print_report_ru() {
  local reason="${1:-запуск скрипта}"
  echo "" >&2
  echo "══════════════════════════════════════════════════════════" >&2
  echo "  Olc-cost-l: на VPS мало места на диске" >&2
  echo "══════════════════════════════════════════════════════════" >&2
  echo "  Этап: $reason" >&2
  echo "" >&2
  for mp in / /tmp; do
    [[ -d "$mp" ]] || continue
    local avail use ih
    avail="$(olc_disk_available_mb "$mp")"
    use="$(olc_disk_use_pct "$mp")"
    ih="$(olc_disk_size_human "$mp")"
  echo "  Раздел: $mp" >&2
  echo "    Занято: ${use}%  ($ih, свободно ~${avail} МБ)" >&2
    local iu
    iu="$(olc_disk_inode_use_pct "$mp")"
    [[ -n "$iu" && "$iu" -gt 0 ]] && echo "    Inodes: занято ${iu}%" >&2
  done
  echo "" >&2
  echo "  Что это значит:" >&2
  echo "    Скрипт не может записать файлы (git clone, сборка, /tmp/olcrtc-src)." >&2
  echo "    В английских логах это часто: «No space left on device» или «write error»." >&2
  echo "" >&2
  echo "  Что сделать:" >&2
  echo "    1. Посмотреть диск:     df -h / /tmp" >&2
  echo "    2. Кто съел место:      sudo du -xh / --max-depth=1 2>/dev/null | sort -hr | head -15" >&2
  echo "    3. Бэкапы Olc:         sudo ls -lh /var/backups/olc-vps/ 2>/dev/null" >&2
  echo "       удалить старые:    sudo find /var/backups/olc-vps -name '*.tar.gz' -mtime +3 -delete" >&2
  echo "    4. Кэши сборки:        sudo rm -rf /root/.cache/go-build /root/.npm/_cacache" >&2
  echo "    5. Очистка apt:        sudo apt-get clean" >&2
  echo "    6. Проверка снова:     olc-disk-check   (или повторите install/update)" >&2
  echo "" >&2
  echo "  Освободите минимум ~${OLC_DISK_MIN_MB_ROOT} МБ на / и ~${OLC_DISK_MIN_MB_TMP} МБ в /tmp." >&2
  echo "══════════════════════════════════════════════════════════" >&2
  echo "" >&2
}

# Возвращает 0 если места достаточно, 1 если критично мало.
olc_disk_check_critical() {
  local path="$1" min_mb="$2"
  local avail use
  avail="$(olc_disk_available_mb "$path")"
  use="$(olc_disk_use_pct "$path")"
  [[ -z "$avail" ]] && return 0
  if [[ "$use" -ge "$OLC_DISK_FAIL_USE_PCT" ]] || [[ "$avail" -lt "$min_mb" ]]; then
    return 1
  fi
  local iu
  iu="$(olc_disk_inode_use_pct "$path")"
  [[ -n "$iu" && "$iu" -ge 99 ]] && return 1
  return 0
}

# Главная preflight-функция для entrypoint-скриптов.
olc_preflight_disk_space() {
  [[ "${OLC_DISK_CHECK_DISABLE:-0}" == "1" ]] && return 0
  command -v df >/dev/null 2>&1 || return 0

  local reason="${1:-скрипт Olc-cost-l}"
  local failed=0
  local warned=0

  if ! olc_disk_check_critical / "$OLC_DISK_MIN_MB_ROOT"; then
    failed=1
  else
    local use
    use="$(olc_disk_use_pct /)"
    [[ "$use" -ge "$OLC_DISK_WARN_USE_PCT" ]] && warned=1
  fi

  if [[ -d /tmp ]] && ! olc_disk_check_critical /tmp "$OLC_DISK_MIN_MB_TMP"; then
    failed=1
  fi

  if [[ "$failed" -eq 1 ]]; then
    olc_disk_print_report_ru "$reason"
    if [[ "$OLC_DISK_CHECK_WARN_ONLY" == "1" ]]; then
      echo "[olc-disk] предупреждение (OLC_DISK_CHECK_WARN_ONLY=1), продолжаем…" >&2
      return 0
    fi
    return 1
  fi

  if [[ "$warned" -eq 1 ]]; then
    echo "[olc-disk] внимание: на диске / осталось мало места ($(olc_disk_use_pct /)% занято, ~$(olc_disk_available_mb /) МБ свободно). Рекомендуется очистить до продолжения." >&2
  fi
  return 0
}

# Удобная обёртка: при ENOSPC в stderr подсказать по-русски (для логов).
olc_disk_hint_if_enospc() {
  local log="${1:-}"
  [[ -f "$log" ]] || return 0
  if grep -qiE 'no space left on device|write error.*device|disk full' "$log" 2>/dev/null; then
    olc_disk_print_report_ru "ошибка записи (вероятно, диск переполнен)"
    return 0
  fi
  return 0
}
