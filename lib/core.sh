# shellcheck shell=bash
# Core helpers — harness-agnostic. Sourced by bin/prune; never sourced by users.
#
# Adapter contract (see docs/ADAPTERS.md):
#   prune_<name>_inventory  : prints tab-separated rows: id\ttitle\tdir\tupdated\tmessages[\textra...]
#   prune_<name>_preview ID : prints human preview to stdout
#   prune_<name>_delete IDS : deletes; exit 0 = full success, 1 = any failure
#   prune_<name>_doctor     : optional; exit 0/1 + stderr message

# ---------- age parser ------------------------------------------------------
# Convert "30d", "12h", "45m" -> seconds. Exits 1 (no echo) on parse error.
_prune_parse_age() {
    local arg="$1"
    if [[ ! "$arg" =~ ^([0-9]+)([dhm])$ ]]; then
        return 1
    fi
    local num="${BASH_REMATCH[1]}"
    local unit="${BASH_REMATCH[2]}"
    case "$unit" in
        d) printf '%d\n' $(( num * 86400 )) ;;
        h) printf '%d\n' $(( num * 3600  )) ;;
        m) printf '%d\n' $(( num * 60    )) ;;
    esac
}

# Convert "YYYY-MM-DD HH:MM" (or any `date -d`-parseable string) -> epoch seconds.
# Echoes empty string on parse failure (caller decides what to do).
_prune_to_epoch() {
    date -d "$1" +%s 2>/dev/null || true
}

# ---------- inventory filtering --------------------------------------------
# Read inventory rows on stdin (id\t...\tdir\tupdated\t...) and filter.
# Args: $1 = mode ("here" | "<N>{d,h,m}" | "all"); $2 = $PWD or cutoff_seconds.
# Stdout: filtered IDs (one per line).
_prune_filter_inventory() {
    local mode="$1"
    case "$mode" in
        all)
            awk -F'\t' '{print $1}'
            ;;
        here)
            local cwd="$2"
            awk -F'\t' -v c="$cwd" '$3==c {print $1}'
            ;;
        age)
            local cutoff="$2"
            awk -F'\t' -v c="$cutoff" '
                {
                    cmd = "date -d \"" $4 "\" +%s 2>/dev/null"
                    cmd | getline ts
                    close(cmd)
                    if (ts != "" && ts < c) print $1
                }'
            ;;
        *)
            return 1
            ;;
    esac
}

# ---------- aligned table for fzf -------------------------------------------
# Wrap inventory rows into "<id>\t<aligned-display-line>" so fzf shows the
# pretty line via --with-nth=2 while keeping the id extractable as field 1.
# Format adapts to the number of columns:
#   - 5 cols  (id title dir updated msgs)
#   - 6 cols  (id title dir updated msgs extra1)
#   - 7 cols  (id title dir updated msgs extra1 extra2)
# Header row is emitted with literal first field "HEADER" and is suitable for
# `fzf --header-lines=1`.
_prune_format_table() {
    awk -F'\t' '
        function trunc(s, n) { return (length(s) > n ? substr(s,1,n-1) "…" : s) }
        BEGIN {
            id_w=24; title_w=50; upd_w=16; msgs_w=4;
        }
        NR==1 {
            n_cols = NF
            # header
            if (n_cols == 5)
                hdr = sprintf("%-*s  %-*s  %-*s  %*s  %s", \
                              id_w, "ID", title_w, "TITLE", upd_w, "UPDATED", msgs_w, "MSGS", "DIRECTORY")
            else if (n_cols == 6)
                hdr = sprintf("%-*s  %-*s  %-*s  %*s  %-12s  %s", \
                              id_w, "ID", title_w, "TITLE", upd_w, "UPDATED", msgs_w, "MSGS", "EXTRA", "DIRECTORY")
            else
                hdr = sprintf("%-*s  %-*s  %-*s  %*s  %-12s  %-12s  %s", \
                              id_w, "ID", title_w, "TITLE", upd_w, "UPDATED", msgs_w, "MSGS", "EXTRA1", "EXTRA2", "DIRECTORY")
            printf "HEADER\t%s\n", hdr
        }
        {
            id_disp    = trunc($1, id_w)
            title_disp = trunc($2, title_w)
            dir_disp   = $3
            upd_disp   = $4
            msgs_disp  = $5
            extra1     = (NF >= 6 ? trunc($6, 12) : "")
            extra2     = (NF >= 7 ? trunc($7, 12) : "")
            if (NF == 5)
                line = sprintf("%-*s  %-*s  %-*s  %*d  %s", \
                               id_w, id_disp, title_w, title_disp, upd_w, upd_disp, msgs_w, msgs_disp, dir_disp)
            else if (NF == 6)
                line = sprintf("%-*s  %-*s  %-*s  %*d  %-12s  %s", \
                               id_w, id_disp, title_w, title_disp, upd_w, upd_disp, msgs_w, msgs_disp, extra1, dir_disp)
            else
                line = sprintf("%-*s  %-*s  %-*s  %*d  %-12s  %-12s  %s", \
                               id_w, id_disp, title_w, title_disp, upd_w, upd_disp, msgs_w, msgs_disp, extra1, extra2, dir_disp)
            printf "%s\t%s\n", $1, line
        }
    '
}

# ---------- confirm dialog (fzf-as-Yes/No) ---------------------------------
_prune_confirm() {
    local n="$1" desc="$2"
    printf '\n'
    local choice
    choice=$(printf '%s\n%s\n' \
                "No  — cancel" \
                "Yes — delete ${n} session(s) ${desc}" \
            | fzf --reverse --height=20% --no-multi \
                  --prompt="confirm ❯ " \
                  --header="↑↓ to choose, Enter to confirm, Esc to cancel" \
                  --bind="esc:abort")
    [[ "${choice:-}" == Yes* ]]
}

# ---------- main interactive picker ----------------------------------------
# Args: $1 = harness name; reads inventory on stdin.
# Stdout: selected IDs, one per line. Empty if user cancelled.
_prune_pick() {
    local name="$1"
    local table
    table=$(_prune_format_table)
    local selected
    # The preview re-invokes the prune binary so the right adapter loads.
    # PRUNE_BIN is exported by bin/prune.
    selected=$(printf '%s\n' "$table" | fzf \
        --delimiter=$'\t' \
        --with-nth=2 \
        --header-lines=1 \
        --multi \
        --reverse \
        --height=80% \
        --prompt="prune ${name} ❯ " \
        --header=$'Tab=select  Enter=delete  Esc=cancel\n' \
        --preview="${PRUNE_BIN:-prune} --preview ${name} {1}" \
        --preview-window="right:60%:wrap")
    [[ -z "$selected" ]] && return 0
    printf '%s\n' "$selected" | awk -F'\t' '{print $1}'
}

# ---------- the dispatched mode runner -------------------------------------
# Called from bin/prune after sourcing the right adapter. Implements the four
# modes uniformly. Args: $1 = harness name, $2 = mode arg ("" | all | here |
# <N>{d,h,m}), $3 = "1" if --dry-run.
_prune_run_mode() {
    local name="$1" arg="${2:-}" dry="${3:-0}"

    if ! command -v "prune_${name}_inventory" >/dev/null 2>&1 && \
       ! declare -F "prune_${name}_inventory" >/dev/null 2>&1; then
        _ui_err "adapter '${name}' missing prune_${name}_inventory"
        return 1
    fi

    local inventory
    inventory=$("prune_${name}_inventory")
    if [[ -z "$inventory" ]]; then
        printf '\n'
        _ui_dim "[prune ${name}] no sessions stored"
        return 0
    fi

    local -a ids=()
    local desc=""
    case "$arg" in
        all)
            mapfile -t ids < <(printf '%s\n' "$inventory" | _prune_filter_inventory all)
            desc="(ALL sessions)"
            ;;
        here)
            mapfile -t ids < <(printf '%s\n' "$inventory" | _prune_filter_inventory here "$PWD")
            if (( ${#ids[@]} == 0 )); then
                _ui_dim "[prune ${name}] no sessions from $PWD"
                return 0
            fi
            desc="opened in $PWD"
            ;;
        "")
            mapfile -t ids < <(printf '%s\n' "$inventory" | _prune_pick "$name")
            if (( ${#ids[@]} == 0 )); then
                _ui_dim "cancelled"
                return 0
            fi
            desc="(selected)"
            ;;
        *)
            local secs
            if ! secs=$(_prune_parse_age "$arg"); then
                _ui_err "unknown argument: $arg"
                return 1
            fi
            local cutoff=$(( $(date +%s) - secs ))
            mapfile -t ids < <(printf '%s\n' "$inventory" | _prune_filter_inventory age "$cutoff")
            if (( ${#ids[@]} == 0 )); then
                _ui_dim "[prune ${name}] no sessions older than ${arg}"
                return 0
            fi
            desc="older than ${arg}"
            ;;
    esac

    if (( dry == 1 )); then
        printf '%s\n' "Would delete ${#ids[@]} session(s) ${desc}:"
        printf '  %s\n' "${ids[@]}"
        return 0
    fi

    if ! _prune_confirm "${#ids[@]}" "$desc"; then
        _ui_dim "cancelled"
        return 0
    fi

    "prune_${name}_delete" "${ids[@]}"
}

# ---------- doctor checks --------------------------------------------------
# Prints a one-line status per dependency / adapter.
_prune_doctor() {
    local missing=0
    _check_cmd() {
        local c="$1" required="${2:-1}"
        if command -v "$c" >/dev/null 2>&1; then
            _ui_ok "${c} found ($(command -v "$c"))"
        else
            if (( required == 1 )); then
                _ui_err "${c} missing (required)"
                missing=1
            else
                _ui_warn "${c} missing (optional)"
            fi
        fi
    }
    _ui_bold "Prune ${PRUNE_VERSION:-?} doctor"
    printf '\n\n'
    printf '%s\n' "Dependencies:"
    _check_cmd fzf
    _check_cmd python3
    _check_cmd awk
    _check_cmd date
    _check_cmd sqlite3 0   # only required for goose/forge SQL fallback
    printf '\n%s\n' "Adapters:"
    local name fn
    for name in "${PRUNE_ADAPTERS[@]:-}"; do
        [[ -z "$name" ]] && continue
        fn="prune_${name}_doctor"
        if declare -F "$fn" >/dev/null 2>&1; then
            if "$fn"; then
                _ui_ok "${name}"
            else
                _ui_warn "${name} (see message above)"
            fi
        else
            # Default check: is the harness binary on PATH?
            if command -v "$name" >/dev/null 2>&1; then
                _ui_ok "${name}"
            else
                _ui_dim "${name} (CLI not found; adapter loaded but unusable)"
            fi
        fi
    done
    return "$missing"
}
