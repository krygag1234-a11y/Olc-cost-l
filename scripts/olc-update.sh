#!/usr/bin/env bash
# Short updater command for already-installed Olc-cost-l hosts.
set -euo pipefail

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    exec sudo -E bash "$0" "$@"
  fi
}

detect_repo() {
  if [[ -d /opt/Olc-cost-l/.git ]]; then
    echo "/opt/Olc-cost-l"
    return
  fi
  if [[ -d /opt/olcrtc/.git ]]; then
    echo "/opt/olcrtc"
    return
  fi
  if [[ -L /opt/olcrtc ]] && [[ -d "$(readlink -f /opt/olcrtc)/.git" ]]; then
    readlink -f /opt/olcrtc
    return
  fi
  return 1
}

_script="${BASH_SOURCE[0]}"
while [[ -L "$_script" ]]; do
  _script="$(readlink -f "$_script")"
done
SCRIPT_DIR="$(cd "$(dirname "$_script")" && pwd)"

# shellcheck source=lib-tui.sh
if [[ -f "$SCRIPT_DIR/lib-tui.sh" ]]; then
  source "$SCRIPT_DIR/lib-tui.sh"
else
  tui_log_info() { echo "[olc-update] $*"; }
  tui_log_error() { echo "[ERROR] $*" >&2; }
  tui_log_success() { echo "[OK] $*"; }
  tui_divider() { echo "────────────────────────────────────────"; }
fi
# shellcheck source=lib-deploy-profile.sh
source "$SCRIPT_DIR/lib-deploy-profile.sh"
# shellcheck source=lib-git-safe.sh
source "$SCRIPT_DIR/lib-git-safe.sh"
# shellcheck source=lib-olc-core.sh
source "$SCRIPT_DIR/lib-olc-core.sh"
# shellcheck source=lib-disk-preflight.sh
source "$SCRIPT_DIR/lib-disk-preflight.sh"
# shellcheck source=lib-cache-cleanup.sh
source "$SCRIPT_DIR/lib-cache-cleanup.sh"
# shellcheck source=lib-vps-backup.sh
source "$SCRIPT_DIR/lib-vps-backup.sh"

olc_update_has_tty() {
  [ -t 0 ] || { [ -e /dev/tty ] && : </dev/tty; } 2>/dev/null
}

main() {
  need_root "$@"
  local update_mode=""
  local repo profile_arg=()
  local has_explicit_flags=0
  local unknown_flags=()
  local arg
  for arg in "$@"; do
    case "$arg" in
      --show-profile) profile_show; exit 0 ;;
      --profile) profile_arg=(--profile) ;;
      --force-sha-update) export OLCRTC_FORCE_SHA_UPDATE=1 ;;
      --manager-stable) export OLC_MANAGER_STABLE=1; has_explicit_flags=1 ;;
      --manager-latest) export OLC_MANAGER_LATEST=1; has_explicit_flags=1 ;;
      --incremental) update_mode="--incremental" ;;
      --update) update_mode="--update" ;;
      --resume) ;; # handled by agent-bootstrap
      --ssh|--localhost) ;; # handled by agent-bootstrap
      *) unknown_flags+=("$arg") ;;
    esac
  done

  # Валидация неизвестных флагов
  if [[ "${#unknown_flags[@]}" -gt 0 ]]; then
    echo "" >&2
    echo "⚠️  ПРЕДУПРЕЖДЕНИЕ: Неизвестные флаги: ${unknown_flags[*]}" >&2
    echo "" >&2
    echo "При обновлении доступны только:" >&2
    echo "  --manager-latest     Обновиться на последнюю upstream версию панели (экспериментальная)" >&2
    echo "  --force-sha-update   Принудительно обновить pinned SHA из upstream" >&2
    echo "  --ssh                Переключить панель в режим SSH-туннеля" >&2
    echo "  --ip                 Переключить панель в режим открытого IP" >&2
    echo "  --resume             Продолжить прерванное обновление" >&2
    echo "" >&2
    echo "ℹ️  Обновление НЕ переустанавливает компоненты — только обновляет уже установленные." >&2
    echo "   Для доустановки компонентов используйте интерактивное меню." >&2
    echo "" >&2

    if olc_update_has_tty; then
      echo "Выберите действие:" >&2
      echo "  [1] Показать интерактивное меню обновления" >&2
      echo "  [2] Продолжить с дефолтными настройками (игнорировать неправильные флаги)" >&2
      echo "  [3] Отменить обновление" >&2
      echo -n "Ваш выбор (1-3) [2]: " >&2
      read -r choice </dev/tty || choice="2"
      choice="${choice:-2}"

      case "$choice" in
        1)
          echo "" >&2
          if [[ -f "$SCRIPT_DIR/lib-olc-core.sh" ]]; then
            source "$SCRIPT_DIR/lib-olc-core.sh"
            interactive_update_menu || {
              if declare -f tui_fatal >/dev/null 2>&1; then
                tui_fatal "Ошибка при работе с интерактивным меню обновления" "Меню не смогло завершить выбор параметров" "Попробуйте с явными флагами: olc-update --manager-stable --full"
              else
                echo "ОШИБКА: интерактивное меню завершилось с ошибкой. Используйте флаги: olc-update --manager-stable --full" >&2
                exit 1
              fi
            }
          else
            echo "⚠️  lib-olc-core.sh не найден, интерактивное меню недоступно" >&2
            echo "Продолжаю с дефолтными настройками..." >&2
          fi
          ;;
        2)
          echo "✓ Продолжаю обновление с дефолтными настройками (игнорирую неправильные флаги)..." >&2
          ;;
        3)
          echo "Обновление отменено." >&2
          exit 0
          ;;
        *)
          echo "Неправильный выбор. Продолжаю с дефолтными настройками..." >&2
          ;;
      esac
    else
      echo "Нет интерактивного терминала. Продолжаю с дефолтными настройками (игнорирую неправильные флаги)." >&2
    fi

    echo "" >&2
  fi

  # If user specified component flags but no mode, default to --update (not interactive menu)
  if [[ -z "$update_mode" && "$has_explicit_flags" -eq 1 ]]; then
    update_mode="--update"
  fi
  repo="$(detect_repo)" || {
    if declare -f tui_fatal >/dev/null 2>&1; then
      tui_fatal "Репозиторий Olc-cost-l не найден" "olc-update требует установленный репозиторий в /opt/Olc-cost-l" "Сначала установите: curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash"
    else
      echo "ОШИБКА: Olc-cost-l repo not found. Install first: curl ... | sudo bash" >&2
      exit 1
    fi
  }
  cd "$repo"
  export OLC_REPO_ROOT="$repo"
  
  echo "Проверка актуальности репозитория (ветка main)..." >&2
  local_sha="$(git rev-parse HEAD 2>/dev/null || true)"
  remote_sha="$(git ls-remote origin main 2>/dev/null | awk '{print $1}' || true)"

  local repo_uptodate=0
  if [[ -n "$local_sha" && "$local_sha" == "$remote_sha" ]]; then
    repo_uptodate=1
    echo "Репозиторий уже актуален." >&2
    git log -1 --format="Текущая версия: %h - %s (%cd)" --date=format:"%Y-%m-%d %H:%M" >&2
  else
    if [[ -n "$remote_sha" ]]; then
      echo "Доступны обновления репозитория." >&2
    fi
  fi

  # TUI menu для выбора режима (ПЕРЕД git pull) — только если режим не задан флагами
  if [[ -z "$update_mode" ]] && [[ -t 0 ]] && [[ -f "$repo/scripts/lib-tui.sh" ]]; then
    source "$repo/scripts/lib-tui.sh" 2>/dev/null || true
    if declare -f tui_menu >/dev/null 2>&1; then
      echo ""
      if [[ "$repo_uptodate" -eq 1 ]]; then
        mode=$(tui_menu "Репозиторий актуален. Выберите действие:" \
          "Доустановка (быстро - skip работающих компонентов)" \
          "Обновление (полная пересборка - patches, binaries)" \
          "Отмена")
      else
        mode=$(tui_menu "Выберите режим обновления:" \
          "Доустановка (быстро - skip работающих компонентов)" \
          "Обновление (полная пересборка - patches, binaries)" \
          "Отмена")
      fi
      # tui_menu returns 0-based index
      case "$mode" in
        2) echo "Отмена." >&2; exit 0 ;;
        1) update_mode="--update" ;;
        0) update_mode="--incremental" ;;
        *) update_mode="--incremental" ;;
      esac
    fi
  fi

  # Если режим не выбран (нет TTY или нет tui_menu), default = --update
  : "${update_mode:=--update}"

  olc_preflight_disk_space "olc-update" || {
    if declare -f tui_fatal >/dev/null 2>&1; then
      tui_fatal "Недостаточно места на диске для обновления" "Требуется минимум 400 МБ свободного места" "Освободите диск: sudo olc-cleanup-caches"
    else
      echo "ОШИБКА: недостаточно места на диске. Запустите: sudo olc-cleanup-caches" >&2
      exit 1
    fi
  }
  if [[ "$(df -Pm / 2>/dev/null | awk 'NR==2 {print $5+0}')" -ge 95 ]]; then
    olc_cleanup_build_caches "olc-update-pre-git" || true
  fi
  export _OLC_DISK_PROMPTED=1 # Чтобы не спрашивать дважды в agent-bootstrap.sh
  olc_preflight_vps_backup "olc-update" || true
  export OLC_VPS_BACKUP_DISABLE=1 # Чтобы не делать бэкап дважды

  olc_git_safe_register "$repo"

  # Git pull с русским языком (только если есть обновления)
  if [[ "$repo_uptodate" -eq 0 ]]; then
    echo ""
    tui_log_info "Обновление репозитория из GitHub..."
    tui_divider
    # Reset local modifications (patches may leave dirty state)
    olc_git "$repo" reset --hard HEAD >/dev/null 2>&1 || true
    olc_git "$repo" clean -fd >/dev/null 2>&1 || true
    LANG=ru_RU.UTF-8 LC_ALL=ru_RU.UTF-8 olc_git "$repo" pull --quiet --ff-only origin main || {
      if declare -f tui_fatal >/dev/null 2>&1; then
        tui_fatal "Ошибка git pull при обновлении репозитория" "Не удалось получить изменения с GitHub origin/main" "Проверьте сеть: ping github.com && curl -I https://github.com"
      else
        echo "ОШИБКА: git pull failed. Проверьте подключение к GitHub." >&2
        exit 1
      fi
    }
    tui_log_success "Репозиторий обновлён до последней версии."
    tui_divider
    echo ""
  fi

  # Загружаем TUI библиотеку для использования в agent-bootstrap.sh
  if [[ -f "$repo/scripts/lib-tui.sh" ]]; then
    source "$repo/scripts/lib-tui.sh" 2>/dev/null || true
    export OLC_TUI_LOADED=1
  fi
  # Re-read profile id if passed as --profile <id>
  local boot_args=(--update)
  local i=1
  while [[ $i -le $# ]]; do
    eval "arg=\${$i}"
    if [[ "$arg" == "--profile" ]]; then
      next=$((i + 1))
      if [[ $next -le $# ]]; then
        eval "pid=\${$next}"
        boot_args+=(--profile "$pid")
        i=$((i + 2))
      else
        tui_fatal "Флаг --profile требует аргумент (profile ID)." \
          "Получено: --profile без значения" \
          "Используй: olc-update --show-profile (показать ID), затем olc-update --profile <ID>"
      fi
      continue
    fi
    if [[ "$arg" != "--show-profile" ]]; then
      boot_args+=("$arg")
    fi
    i=$((i + 1))
  done

  echo "" >&2
  tui_log_info "Запуск agent-bootstrap.sh с параметрами: ${boot_args[*]}"
  tui_divider

  bash scripts/agent-bootstrap.sh "${boot_args[@]}" || {
    local exit_code=$?
    echo "" >&2
    case "$exit_code" in
      130)
        tui_log_warning "⚠ Прервано пользователем (Ctrl+C)"
        ;;
      143)
        tui_log_warning "⚠ Остановлено (SIGTERM)"
        ;;
      *)
        tui_log_error "agent-bootstrap.sh завершился с ошибкой (код: $exit_code)"
        ;;
    esac
    exit $exit_code
  }
}

main "$@"
