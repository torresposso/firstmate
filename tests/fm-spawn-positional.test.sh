#!/usr/bin/env bash
# Behavior tests for fm-spawn.sh single-task positional validation.
#
# A caller who leaves out a required positional must get one error naming the
# argument they forgot, not an abort from `set -u` naming a shell array element
# ("POS[1]: unbound variable"), and nothing may be created on the way out.
# These drive the real script against a throwaway home so no fleet state is
# touched; every case stops at argument parsing or a later pre-launch refusal,
# never at a window, worktree, or backend endpoint.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SPAWN="$ROOT/bin/fm-spawn.sh"
TMP_ROOT=$(fm_test_tmproot fm-spawn-positional)
# Keep the backend static so a herdr- or tmux-shaped ambient runtime cannot add
# its own auto-detect notice to the output these cases assert on.
export FM_BACKEND=tmux

# A fresh throwaway home per case, so "nothing was created" is answerable.
#
# The home also pins a harness. With no config/ the harness comes from local
# detection, which names a real harness only on a machine that has one installed
# or running in this process tree; on a clean runner it is `unknown` and every
# case whose refusal sits after harness resolution fails on "no launch template
# for harness 'unknown'" instead of on the behavior under test. The secondmate
# case resolves through config/secondmate-harness and falls back to this crew
# pin, which is the fallback the script documents. claude is pinned because its
# launch template is built in, so no case depends on which agent CLI is
# installed. Cases that refuse before harness resolution are unaffected.
make_home() {
  local home=$1
  mkdir -p "$home/data" "$home/projects" "$home/config"
  printf 'claude\n' > "$home/config/crew-harness"
}

run_spawn() {
  local home=$1
  shift
  FM_ROOT_OVERRIDE='' \
    FM_STATE_OVERRIDE='' \
    FM_DATA_OVERRIDE='' \
    FM_CONFIG_OVERRIDE='' \
    FM_PROJECTS_OVERRIDE='' \
    FM_HOME="$home" \
    FM_SPAWN_NO_GUARD=1 \
    "$SPAWN" "$@" 2>&1
}

# A missing positional is refused by name, with the neighbouring refusal's exit
# status, and the abort never comes from an unset array element.
assert_missing_positional() {
  local label=$1 expect=$2 expect_id=$3 home=$4
  shift 4
  local out status
  home="$TMP_ROOT/$home"
  make_home "$home"
  out=$(run_spawn "$home" "$@")
  status=$?
  expect_code 2 "$status" "$label: expected the usage-refusal exit status"$'\n'"$out"
  printf '%s\n' "$out" | grep -F "$expect" >/dev/null \
    || fail "$label: missing '$expect'"$'\n'"$out"
  printf '%s\n' "$out" | grep -F 'unbound variable' >/dev/null \
    && fail "$label: still aborted from an unset positional"$'\n'"$out"
  assert_absent "$home/state/$expect_id.meta" "$label created a task record"
  assert_absent "$home/data/$expect_id" "$label created a task data directory"
  pass "$label"
}

test_ship_missing_project_is_named() {
  assert_missing_positional \
    "ship spawn without <project-dir> names the missing positional" \
    'error: missing <project-dir> positional' "nope-pos-ship-z1" "home-ship" \
    nope-pos-ship-z1 --mode direct-PR --yolo on
}

test_no_positional_names_the_missing_task_id() {
  assert_missing_positional \
    "ship spawn with no positional names the missing <task-id>" \
    'error: missing <task-id> positional' "nope-pos-id-z2" "home-id" \
    --mode direct-PR --yolo on
}

test_scout_missing_project_names_its_own_shape() {
  assert_missing_positional \
    "scout spawn without <project-dir> names the missing positional" \
    'error: missing <project-dir> positional for a scout spawn' "nope-pos-scout-z3" "home-scout" \
    nope-pos-scout-z3 --scout
}

# --secondmate's home positional is OPTIONAL and --relaunch's project comes from
# the task's own record, so neither shape may be refused as a missing
# <project-dir>. Both must reach their own later refusal.
test_secondmate_and_relaunch_are_not_refused_a_project() {
  local label home out status
  while IFS='|' read -r label home expect args; do
    [ -n "$label" ] || continue
    home="$TMP_ROOT/$home"
    make_home "$home"
    # shellcheck disable=SC2086  # args is an intentional word-split arg list
    out=$(run_spawn "$home" $args)
    status=$?
    [ "$status" -ne 0 ] || fail "$label: expected a non-zero exit"$'\n'"$out"
    printf '%s\n' "$out" | grep -F 'missing <' >/dev/null \
      && fail "$label: wrongly demanded a positional"$'\n'"$out"
    printf '%s\n' "$out" | grep -F "$expect" >/dev/null \
      || fail "$label: missing '$expect'"$'\n'"$out"
  done <<'ROWS'
--secondmate takes the task id alone|home-sm|no firstmate home supplied or registered for nope-pos-sm-z4|nope-pos-sm-z4 --secondmate
--relaunch takes the task id alone|home-relaunch|error: --relaunch needs an existing task record|nope-pos-relaunch-z5 --relaunch
ROWS
  pass "--secondmate and --relaunch still parse with one positional"
}

# A well-formed two-positional call must be untouched by the new guard: it
# reaches the same pre-launch refusal it always did.
test_wellformed_call_reaches_its_normal_refusal() {
  local home out status
  home="$TMP_ROOT/home-ok"
  make_home "$home"
  mkdir -p "$home/projects/alpha"
  git -C "$home/projects/alpha" init -q || fail "could not initialize project fixture"
  out=$(run_spawn "$home" nope-pos-ok-z6 projects/alpha --mode no-mistakes --yolo off)
  status=$?
  [ "$status" -ne 0 ] || fail "spawn with a missing brief should fail"$'\n'"$out"
  printf '%s\n' "$out" | grep -F \
    "error: task nope-pos-ok-z6 has no brief at inaccessible data path $home/data/nope-pos-ok-z6/brief.md" >/dev/null \
    || fail "a well-formed spawn no longer reached its brief check"$'\n'"$out"
  pass "a well-formed single-task spawn still parses and reaches its normal refusal"
}

test_ship_missing_project_is_named
test_no_positional_names_the_missing_task_id
test_scout_missing_project_names_its_own_shape
test_secondmate_and_relaunch_are_not_refused_a_project
test_wellformed_call_reaches_its_normal_refusal
