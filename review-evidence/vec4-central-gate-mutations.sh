#!/usr/bin/env bash
set -euo pipefail

readonly SOURCE_REL="Sources/RemoteMic/XiaomiRemoteMicBridge.swift"
readonly TEST_CLASS="RemoteMicCallbackRoutingTests"

reject() {
    printf 'REJECT: %s\n' "$*" >&2
    return 1
}

classify_expected_failure() {
    local label="$1"
    local test_name="$2"
    local assertion_marker="$3"
    local exit_code="$4"
    local output_file="$5"

    if [[ "$exit_code" -eq 0 ]]; then
        reject "$label mutation exited 0"
        return
    fi
    if [[ "$exit_code" -eq 124 || "$exit_code" -ge 128 ]]; then
        reject "$label mutation ended by timeout or signal (exit=$exit_code)"
        return
    fi
    if grep -Eiq \
        'emit-module command failed|compile command failed|linker command failed|failed to build|fatal error:|terminated due to signal|segmentation fault|bus error|illegal instruction|timed out|timeout after' \
        "$output_file"; then
        reject "$label mutation hit a build, signal, fatal, or timeout failure"
        return
    fi
    if ! grep -Fq "$test_name" "$output_file"; then
        reject "$label output does not name the target test $test_name"
        return
    fi
    if ! grep -Eq "Test Case .*${test_name}.*failed" "$output_file"; then
        reject "$label output lacks the target XCTest failure record"
        return
    fi
    if ! grep -Fq "$assertion_marker" "$output_file"; then
        reject "$label output lacks the target assertion marker"
        return
    fi

    printf 'CLASSIFIER: PASS — %s mutation produced the target XCTest assertion (exit=%s)\n' \
        "$label" "$exit_code"
}

classifier_self_test() {
    local self_test_dir
    local target_test="testCentralManagerIdentityGateRejectsWrongManager"
    local marker="manager identity gate must reject a same-attempt callback from another manager"
    self_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/vec4-classifier-self-test.XXXXXX")"
    trap "rm -rf -- '$self_test_dir'" EXIT

    printf '%s\n' \
        "Test Case '-[OpenTypeTests.RemoteMicCallbackRoutingTests ${target_test}]' failed" \
        "XCTAssertTrue failed - ${marker}" \
        >"$self_test_dir/target.out"
    classify_expected_failure target "$target_test" "$marker" 1 "$self_test_dir/target.out"

    printf '%s\n' \
        "Test Case '-[OpenTypeTests.RemoteMicCallbackRoutingTests ${target_test}]' failed" \
        "XCTAssertTrue failed - ${marker}" \
        "error: emit-module command failed with exit code 1" \
        >"$self_test_dir/compile.out"
    if classify_expected_failure compile "$target_test" "$marker" 1 "$self_test_dir/compile.out"; then
        reject "classifier accepted a compiler failure"
    fi

    if classify_expected_failure signal "$target_test" "$marker" 139 "$self_test_dir/target.out"; then
        reject "classifier accepted a signal failure"
    fi
    if classify_expected_failure timeout "$target_test" "$marker" 142 "$self_test_dir/target.out"; then
        reject "classifier accepted a timeout failure"
    fi

    printf '%s\n' \
        "Test Case '-[OpenTypeTests.RemoteMicCallbackRoutingTests testUnrelated]' failed" \
        "XCTAssertTrue failed - ${marker}" \
        >"$self_test_dir/unrelated.out"
    if classify_expected_failure unrelated "$target_test" "$marker" 1 "$self_test_dir/unrelated.out"; then
        reject "classifier accepted an unrelated XCTest failure"
    fi

    printf 'CLASSIFIER_SELF_TEST: PASS\n'
}

if [[ "${1:-}" == "--self-test" ]]; then
    classifier_self_test
    exit 0
fi
if [[ "$#" -ne 0 ]]; then
    printf 'usage: %s [--self-test]\n' "$0" >&2
    exit 64
fi

command -v swift >/dev/null 2>&1 || {
    printf 'swift is unavailable; macOS/Xcode XCTest execution was not started\n' >&2
    exit 127
}

SOURCE_REPO="${REPO_DIR:-$(git rev-parse --show-toplevel)}"
BASE_SHA="${BASE_SHA:-$(git -C "$SOURCE_REPO" rev-parse HEAD)}"
RUN_TIMEOUT_SECONDS="${RUN_TIMEOUT_SECONDS:-1800}"
LOG_PATH="${LOG_PATH:-$PWD/vec4-central-gate-mutations-${BASE_SHA:0:12}.log}"

[[ "$RUN_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] \
    || { printf 'RUN_TIMEOUT_SECONDS must be a positive integer\n' >&2; exit 64; }
git -C "$SOURCE_REPO" cat-file -e "${BASE_SHA}^{commit}"
if [[ "$LOG_PATH" != /* ]]; then
    LOG_PATH="$PWD/$LOG_PATH"
fi
[[ ! -e "$LOG_PATH" ]] \
    || { printf 'refusing to overwrite existing log: %s\n' "$LOG_PATH" >&2; exit 73; }

RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vec4-central-gates.XXXXXX")"
cleanup() {
    rm -rf "$RUN_DIR"
}
trap cleanup EXIT

exec > >(tee "$LOG_PATH") 2>&1

printf '=== VEC-4 / #104 central gate mutation harness ===\n'
printf 'BASE_SHA: %s\n' "$BASE_SHA"
printf 'SOURCE_REPO: %s\n' "$SOURCE_REPO"
printf 'RUN_TIMEOUT_SECONDS: %s\n' "$RUN_TIMEOUT_SECONDS"
printf 'LOG_PATH: %s\n' "$LOG_PATH"
printf 'UNAME: %s\n' "$(uname -a)"
printf 'SWIFT: %s\n' "$(swift --version | tr '\n' ';')"
printf 'XCODEBUILD: %s\n' "$(xcodebuild -version | tr '\n' ';')"
printf 'SCRIPT_SHA256: %s\n' "$(shasum -a 256 "$0" | awk '{print $1}')"

git clone --quiet --no-hardlinks "$SOURCE_REPO" "$RUN_DIR/repo"
git -C "$RUN_DIR/repo" checkout --quiet --detach "$BASE_SHA"
readonly REPO="$RUN_DIR/repo"

[[ "$(git -C "$REPO" rev-parse HEAD)" == "$BASE_SHA" ]]
[[ -z "$(git -C "$REPO" status --porcelain)" ]]
test -f "$REPO/review-evidence/vec4-central-gate-mutations.sh"
printf 'INITIAL_HEAD: %s\n' "$(git -C "$REPO" rev-parse HEAD)"
printf 'INITIAL_TREE: %s\n' "$(git -C "$REPO" rev-parse 'HEAD^{tree}')"
printf 'INITIAL_STATUS: clean\n'

TEST_EXIT_CODE=0
run_timed_test() {
    local label="$1"
    local filter="$2"
    local output_file="$RUN_DIR/${label}.out"
    local started_at
    local finished_at
    local started_epoch
    local finished_epoch

    printf '\n=== %s ===\n' "$label"
    printf 'COMMAND: swift test --filter %s\n' "$filter"
    started_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    started_epoch="$(date '+%s')"
    printf 'STARTED_AT: %s\n' "$started_at"
    set +e
    (
        cd "$REPO"
        /usr/bin/perl -e 'alarm shift; exec @ARGV or die "exec failed: $!\n"' \
            "$RUN_TIMEOUT_SECONDS" swift test --filter "$filter"
    ) >"$output_file" 2>&1
    TEST_EXIT_CODE=$?
    set -e
    finished_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    finished_epoch="$(date '+%s')"
    cat "$output_file"
    printf 'TEST_EXIT_CODE: %s\n' "$TEST_EXIT_CODE"
    printf 'FINISHED_AT: %s\n' "$finished_at"
    printf 'ELAPSED_SECONDS: %s\n' "$((finished_epoch - started_epoch))"
}

run_pass() {
    local filter="$1"
    run_timed_test baseline "$filter"
    [[ "$TEST_EXIT_CODE" -eq 0 ]] \
        || { printf 'baseline test failed or timed out (exit=%s)\n' "$TEST_EXIT_CODE" >&2; exit 1; }
    printf 'BASELINE: PASS\n'
}

restore_source() {
    printf 'RESTORE_COMMAND_CWD: %s\n' "$REPO"
    printf 'RESTORE_COMMAND: git restore --source=%s --worktree -- %s\n' \
        "$BASE_SHA" "$SOURCE_REL"
    git -C "$REPO" restore --source="$BASE_SHA" --worktree -- "$SOURCE_REL"
}

apply_mutation() {
    local expression="$1"

    printf 'MUTATION_COMMAND_CWD: %s\n' "$REPO"
    printf 'MUTATION_COMMAND:'
    printf ' %q' perl -0pi -e "$expression" "$SOURCE_REL"
    printf '\n'
    (
        cd "$REPO"
        perl -0pi -e "$expression" "$SOURCE_REL"
    )
}

record_mutation() {
    local label="$1"
    printf '\n--- %s mutation diff ---\n' "$label"
    git -C "$REPO" diff --check
    git -C "$REPO" diff -- "$SOURCE_REL"
    [[ "$(git -C "$REPO" status --porcelain)" == " M $SOURCE_REL" ]]
}

restore_and_prove() {
    local label="$1"
    restore_source
    git -C "$REPO" diff --exit-code "$BASE_SHA" -- "$SOURCE_REL"
    [[ -z "$(git -C "$REPO" status --porcelain)" ]]
    printf '%s_RESTORED_HEAD: %s\n' "$label" "$(git -C "$REPO" rev-parse HEAD)"
    printf '%s_RESTORED_TREE: %s\n' "$label" "$(git -C "$REPO" rev-parse 'HEAD^{tree}')"
    printf '%s_RESTORED_STATUS: clean\n' "$label"
}

run_mutation() {
    local label="$1"
    local test_name="$2"
    local assertion_marker="$3"
    local filter="$TEST_CLASS/$test_name"
    local classifier_exit

    record_mutation "$label"
    run_timed_test "$label" "$filter"
    set +e
    classify_expected_failure \
        "$label" "$test_name" "$assertion_marker" "$TEST_EXIT_CODE" "$RUN_DIR/${label}.out"
    classifier_exit=$?
    set -e
    restore_and_prove "$label"
    [[ "$classifier_exit" -eq 0 ]] || exit "$classifier_exit"
}

run_pass "$TEST_CLASS"

restore_source
apply_mutation \
    's/(private func currentCentralAttempt\([\s\S]*?guard let transport = centralTransport,\n)\s*transport\.identity === managerIdentity,\n/$1/' \
run_mutation manager \
    testCentralManagerIdentityGateRejectsWrongManager \
    "manager identity gate must reject a same-attempt callback from another manager"

restore_source
apply_mutation \
    's/(private func currentCentralAttempt\([\s\S]*?let activePeripheralIdentity = self\.peripheralIdentity,\n)\s*activePeripheralIdentity === peripheralIdentity else/$1true else/' \
run_mutation peripheral \
    testCentralPeripheralIdentityGateRejectsWrongPeripheral \
    "peripheral identity gate must reject a same-attempt callback from another peripheral"

restore_source
apply_mutation \
    's/(private func currentCentralAttempt\([\s\S]*?)guard let sourceAttempt,\n\s*activeConnectionAttempt == sourceAttempt,\n\s*handshake\.accepts\(sourceAttempt\) else \{ return nil \}\n\s*guard let active = centralLifecycle\.attempt, active == sourceAttempt else \{ return nil \}/$1guard let sourceAttempt else { return nil }/' \
run_mutation attempt \
    testCentralAttemptIdentityGateRejectsWrongAttempt \
    "source attempt gate must reject a stale attempt from the active manager and peripheral"

git -C "$REPO" diff --exit-code "$BASE_SHA" -- .
[[ -z "$(git -C "$REPO" status --porcelain)" ]]
printf '\nFINAL_HEAD: %s\n' "$(git -C "$REPO" rev-parse HEAD)"
printf 'FINAL_TREE: %s\n' "$(git -C "$REPO" rev-parse 'HEAD^{tree}')"
printf 'FINAL_STATUS: clean\n'
printf 'RESULT: PASS — baseline green, three target mutations red, every restore exact\n'
