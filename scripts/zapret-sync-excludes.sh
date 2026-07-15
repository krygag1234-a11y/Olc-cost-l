#!/usr/bin/env bash
# Sync zapret exclusions from Olc-cost-l + olcrtc runtime lists.
#
# Direct RU / carrier hosts → netrogat.txt (nfqws: no DPI desync).
# RF-blocked (ru-blocked-tor) → NOT in netrogat; stay on zapret-hosts-user only.
#
# Usage:
#   zapret-sync-excludes.sh              # merge domains + refresh ipset exclude
#   zapret-sync-excludes.sh --domains-only
#   zapret-sync-excludes.sh --reload-zapret
#
# Env:
#   ZAPRET_OPT=/opt/zapret
#   OLCRTC_ZAPRET_RESOLVE_IPS=1   resolve carrier/high-priority hosts → nozapret (default 1)
#   OLCRTC_ZAPRET_RU_CIDR=0       add ru-cidrs.txt to ip exclude (breaks zapret on blocked .ru IPs; default 0)
#   OLCRTC_ZAPRET_WHITELIST_EXTRA=/path  optional extra domain/CIDR file
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
OPT="${ZAPRET_OPT:-/opt/zapret}"
NETROGAT="${OPT}/lists/netrogat.txt"
HOSTS_EXCLUDE="${OPT}/ipset/zapret-hosts-user-exclude.txt"
STAGING="${OLCRTC_STATE:-/var/lib/olcrtc}/zapret-netrogat-staging.txt"
REPORT="${OLCRTC_STATE:-/var/lib/olcrtc}/zapret-sync-report.txt"

DOMAINS_ONLY=0
RELOAD=0
for arg in "$@"; do
  case "$arg" in
    --domains-only) DOMAINS_ONLY=1 ;;
    --reload-zapret) RELOAD=1 ;;
  esac
done

log() { echo "[zapret-sync] $*"; }

flatten_domains() {
  sed -E 's/^#.*//;s/^[[:space:]]+//;s/[[:space:]]+$//' |
    grep -E '^[a-z0-9.*:@/_-]+' | tr '[:upper:]' '[:lower:]'
}

collect_sources() {
  local f
  # Repo static
  for f in \
    "$REPO_ROOT/data/zapret-netrogat-extra.txt" \
    "$REPO_ROOT/data/zapret-carrier-hosts.txt" \
    "$REPO_ROOT/data/zapret-community-excludes/flowseal-list-exclude.txt" \
    "$REPO_ROOT/data/zapret-vk-cdn-extra.txt" \
    "$REPO_ROOT/data/ru-domains-extra.txt" \
    "$REPO_ROOT/data/ru-embed-balancers.txt" \
    "$REPO_ROOT/data/ru-video-balancers-full.txt"; do
    [[ -f "$f" ]] && grep -vE '^[[:space:]]*#' "$f" | flatten_domains || true
  done
  # Runtime split lists (main RU whitelist for direct egress)
  for f in \
    /var/lib/olcrtc/ru-direct-domains.txt \
    /var/lib/olcrtc/ru-domains-extra.txt \
    /var/lib/olcrtc/ru-player-cdn-domains.txt; do
    [[ -f "$f" ]] && grep -vE '^[[:space:]]*#' "$f" | flatten_domains || true
  done
  # Optional user whitelist
  if [[ -n "${OLCRTC_ZAPRET_WHITELIST_EXTRA:-}" && -f "${OLCRTC_ZAPRET_WHITELIST_EXTRA}" ]]; then
    grep -vE '^[[:space:]]*#' "${OLCRTC_ZAPRET_WHITELIST_EXTRA}" | flatten_domains || true
  fi
  # Manager / runtime YAML (room URLs, hosts)
  if [[ -d /var/lib/olcrtc/manager-run ]]; then
    grep -hoE 'https?://[a-zA-Z0-9._-]+' /var/lib/olcrtc/manager-run/*.yaml 2>/dev/null |
      sed -E 's#https?://##' | flatten_domains || true
  fi
  # Scan olcrtc upstream clone if present
  local src="${OLCRTC_SRC:-/tmp/olcrtc-src}"
  if [[ -d "$src/internal/auth" ]]; then
    grep -hoE 'https?://[a-zA-Z0-9._/-]+' "$src/internal/auth"/*.go "$src/internal/auth"/*/*.go 2>/dev/null |
      sed -E 's#https?://([^/]+).*#\1#' | flatten_domains || true
  fi
  # Repo scripts/patches URLs (carrier hints)
  grep -rhoE 'https?://[a-zA-Z0-9._-]+' "$REPO_ROOT/scripts" "$REPO_ROOT/patches" 2>/dev/null |
    sed -E 's#https?://##' | flatten_domains || true
}

merge_netrogat() {
  if [[ ! -f "$NETROGAT" ]]; then
    log "skip: no $NETROGAT (zapret not installed)"
    install -d "$(dirname "$REPORT")"
    echo "ZAPRET_NOT_INSTALLED" >"$REPORT"
    return 1  # Signal skip to main()
  fi

  install -d "$(dirname "$STAGING")"
  local tmp
  tmp="$(mktemp)"
  collect_sources | awk 'NF && !seen[$0]++' >"$tmp"

  python3 - "$tmp" "$STAGING" "$REPO_ROOT" <<'PY'
import sys
from datetime import datetime
from pathlib import Path

def load_rules(path):
    exact, suffix = set(), []
    p = Path(path)
    if not p.is_file():
        return exact, suffix
    for line in p.read_text(errors="replace").splitlines():
        line = line.split("#", 1)[0].strip().lower()
        if not line:
            continue
        if line.startswith("exact:"):
            exact.add(line[6:])
        elif line.startswith("suffix:"):
            s = line[7:]
            suffix.append(s if s.startswith(".") else "." + s)
        else:
            if line.startswith("."):
                suffix.append(line)
            else:
                exact.add(line)
    return exact, suffix

def blocked(host, exact, suffix):
    host = host.strip().lower()
    if not host:
        return False
    if host in exact:
        return True
    for e in exact:
        if host == e or host.endswith("." + e):
            return True
    for s in suffix:
        if not s.startswith("."):
            s = "." + s
        if host == s[1:] or host.endswith(s):
            return True
    return False

src = Path(sys.argv[1])
out = Path(sys.argv[2])
repo = Path(sys.argv[3])
be, bs = set(), []
for bf in (
    Path("/var/lib/olcrtc/ru-blocked-tor-domains.txt"),
    Path("/var/lib/olcrtc/force-tor-domains.txt"),
    repo / "data/global-force-tor-domains.txt",
):
    e, s = load_rules(bf)
    be |= e
    bs.extend(s)

kept, seen = [], set()
for line in src.read_text(errors="replace").splitlines():
    raw = line.strip()
    if not raw:
        continue
    rule = raw.lower()
    tests = []
    if rule.startswith("exact:"):
        tests = [rule[6:]]
    elif rule.startswith("suffix:"):
        suf = rule[7:]
        tests = ["x" + (suf if suf.startswith(".") else "." + suf)]
    elif rule.startswith("."):
        tests = ["x" + rule]
    else:
        tests = [rule, "x." + rule]
    if any(blocked(h, be, bs) for h in tests):
        continue
    if raw not in seen:
        kept.append(raw)
        seen.add(raw)

header = []
net_base = Path("/opt/zapret/lists/netrogat.txt")
if net_base.is_file():
    for ln in net_base.read_text(errors="replace").splitlines():
        l = ln.strip()
        if l in ("none.com", "none.dom", "bezrazbor.disabled"):
            header.append(l)

out_seen: set[str] = set()
lines = [f"# olcrtc zapret-sync — {datetime.now().isoformat(timespec='seconds')}"]
for h in header:
    if h not in out_seen:
        lines.append(h)
        out_seen.add(h)
for r in kept:
    if r not in out_seen:
        lines.append(r)
        out_seen.add(r)
out.write_text("\n".join(lines) + "\n")
print(len(kept))
PY

  install -m 0644 "$STAGING" "$NETROGAT"
  rm -f "$tmp"
  log "netrogat: $(wc -l <"$NETROGAT") lines → $NETROGAT"
}

build_hosts_exclude() {
  local tmp
  tmp="$(mktemp)"
  {
    echo "# olcrtc zapret IP exclude — $(date -Iseconds)"
    echo "# Private nets (zapret default)"
    grep -vE '^[[:space:]]*#' "$OPT/ipset/zapret-hosts-user-exclude.txt" 2>/dev/null |
      grep -E '^[0-9./:]+' || true
    [[ -f "$REPO_ROOT/data/zapret-community-excludes/flowseal-ipset-exclude.txt" ]] &&
      grep -vE '^[[:space:]]*#' "$REPO_ROOT/data/zapret-community-excludes/flowseal-ipset-exclude.txt" |
      grep -E '^[0-9./:]+' || true
    # Carrier + extra: resolve via zapret filedigger
    for f in \
      "$REPO_ROOT/data/zapret-netrogat-extra.txt" \
      "$REPO_ROOT/data/zapret-carrier-hosts.txt"; do
      [[ -f "$f" ]] && grep -vE '^[[:space:]]*#' "$f" | flatten_domains || true
    done
    if [[ "${OLCRTC_ZAPRET_RU_CIDR:-0}" == "1" && -f /var/lib/olcrtc/ru-cidrs.txt ]]; then
      grep -vE '^[[:space:]]*#' /var/lib/olcrtc/ru-cidrs.txt | grep -E '^[0-9]' || true
    fi
    if [[ -n "${OLCRTC_ZAPRET_WHITELIST_EXTRA:-}" && -f "${OLCRTC_ZAPRET_WHITELIST_EXTRA}" ]]; then
      grep -vE '^[[:space:]]*#' "${OLCRTC_ZAPRET_WHITELIST_EXTRA}" || true
    fi
  } | awk 'NF && !seen[$0]++' >"$tmp"
  install -m 0644 "$tmp" "$HOSTS_EXCLUDE"
  rm -f "$tmp"
  log "hosts-user-exclude: $(wc -l <"$HOSTS_EXCLUDE") lines"
}

inject_carrier_ips() {
  command -v ipset >/dev/null || return 0
  ipset list nozapret &>/dev/null || return 0
  local dom ip ips cidr added=0
  while IFS= read -r dom; do
    [[ -z "$dom" ]] && continue
    if [[ "$dom" =~ ^[0-9]+(\.[0-9]+){3}(/[0-9]+)?$ ]]; then
      ipset add nozapret "$dom" 2>/dev/null || true
      continue
    fi
    [[ "$dom" =~ ^suffix:|^exact: ]] && continue
    # ВАЖНО: getent возвращает rc=2 для неразрешившегося хоста — при
    # set -euo pipefail голый пайплайн `getent | awk | while` валил весь
    # скрипт с rc=2 (T-2: «zapret sync excludes — ошибка rc=2» на боевом VPS,
    # триггер — jitsi.net без A-записи). Резолв защищён.
    ips="$(getent ahostsv4 "$dom" 2>/dev/null | awk '{print $1}' | sort -u)" || ips=""
    while IFS= read -r ip; do
      [[ -n "$ip" ]] || continue
      ipset add nozapret "$ip" 2>/dev/null || true
    done <<<"$ips"
    # Jitsi/crypto VPS often one /24 — bypass iptables NFQUEUE when hostlist misses early packets
    if [[ "$dom" == *cryptopro* || "$dom" == *jitsi* ]]; then
      while read -r cidr; do
        [[ -n "$cidr" ]] && ipset add nozapret "$cidr" 2>/dev/null || true
      done < <(getent ahostsv4 "$dom" 2>/dev/null | awk '{print $1}' | head -1 | awk -F. '{print $1"."$2"."$3".0/24"}')
    fi
  done < <(
    {
      grep -vE '^[[:space:]]*#' "$REPO_ROOT/data/zapret-carrier-hosts.txt" 2>/dev/null
      grep -vE '^[[:space:]]*#' "$REPO_ROOT/data/zapret-netrogat-extra.txt" 2>/dev/null
      grep -hoE 'meet\.[a-z0-9.-]+|stream\.wb\.ru|telemost\.yandex\.ru|cloud-api\.yandex\.ru' \
        /var/lib/olcrtc/manager-run/*.yaml 2>/dev/null || true
    } | flatten_domains | awk 'NF && !/^suffix:/ && !/^exact:/'
  )
  log "nozapret carrier IPs injected (ipset entries: $(ipset list nozapret 2>/dev/null | grep -cE '^[0-9]' || echo 0))"
}

refresh_ipset() {
  if [[ ! -x "$OPT/ipset/get_exclude.sh" ]]; then
    log "skip ipset: no get_exclude.sh"
    inject_carrier_ips
    return 0
  fi
  log "rebuilding nozapret ipset (DNS resolve, may take 1-3 min)…"
  if bash "$OPT/ipset/get_exclude.sh" 2>/dev/null; then
    inject_carrier_ips
  else
    log "WARN: get_exclude.sh failed — manual carrier resolve"
    inject_carrier_ips
  fi
}

reload_zapret() {
  if pidof nfqws >/dev/null 2>&1; then
    timeout 90 "$OPT/init.d/sysv/zapret" restart 2>/dev/null ||
      systemctl restart zapret.service 2>/dev/null || true
    log "zapret restarted"
  fi
}

write_report() {
  install -d "$(dirname "$REPORT")"
  {
    echo "zapret-sync $(date -Iseconds)"
    if [[ -f "$NETROGAT" ]]; then
      echo "netrogat_lines=$(wc -l <"$NETROGAT" 2>/dev/null || echo 0)"
    else
      echo "netrogat_lines=0"
    fi
    if [[ -f "$HOSTS_EXCLUDE" ]]; then
      echo "hosts_exclude_lines=$(wc -l <"$HOSTS_EXCLUDE" 2>/dev/null || echo 0)"
    else
      echo "hosts_exclude_lines=0"
    fi
    echo "nozapret_entries=$(ipset list nozapret 2>/dev/null | grep -cE '^[0-9]' || echo 0)"
    echo "ru_direct=$(grep -cvE '^#|^$' /var/lib/olcrtc/ru-direct-domains.txt 2>/dev/null || echo 0)"
    echo "ru_blocked=$(grep -cvE '^#|^$' /var/lib/olcrtc/ru-blocked-tor-domains.txt 2>/dev/null || echo 0)"
  } >"$REPORT"
  log "report → $REPORT"
}

main() {
  if ! merge_netrogat; then
    log "merge_netrogat skipped or failed"
    write_report
    return 0
  fi
  if [[ "$DOMAINS_ONLY" -eq 0 ]]; then
    build_hosts_exclude
    if [[ "${OLCRTC_ZAPRET_RESOLVE_IPS:-1}" == "1" ]]; then
      refresh_ipset
    fi
  fi
  write_report
  [[ "$RELOAD" -eq 1 ]] && reload_zapret
}

main "$@"
