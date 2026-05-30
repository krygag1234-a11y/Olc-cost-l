#!/usr/bin/env bash
# Clean temporary Olc-cost-l build caches without uninstalling services.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib-output.sh
source "$SCRIPT_DIR/lib-output.sh"
# shellcheck source=lib-cache-cleanup.sh
source "$SCRIPT_DIR/lib-cache-cleanup.sh"

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

olc_print_header "Очистка кэшей сборки Olc-cost-l"

olc_print_section "Анализ занятого места"
df -h / /tmp | tail -2 | while read -r line; do
  olc_print_info "$line"
done

echo
olc_cleanup_build_caches "manual"

olc_print_section "После очистки"
df -h / /tmp | tail -2 | while read -r line; do
  olc_print_info "$line"
done

olc_print_ok "Очистка завершена"
