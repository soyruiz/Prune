# shellcheck shell=bash
# Minimal assertion helpers — bash-pure, no bats required.
# Each test file is a bash script that sources this and calls assertions.
# A failure prints a diagnostic and increments _TESTS_FAILED.

_TESTS_RUN=0
_TESTS_FAILED=0
_TEST_NAME=""

_test_begin() {
    _TEST_NAME="$1"
    _TESTS_RUN=$(( _TESTS_RUN + 1 ))
}

_test_fail() {
    _TESTS_FAILED=$(( _TESTS_FAILED + 1 ))
    printf '  ✗ %s\n    %s\n' "$_TEST_NAME" "$1" >&2
}

_test_pass() {
    printf '  ✓ %s\n' "$_TEST_NAME"
}

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [[ "$expected" == "$actual" ]]; then
        _test_pass
    else
        _test_fail "${msg:-equality}: expected [${expected}], got [${actual}]"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "$haystack" == *"$needle"* ]]; then
        _test_pass
    else
        _test_fail "${msg:-contains}: '${needle}' not found in: ${haystack}"
    fi
}

assert_exit() {
    local expected="$1"; shift
    local actual=0
    "$@" >/dev/null 2>&1 || actual=$?
    if [[ "$expected" == "$actual" ]]; then
        _test_pass
    else
        _test_fail "exit code: expected ${expected}, got ${actual} (cmd: $*)"
    fi
}

assert_lines_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    local exp_n act_n
    exp_n=$(printf '%s\n' "$expected" | wc -l)
    act_n=$(printf '%s\n' "$actual"   | wc -l)
    if [[ "$exp_n" == "$act_n" ]]; then
        _test_pass
    else
        _test_fail "${msg:-line count}: expected ${exp_n}, got ${act_n}"
    fi
}

_test_summary() {
    printf '\n'
    if (( _TESTS_FAILED == 0 )); then
        printf '✓ %d test(s) passed\n' "$_TESTS_RUN"
    else
        printf '✗ %d/%d test(s) failed\n' "$_TESTS_FAILED" "$_TESTS_RUN" >&2
    fi
    return "$_TESTS_FAILED"
}
