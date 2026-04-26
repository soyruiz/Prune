# shellcheck shell=bash
# Plain ANSI helpers. Auto-disabled when stdout is not a TTY or NO_COLOR is set.

if [[ -n "${NO_COLOR:-}" ]] || ! [[ -t 1 ]]; then
    _PRUNE_C_RESET=""
    _PRUNE_C_DIM=""
    _PRUNE_C_RED=""
    _PRUNE_C_GREEN=""
    _PRUNE_C_YELLOW=""
    _PRUNE_C_BLUE=""
    _PRUNE_C_BOLD=""
else
    _PRUNE_C_RESET=$'\033[0m'
    _PRUNE_C_DIM=$'\033[2m'
    _PRUNE_C_RED=$'\033[31m'
    _PRUNE_C_GREEN=$'\033[32m'
    _PRUNE_C_YELLOW=$'\033[33m'
    _PRUNE_C_BLUE=$'\033[34m'
    _PRUNE_C_BOLD=$'\033[1m'
fi

_ui_dim()    { printf '%s%s%s\n' "$_PRUNE_C_DIM"    "$*" "$_PRUNE_C_RESET"; }
_ui_ok()     { printf '%s✓%s %s\n' "$_PRUNE_C_GREEN"  "$_PRUNE_C_RESET" "$*"; }
_ui_warn()   { printf '%s⚠%s %s\n' "$_PRUNE_C_YELLOW" "$_PRUNE_C_RESET" "$*"; }
_ui_err()    { printf '%s✗%s %s\n' "$_PRUNE_C_RED"    "$_PRUNE_C_RESET" "$*" >&2; }
_ui_info()   { printf '%s%s%s\n' "$_PRUNE_C_BLUE"   "$*" "$_PRUNE_C_RESET"; }
_ui_bold()   { printf '%s%s%s'   "$_PRUNE_C_BOLD"   "$*" "$_PRUNE_C_RESET"; }
