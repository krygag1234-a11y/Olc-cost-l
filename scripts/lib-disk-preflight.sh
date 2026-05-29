#!/usr/bin/env bash
# Проверка свободного места на диске перед тяжёлыми шагами Olc-cost-l.
[[ -n "${_OLC_DISK_PREFLIGHT_LOADED:-}" ]] && return 0
_OLC_DISK_PREFLIGHT_LOADED=1

# Минимум свободного места (МиБ) на корне и в /tmp
OLC_DISK_MIN_MB_ROOT="${OLC_DISK_MIN_MB_ROOT:-400}"
OLC_DISK_MIN_MB_TMP="${OLC_DISK_MIN_MB_TMP:-200}"
# Остановить скрипт, если занято >= N% (по df)
OLC_DISK_FAIL_USE_PCT="${OLC_DISK_FAIL_USE_PCT:-98}"
OLC_DISK_WARN_USE_PCT="${OLC_DISK_WARN_USE_PCT:-95}"
# 1 = только предупреждение, не выходить с ошибкой
OLC_DISK_CHECK_WARN_ONLY="${OLC_DISK_CHECK_WARN_ONLY:-0}"
OLC_DISK_PROMPT_ON_WARN="${OLC_DISK_PROMPT_ON_WARN:-1}"

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

olc_disk_has_tty() {
  [ -t 0 ] || { [ -e /dev/tty ] && : </dev/tty; } 2>/dev/null
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
  echo "       удалить все бэкапы: sudo rm -f /var/backups/olc-vps/*.tar.gz" >&2
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

olc_disk_interactive_cleanup() {
  # Проверяем, есть ли терминал для ввода
  if ! olc_disk_has_tty; then
    return 1
  fi
  
  if [[ "${_OLC_DISK_PROMPTED:-0}" == "1" ]]; then
    return 1
  fi
  export _OLC_DISK_PROMPTED=1

  echo "" >&2
  echo "Хотите сделать анализ содержимого диска, чтобы прямо тут выяснить есть ли на диски только нужные или не нужные файлы? (мы не собираем никаких данных, все эти анализы хранятся на вашем устройстве)" >&2
  echo "1 - Да" >&2
  echo "2 - Нет, я сам решу эту проблему" >&2

  local answer
  read -r -p "Введите 1 или 2: " answer </dev/tty || return 1

  if [[ "${answer,,}" == "1" || "${answer,,}" == "да" || "${answer,,}" == "-да" || "${answer,,}" == "- да" || "${answer,,}" == "y" || "${answer,,}" == "yes" ]]; then
    echo "Выполняем анализ..." >&2
    
    local backups_size=0 cache_go=0 cache_npm=0 apt_cache=0 logs_gz=0
    [[ -d /var/backups/olc-vps ]] && backups_size=$(du -sm /var/backups/olc-vps 2>/dev/null | awk '{print $1}')
    [[ -d /root/.cache/go-build ]] && cache_go=$(du -sm /root/.cache/go-build 2>/dev/null | awk '{print $1}')
    [[ -d /root/.npm/_cacache ]] && cache_npm=$(du -sm /root/.npm/_cacache 2>/dev/null | awk '{print $1}')
    [[ -d /var/cache/apt/archives ]] && apt_cache=$(du -sm /var/cache/apt/archives 2>/dev/null | awk '{print $1}')
    logs_gz=$(find /var/log -type f -name '*.gz' -exec du -cm {} + 2>/dev/null | awk '/total$/ {print $1}')
    
    echo "" >&2
    echo "Найдены следующие временные/старые файлы:" >&2
    [[ -n "$backups_size" && "$backups_size" -gt 0 ]] && echo " - Бэкапы Olc-cost-l (/var/backups/olc-vps): ~${backups_size} МБ" >&2
    [[ -n "$cache_go" && "$cache_go" -gt 0 ]] && echo " - Кэш сборки Go (/root/.cache/go-build): ~${cache_go} МБ" >&2
    [[ -n "$cache_npm" && "$cache_npm" -gt 0 ]] && echo " - Кэш npm (/root/.npm/_cacache): ~${cache_npm} МБ" >&2
    [[ -n "$apt_cache" && "$apt_cache" -gt 0 ]] && echo " - Кэш пакетов apt: ~${apt_cache} МБ" >&2
    [[ -n "$logs_gz" && "$logs_gz" -gt 0 ]] && echo " - Старые сжатые логи (/var/log/*.gz): ~${logs_gz} МБ" >&2
    
    local total_junk=$(( ${backups_size:-0} + ${cache_go:-0} + ${cache_npm:-0} + ${apt_cache:-0} + ${logs_gz:-0} ))
    if [[ "$total_junk" -eq 0 ]]; then
      echo "Мусорных файлов не найдено (или они занимают < 1 МБ)." >&2
      return 1
    fi

    echo "" >&2
    echo "Хотите очистить диск прямо от сюда автоматически (ВСЕ бэкапы и кэш будут удалены):" >&2
    echo "1 - Да, очистить всё найденное" >&2
    echo "2 - Нет, я сам решу эту проблему" >&2

    local ans2
    read -r -p "Введите 1 или 2: " ans2 </dev/tty || return 1
    if [[ "${ans2,,}" == "1" || "${ans2,,}" == "да" || "${ans2,,}" == "- да" || "${ans2,,}" == "-да" || "${ans2,,}" == "y" || "${ans2,,}" == "yes" ]]; then
      echo "Очистка..." >&2
      rm -f /var/backups/olc-vps/*.tar.gz /var/backups/olc-vps/*.tsv /var/backups/olc-vps/*.txt 2>/dev/null || true
      rm -rf /root/.cache/go-build /root/.npm/_cacache 2>/dev/null || true
      apt-get clean 2>/dev/null || true
      find /var/log -type f -name '*.gz' -delete 2>/dev/null || true
      journalctl --vacuum-time=1d 2>/dev/null || true
      echo "Очистка завершена." >&2
      return 0
    fi
  fi
  return 1
}

# Главная preflight-функция для entrypoint-скриптов.
olc_preflight_disk_space() {
  [[ "${OLC_DISK_CHECK_DISABLE:-0}" == "1" ]] && return 0
  command -v df >/dev/null 2>&1 || return 0

  local reason="${1:-скрипт Olc-cost-l}"
  local res
  
  _olc_preflight_disk_space_internal "$reason"
  res=$?
  
  if [[ "$res" -ne 0 ]]; then
    # Если мало места (failed=1)
    if [[ "$res" -eq 1 ]]; then
      if olc_disk_interactive_cleanup; then
        echo "[olc-disk] Повторная проверка диска после очистки..." >&2
        _olc_preflight_disk_space_internal "$reason"
        res=$?
        # Если после очистки был failed, а стал warned (2) или ok (0), считаем успехом или пускаем дальше
        [[ "$res" -eq 2 ]] && return 0
        return "$res"
      fi
    fi
  fi
  
  if [[ "$res" -eq 2 ]]; then
    if [[ "$OLC_DISK_PROMPT_ON_WARN" == "1" ]]; then
      olc_disk_interactive_cleanup || true
    fi
    return 0
  fi
  return "$res"
}

_olc_preflight_disk_space_internal() {
  local reason="$1"
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
      return 2
    fi
    return 1
  fi

  if [[ "$warned" -eq 1 ]]; then
    echo "[olc-disk] внимание: на диске / осталось мало места ($(olc_disk_use_pct /)% занято, ~$(olc_disk_available_mb /) МБ свободно). Рекомендуется очистить до продолжения." >&2
    return 2
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
