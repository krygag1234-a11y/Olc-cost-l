#!/usr/bin/env bash
# Safe full reinstall of the vendored Olc-cost-l stack with exact profile and data restore.
set -Eeuo pipefail

INSTALL_DIR="$(readlink -m -- "${OLC_INSTALL_DIR:-/opt/Olc-cost-l}")"
SOURCE_DIR="$(readlink -m -- "${OLC_REINSTALL_SOURCE_DIR:-$INSTALL_DIR}")"
case "$INSTALL_DIR" in
  /|/bin|/boot|/dev|/etc|/home|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var)
    printf '[reinstall] ERROR: unsafe install directory: %s\n' "$INSTALL_DIR" >&2
    exit 1
    ;;
esac
case "$SOURCE_DIR" in
  /|/bin|/boot|/dev|/etc|/home|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var)
    printf '[reinstall] ERROR: unsafe source directory: %s\n' "$SOURCE_DIR" >&2
    exit 1
    ;;
esac
PROFILE="${OLCRTC_DEPLOY_PROFILE:-/etc/olcrtc-manager/deploy-profile.json}"
BACKUP_ROOT="${OLC_REINSTALL_BACKUP_ROOT:-/var/backups/olc-reinstall}"
ASSUME_YES=0
DRY_RUN=0
ROLLBACK_ARCHIVE=""
WORK_DIR=""
PHASE="preflight"

log() { printf '[reinstall] %s\n' "$*"; }
die() { printf '[reinstall] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: sudo olc-reinstall [--yes] [--dry-run]

Creates a full VPS rollback archive and a logical panel backup, remembers the
current deploy profile and an exact source snapshot, purges the Olc-cost-l stack
including /opt/Olc-cost-l, restores the same vendored source, installs the same
profile, imports the backup, and validates the result.

By default the current vendored checkout is reused. For the first migration of
a legacy installation, set OLC_REINSTALL_SOURCE_DIR to a separately validated
vendored checkout. The legacy /opt tree is still captured by the rollback
archive, while the clean source checkout becomes the post-purge installation.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

if [[ "$(id -u)" -ne 0 ]]; then
  sudo_args=()
  [[ "$ASSUME_YES" -eq 1 ]] && sudo_args+=(--yes)
  [[ "$DRY_RUN" -eq 1 ]] && sudo_args+=(--dry-run)
  exec sudo -E bash "$0" "${sudo_args[@]}"
fi
[[ -x "$SOURCE_DIR/install.sh" ]] || die "vendored installer not found: $SOURCE_DIR/install.sh"
[[ -x "$SOURCE_DIR/scripts/olc-purge.sh" ]] || die "purge script not found"
[[ -x "$SOURCE_DIR/scripts/olc-backup.sh" ]] || die "logical backup script not found"
[[ -x "$SOURCE_DIR/scripts/olc-vps-backup.sh" ]] || die "VPS backup script not found"
[[ -f "$PROFILE" ]] || die "deploy profile not found: $PROFILE"
command -v jq >/dev/null 2>&1 || die "jq is required"

profile_schema="$(jq -r '.schema // 0' "$PROFILE")"
[[ "$profile_schema" == "1" ]] || die "unsupported deploy profile schema: $profile_schema"
old_port="$(jq -r '.port // 8888' /etc/olcrtc-manager/config.json 2>/dev/null || echo 8888)"
[[ "$old_port" =~ ^[0-9]+$ ]] || die "invalid manager port in existing config: $old_port"

declare -a INSTALL_FLAGS=()
for component in tor bridges split zapret warp; do
  if [[ "$(jq -r --arg k "$component" '.components[$k] // false' "$PROFILE")" == "true" ]]; then
    INSTALL_FLAGS+=("--$component")
  fi
done
if [[ "${#INSTALL_FLAGS[@]}" -eq 0 ]]; then
  INSTALL_FLAGS=(--full --no-tor --no-zapret)
fi

panel_access="$(jq -r '.panel.access // "ssh"' "$PROFILE")"
case "$panel_access" in
  ip) INSTALL_FLAGS+=(--ip) ;;
  ssh) INSTALL_FLAGS+=(--ssh) ;;
  *) die "unsupported panel access mode: $panel_access" ;;
esac

panel_tls="$(jq -r '.panel.tls // false' "$PROFILE")"
panel_tls_mode="$(jq -r '.panel.tls_mode // "http"' "$PROFILE")"
if [[ "$panel_tls" != "true" ]]; then
  INSTALL_FLAGS+=(--http)
else
  case "$panel_tls_mode" in
    selfsigned) INSTALL_FLAGS+=(--https-self-signed) ;;
    letsencrypt) INSTALL_FLAGS+=(--https-letsencrypt) ;;
    *) die "unsupported TLS mode: $panel_tls_mode" ;;
  esac
fi

branch="$(git -C "$SOURCE_DIR" branch --show-current 2>/dev/null || true)"
[[ -n "$branch" ]] || branch="main"

log "profile: $(jq -r '.profile_id // "custom"' "$PROFILE")"
log "manager port to restore: $old_port"
log "installer flags: ${INSTALL_FLAGS[*]}"
log "source checkout: $SOURCE_DIR"
log "source branch: $branch"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "dry-run: create full VPS backup"
  log "dry-run: export logical backup"
  log "dry-run: archive the current vendored source"
  log "dry-run: olc-purge --yes --purge-repo"
  log "dry-run: restore the exact vendored source snapshot"
  log "dry-run: install.sh ${INSTALL_FLAGS[*]}"
  log "dry-run: first-run import and validation"
  exit 0
fi

if [[ "$ASSUME_YES" -eq 0 ]]; then
  if ! { [[ -e /dev/tty ]] && : </dev/tty; } 2>/dev/null; then
    die "no interactive terminal; use --yes"
  fi
  printf 'A full reversible reinstall will be performed. Type yes: ' >/dev/tty
  answer=""; read -r answer </dev/tty || true
  [[ "${answer,,}" == "yes" ]] || { log "cancelled"; exit 0; }
fi

install -d -m 0700 "$BACKUP_ROOT"
WORK_DIR="$(mktemp -d "$BACKUP_ROOT/run-XXXXXXXX")"
exec > >(tee -a "$WORK_DIR/reinstall.log") 2>&1
log "persistent log: $WORK_DIR/reinstall.log"
cp -a "$PROFILE" "$WORK_DIR/deploy-profile.before.json"
cp -a "$SOURCE_DIR/scripts/olc-purge.sh" "$WORK_DIR/olc-purge.sh"
cp -a "$SOURCE_DIR/scripts/olc-vps-backup.sh" "$WORK_DIR/olc-vps-backup.sh"
cp -a "$SOURCE_DIR/scripts/lib-vps-backup.sh" "$WORK_DIR/lib-vps-backup.sh"
zapret_was_enabled="$(systemctl is-enabled zapret.service 2>/dev/null || true)"
zapret_was_active="$(systemctl is-active zapret.service 2>/dev/null || true)"

PHASE="source-snapshot"
SOURCE_ARCHIVE="$WORK_DIR/vendored-source.tar.gz"
SOURCE_KIND="tar"
SOURCE_COMMIT="$(git -C "$SOURCE_DIR" rev-parse HEAD 2>/dev/null || true)"
# node_modules is generated by npm ci. A same-tree reinstall preserves local
# source changes. A legacy migration from a separate validated checkout copies
# only Git-tracked files plus .git, excluding rollback files and build state.
if [[ "$SOURCE_DIR" == "$INSTALL_DIR" ]]; then
  tar -C "$SOURCE_DIR" \
    --exclude='./components/olcrtc-manager/node_modules' \
    -czf "$SOURCE_ARCHIVE" .
else
  git -C "$SOURCE_DIR" diff --quiet --exit-code || die "validated source has unstaged tracked changes"
  git -C "$SOURCE_DIR" diff --cached --quiet --exit-code || die "validated source has staged changes"
  [[ -n "$SOURCE_COMMIT" ]] || die "validated source has no Git commit"
  [[ "$(git -C "$SOURCE_DIR" rev-parse --is-shallow-repository)" != "true" ]] || \
    die "validated source is shallow; run git -C '$SOURCE_DIR' fetch --unshallow first"
  SOURCE_KIND="bundle"
  SOURCE_ARCHIVE="$WORK_DIR/vendored-source.bundle"
  git -C "$SOURCE_DIR" bundle create "$SOURCE_ARCHIVE" "refs/heads/$branch"
  git -C "$SOURCE_DIR" bundle verify "$SOURCE_ARCHIVE" >/dev/null
fi
if [[ "$SOURCE_KIND" == "tar" ]]; then
  gzip -t "$SOURCE_ARCHIVE"
fi

rollback() {
  rc=$?
  trap - ERR
  log "failed during phase '$PHASE' (rc=$rc)"
  # The rollback archive restores /var/log to its pre-reinstall state. Preserve
  # the failed run's installer/build diagnostics beside reinstall.log first.
  install -d -m 0700 "$WORK_DIR/failure-logs"
  for failed_log in \
    /var/log/olcrtc-bootstrap-patches.log \
    /var/log/olcrtc-apply-patches.log \
    /var/log/olcrtc-apt-install.log \
    /var/log/olc-swap.log; do
    if [[ -f "$failed_log" ]]; then
      cp -a "$failed_log" "$WORK_DIR/failure-logs/" || true
    fi
  done
  if [[ -n "$ROLLBACK_ARCHIVE" && -f "$ROLLBACK_ARCHIVE" ]]; then
    log "rolling back from: $ROLLBACK_ARCHIVE"
    bash "$WORK_DIR/olc-purge.sh" --yes --purge-repo >/dev/null 2>&1 || true
    OLC_VPS_BACKUP_ROOT="$(dirname "$ROLLBACK_ARCHIVE")" bash "$WORK_DIR/olc-vps-backup.sh" restore "$ROLLBACK_ARCHIVE" || true
    systemctl daemon-reload || true
    systemctl enable --now olcrtc-manager.service 2>/dev/null || true
    if [[ "$zapret_was_enabled" == "enabled" || "$zapret_was_active" == "active" ]]; then
      systemctl enable --now zapret.service 2>/dev/null || true
    fi
    log "rollback attempted; inspect services before retrying"
  else
    log "rollback archive was not created; no destructive phase was entered"
  fi
  exit "$rc"
}
trap rollback ERR

PHASE="logical-export"
LOGICAL_BACKUP="$WORK_DIR/panel-backup.json"
# Export while the live manager is still known-good. A large full VPS snapshot
# can briefly saturate disk I/O; the logical backup must not depend on the
# manager responding immediately after that heavy archive operation.
bash "$SOURCE_DIR/scripts/olc-backup.sh" export "$LOGICAL_BACKUP"
jq -e '.olc_backup == true and (.schema_version | type == "number")' "$LOGICAL_BACKUP" >/dev/null

PHASE="full-backup"
before_list="$WORK_DIR/backups.before"
find /var/backups/olc-vps -maxdepth 1 -type f -name '*.tar.gz' -print 2>/dev/null | sort >"$before_list" || true
OLC_VPS_BACKUP_FORCE=1 OLC_VPS_BACKUP_ONCE_PER_DAY=0 bash "$SOURCE_DIR/scripts/olc-vps-backup.sh" create pre-reinstall
ROLLBACK_ARCHIVE="$(find /var/backups/olc-vps -maxdepth 1 -type f -name '*.tar.gz' -printf '%T@ %p\n' | sort -nr | awk 'NR==1 {sub(/^[^ ]+ /, ""); print; exit}')"
[[ -n "$ROLLBACK_ARCHIVE" && -f "$ROLLBACK_ARCHIVE" ]] || die "full rollback archive was not created"
if grep -Fqx -- "$ROLLBACK_ARCHIVE" "$before_list"; then
  die "full backup command did not create a new rollback archive"
fi
gzip -t "$ROLLBACK_ARCHIVE"
ARCHIVE_CONTENTS="$WORK_DIR/rollback-archive.contents"
tar -tzf "$ROLLBACK_ARCHIVE" >"$ARCHIVE_CONTENTS"
for required_path in \
  etc/olcrtc-manager/config.json \
  etc/olcrtc-manager/panel.env \
  opt/Olc-cost-l/install.sh \
  usr/local/bin/olcrtc-manager; do
  grep -Fqx -- "$required_path" "$ARCHIVE_CONTENTS" || \
    die "rollback archive is incomplete: missing $required_path"
done

PHASE="purge"
bash "$WORK_DIR/olc-purge.sh" --yes --purge-repo

PHASE="source-restore"
if [[ "$SOURCE_KIND" == "bundle" ]]; then
  git clone --branch "$branch" "$SOURCE_ARCHIVE" "$INSTALL_DIR"
  [[ "$(git -C "$INSTALL_DIR" rev-parse HEAD)" == "$SOURCE_COMMIT" ]] || \
    die "restored source commit does not match validated source"
else
  install -d -m 0755 "$INSTALL_DIR"
  tar -C "$INSTALL_DIR" -xzf "$SOURCE_ARCHIVE"
fi
[[ -x "$INSTALL_DIR/install.sh" ]] || die "vendored source restore is incomplete"
# The shell started inside /opt/Olc-cost-l. After purge that inode no longer
# exists even though the same path has just been recreated, so explicitly enter
# the new directory before install/git/TUI code calls getcwd().
cd "$INSTALL_DIR"

PHASE="install"
OLC_REPO_BRANCH="$branch" bash "$INSTALL_DIR/install.sh" "${INSTALL_FLAGS[@]}"
cp -a /etc/olcrtc-manager/panel.env "$WORK_DIR/panel.env.after-install"

PHASE="logical-import"
bash "$INSTALL_DIR/scripts/olc-backup.sh" import-first-run "$LOGICAL_BACKUP" --missing-components install
# Backup restores user-editable panel.env values, but the fresh installer owns
# the current transport/access contract.  Keep the newly generated TLS paths
# and access mode instead of letting a stale or incomplete backup disable them.
# shellcheck source=safety-lib.sh
source "$INSTALL_DIR/scripts/safety-lib.sh"
read_installed_env_value() {
  local key="$1"
  bash -c 'set +u; source "$1"; key="$2"; printf "%s" "${!key-}"' _ "$WORK_DIR/panel.env.after-install" "$key"
}
for deploy_key in \
  OLCRTC_MANAGER_ADDR OLCRTC_PANEL_ACCESS OLCRTC_PUBLIC_URL \
  OLCRTC_MANAGER_TLS_CERT OLCRTC_MANAGER_TLS_KEY; do
  safety_panel_env_set /etc/olcrtc-manager/panel.env "$deploy_key" "$(read_installed_env_value "$deploy_key")"
done
systemctl restart olcrtc-manager.service

PHASE="validation"
systemctl enable olcrtc-manager.service >/dev/null
systemctl is-enabled --quiet olcrtc-manager.service
systemctl is-active --quiet olcrtc-manager.service
systemctl is-active --quiet vps-api.service 2>/dev/null || true
scheme=http
[[ "$panel_tls" == "true" ]] && scheme=https
if [[ "$panel_tls" == "true" ]]; then
  set +u
  source /etc/olcrtc-manager/panel.env
  set -u
  [[ -n "${OLCRTC_MANAGER_TLS_CERT:-}" && -f "$OLCRTC_MANAGER_TLS_CERT" ]] || die "TLS certificate missing after reinstall"
  [[ -n "${OLCRTC_MANAGER_TLS_KEY:-}" && -f "$OLCRTC_MANAGER_TLS_KEY" ]] || die "TLS key missing after reinstall"
fi
panel_ready=0
for _ in $(seq 1 45); do
  if curl -kfsS --max-time 3 "$scheme://127.0.0.1:${old_port}/admin" >/dev/null 2>&1; then
    panel_ready=1
    break
  fi
  sleep 1
done
[[ "$panel_ready" -eq 1 ]] || die "manager did not become ready on $scheme port $old_port"
if [[ "$(jq -r '.components.zapret // false' "$PROFILE")" == "true" ]]; then
  set +u
  source /etc/olcrtc-manager/features.env 2>/dev/null || true
  set -u
  if [[ "${OLCRTC_ENABLE_ZAPRET:-1}" == "1" ]]; then
    systemctl is-enabled --quiet zapret.service || die "Zapret is enabled but zapret.service is not enabled"
    systemctl is-active --quiet zapret.service || die "Zapret is enabled but zapret.service is not active"
    pidof nfqws >/dev/null 2>&1 || die "Zapret is enabled but nfqws is not running"
  fi
fi
jq -e --slurpfile old "$WORK_DIR/deploy-profile.before.json" '
  .components == $old[0].components and
  .panel.access == $old[0].panel.access and
  .panel.tls == $old[0].panel.tls and
  .panel.tls_mode == $old[0].panel.tls_mode
' "$PROFILE" >/dev/null

trap - ERR
PHASE="done"
log "reinstall completed successfully"
log "logical backup: $LOGICAL_BACKUP"
log "rollback archive retained: $ROLLBACK_ARCHIVE"
