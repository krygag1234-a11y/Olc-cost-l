#!/usr/bin/env bash
# Regression: nested bash должен использовать IPC родительского progress-bar.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/olcrtc-progress-test.XXXXXX")"

# shellcheck source=lib-install-state.sh
source "$SCRIPT_DIR/lib-install-state.sh"

# state_init() устанавливает EXIT trap, который заменяет trap теста.
# Используем compound trap для сохранения обоих cleanup.
cleanup_test() {
  _olc_progress_cleanup 0 2>/dev/null || true
  rm -rf "$TEST_TMP"
}
trap cleanup_test EXIT
trap 'cleanup_test; exit 130' INT
trap 'cleanup_test; exit 143' TERM

export OLCRTC_STATE_DIR="$TEST_TMP/state"
export OLCRTC_STATE_FILE="$OLCRTC_STATE_DIR/install-state.json"
export OLC_NO_SPINNER=1
export OLC_LANG=ru

# shellcheck source=lib-install-state.sh
source "$SCRIPT_DIR/lib-install-state.sh"
state_init --fresh

parent_substep="$_OLCRTC_PROGRESS_SUBSTEP_FILE"
parent_simple="$_OLCRTC_PROGRESS_SIMPLE_FLAG"
export TEST_PROGRESS_LIB="$SCRIPT_DIR/lib-install-state.sh"
export TEST_PARENT_SUBSTEP="$parent_substep"
export TEST_PARENT_SIMPLE="$parent_simple"

nested_progress_step() {
  bash -c '
    set -euo pipefail
    source "$TEST_PROGRESS_LIB"
    [[ "$_OLCRTC_PROGRESS_SUBSTEP_FILE" == "$TEST_PARENT_SUBSTEP" ]]
    [[ "$_OLCRTC_PROGRESS_SIMPLE_FLAG" == "$TEST_PARENT_SIMPLE" ]]
    [[ "$_OLCRTC_PROGRESS_IPC_OWNER" == "0" ]]
    _olc_substep_reset 2
    _olc_substep "Первая подзадача"
    _olc_substep "Вторая подзадача"
    [[ -f "$TEST_PARENT_SUBSTEP" ]]
    [[ -f "$TEST_PARENT_SIMPLE" ]]
  '
}

output="$(state_step patches nested_progress_step)"
grep -Fq '→ Первая подзадача (1/2, 50%)' <<<"$output"
grep -Fq '→ Вторая подзадача (2/2, 100%)' <<<"$output"
grep -Fq '✓ патчи применены' <<<"$output"
[[ ! -e "$parent_substep" ]]
[[ ! -e "$parent_simple" ]]

failing_progress_step() {
  _olc_substep_reset 1
  _olc_substep "Ошибка после прогресса"
  return 23
}

set +e
failure_output="$(state_step failure failing_progress_step)"
failure_rc=$?
set -e
[[ "$failure_rc" -eq 23 ]]
grep -Fq '→ Ошибка после прогресса (1/1, 100%)' <<<"$failure_output"
grep -Fq '✗ failure (rc=23' <<<"$failure_output"
[[ ! -e "$parent_substep" ]]
[[ ! -e "$parent_simple" ]]

ipc_dir="$_OLCRTC_PROGRESS_IPC_DIR"
_olc_progress_cleanup 0
[[ ! -e "$ipc_dir" ]]
rm -rf "$TEST_TMP"
printf '[progress-test] OK: nested IPC, 0→100%%, rc, cleanup\n'
