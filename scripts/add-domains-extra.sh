#!/usr/bin/env bash
# Append domain rules and merge + restart manager
# Usage:
#   add-domains-extra.sh suffix:.giraff.io exact:a.giraff.io
#   cat hosts-rules.txt | sudo bash add-domains-extra.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=safety-lib.sh
source "$SCRIPT_DIR/safety-lib.sh"

OUT="${RU_DOMAINS_EXTRA:-/var/lib/olcrtc/ru-domains-extra.txt}"
safety_check_output_path OUT "$OUT"

{
  echo "# added $(date -Iseconds)"
  if [[ $# -gt 0 ]]; then
    printf '%s\n' "$@"
  else
    cat
  fi
} >>"$OUT"

bash "$SCRIPT_DIR/fetch-ru-direct-domains.sh"
systemctl restart olcrtc-manager
echo "[add-domains-extra] appended → $OUT, manager restarted"
