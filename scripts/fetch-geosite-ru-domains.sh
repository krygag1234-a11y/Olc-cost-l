#!/usr/bin/env bash
# Download GrimbirdUsers/ru-routing-dat geosite categories → ru-geosite-domains.txt
# Complements built-in *.ru in olcrtc (any doktor-ktto-lordfilm.ru matches automatically).
set -euo pipefail

REPO="${GEOSITE_REPO:-GrimbirdUsers/ru-routing-dat}"
BRANCH="${GEOSITE_BRANCH:-main}"
BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}/data-geosite"
OUT="${GEOSITE_DOMAINS:-/var/lib/olcrtc/ru-geosite-domains.txt}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log() { echo "[geosite-ru] $*"; }

# Categories from https://github.com/GrimbirdUsers/ru-routing-dat
CATEGORIES=(
  category-ru category-ru-all category-gov-ru category-ru-whitelist
  yandex vk mailru-group okko rutube dzen avito wildberries ozon
  wink ok x5 2gis ru-tv ru-medical
  apple apple-update google-play icloud
)

log "fetch geosite categories from ${REPO}…"
for cat in "${CATEGORIES[@]}"; do
  curl -fsSL --max-time 60 "${BASE}/${cat}" -o "${TMP}/${cat}" 2>/dev/null || true
done

# Also pull every file in data-geosite (best effort)
if command -v jq >/dev/null 2>&1; then
  mapfile -t extra < <(curl -fsSL "https://api.github.com/repos/${REPO}/contents/data-geosite?ref=${BRANCH}" 2>/dev/null \
    | jq -r '.[].name' 2>/dev/null || true)
  for cat in "${extra[@]}"; do
    [[ -f "${TMP}/${cat}" ]] && continue
    curl -fsSL --max-time 30 "${BASE}/${cat}" -o "${TMP}/${cat}" 2>/dev/null || true
  done
fi

parse_geosite() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | tr -d '[:space:]')"
    [[ -z "$line" ]] && continue
    case "$line" in
      include:*) continue ;;
      domain:*)
        d="${line#domain:}"
        d="$(echo "$d" | tr '[:upper:]' '[:lower:]')"
        [[ -z "$d" ]] && continue
        # geosite: single label ru/su = national TLD (builtin in olcrtc too)
        if [[ "$d" != *.* ]]; then
          echo "suffix:.${d}"
        else
          echo "suffix:.${d}"
          echo "exact:${d}"
        fi
        ;;
    esac
  done <"$f"
}

{
  echo "# Auto-generated from ${REPO} — $(date -Iseconds)"
  echo "# Built-in: ANY *.ru / .su / .рф already direct in olcrtc (no entry needed)"
  for f in "${TMP}"/*; do
    parse_geosite "$f"
  done
  # Common RU video balancers (non-.ru CDNs, need RU VPS IP for player geo-check)
  cat <<'BAL'

# RU embed balancers (non-RU TLD, direct via RU VPS exit)
suffix:.alloha.tv
suffix:.voidboost.cc
suffix:.voidboost.top
suffix:.voidboost.fun
suffix:.kodik.info
suffix:.kodik.biz
suffix:.kodikapi.com
suffix:.collaps.host
suffix:.lumex.space
suffix:.cdnmovies.net
suffix:.bazon.cc
suffix:.hdrezka.ag
suffix:.hdrezka.me
suffix:.rezka.ag
suffix:.monframe.org
suffix:.ashdi.vip
suffix:.veoveo.ru
suffix:.videocdn.tv
BAL
} | awk '!seen[$0]++' >"$OUT"

n="$(grep -cvE '^#|^$' "$OUT" || echo 0)"
log "wrote ${n} rules → ${OUT}"
