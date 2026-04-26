# shellcheck shell=bash
# Adapter: Pi (badlogic/pi-mono)
# Storage: ~/.pi/agent/sessions/<cwd-encoded>/.../**/*.jsonl
#
# Pi has used two on-disk layouts in recent versions:
#   - Flat:   <cwd-encoded>/<timestamp>_<uuid>.jsonl
#   - Nested: <cwd-encoded>/<top-session>/<subagent-id>/run-N/<timestamp>_<uuid>.jsonl
# We treat every .jsonl under the sessions root as one session (each carries its
# own `type:session` header line with id + cwd). Deletion removes the file and
# walks up its parent dirs cleaning empties (stopping at the sessions root).
#
# Override the storage root with PRUNE_PI_SESSIONS_DIR (used by tests).

PRUNE_PI_SESSIONS_DIR="${PRUNE_PI_SESSIONS_DIR:-$HOME/.pi/agent/sessions}"

prune_pi_doctor() {
    if [[ ! -d "$PRUNE_PI_SESSIONS_DIR" ]]; then
        printf 'pi: sessions dir not found: %s\n' "$PRUNE_PI_SESSIONS_DIR" >&2
        return 1
    fi
    return 0
}

# stdout: id<TAB>title<TAB>directory<TAB>updated<TAB>messages<TAB>path
# (path is an extra column used internally by the delete function — the core
# only reads the first 5 columns, but the table formatter accommodates a 6th.)
prune_pi_inventory() {
    PRUNE_PI_SESSIONS_DIR="$PRUNE_PI_SESSIONS_DIR" python3 <<'PY'
import json, os, sys, glob, datetime
root = os.environ.get('PRUNE_PI_SESSIONS_DIR', '')
if not root or not os.path.isdir(root):
    sys.exit(0)
rows = []
# Recursive glob handles both the legacy flat layout and the new nested one.
for path in glob.glob(os.path.join(root, '**', '*.jsonl'), recursive=True):
    try:
        st = os.stat(path)
    except OSError:
        continue
    sid = ''
    cwd = ''
    title = ''
    msg_count = 0
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            first = f.readline()
            if first:
                try:
                    j = json.loads(first)
                    if j.get('type') == 'session':
                        sid = j.get('id', '') or ''
                        cwd = j.get('cwd', '') or ''
                except json.JSONDecodeError:
                    pass
            for line in f:
                try:
                    j = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if j.get('type') == 'message':
                    msg_count += 1
                    if not title:
                        m = j.get('message', {}) or {}
                        if m.get('role') == 'user':
                            for part in (m.get('content') or []):
                                if isinstance(part, dict) and part.get('type') == 'text':
                                    t = part.get('text', '') or ''
                                    title = t.replace('\t', ' ').replace('\n', ' ').strip()
                                    break
    except OSError:
        continue
    # Use the full UUID as the id (8-char prefix collides for nested subagent
    # JSONLs that share a session timestamp). The fzf picker hides this column
    # via --with-nth=2, so length is not a UX concern.
    full_id = sid or os.path.basename(path)
    title = (title or '(untitled)')[:80]
    updated = datetime.datetime.fromtimestamp(st.st_mtime).strftime('%Y-%m-%d %H:%M')
    rows.append((st.st_mtime, full_id, title, cwd, updated, msg_count, path))

rows.sort(key=lambda r: r[0], reverse=True)
for _, full_id, title, cwd, updated, n, path in rows:
    # Columns: id title directory updated messages path
    print(f"{full_id}\t{title}\t{cwd}\t{updated}\t{n}\t{path}")
PY
}

prune_pi_preview() {
    local sid="$1"
    [[ -z "$sid" || "$sid" == "HEADER" ]] && return 0
    # Resolve short_id -> full path via inventory.
    local target
    target=$(prune_pi_inventory | awk -F'\t' -v s="$sid" '$1==s {print $6; exit}')
    if [[ -z "$target" || ! -f "$target" ]]; then
        printf '(no preview: session %s not found)\n' "$sid"
        return 0
    fi
    PRUNE_PI_FILE="$target" python3 <<'PY'
import json, os, sys, datetime, textwrap
file_path = os.environ.get('PRUNE_PI_FILE', '')
try:
    st = os.stat(file_path)
except OSError:
    sys.exit(0)
sid = ''
cwd = ''
ts = ''
first_user = None
last_assistant = None
msg_count = 0
try:
    with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
        first = f.readline()
        if first:
            try:
                j = json.loads(first)
                if j.get('type') == 'session':
                    sid = j.get('id', '')
                    cwd = j.get('cwd', '')
                    ts = j.get('timestamp', '')
            except json.JSONDecodeError:
                pass
        for line in f:
            try:
                j = json.loads(line)
            except json.JSONDecodeError:
                continue
            if j.get('type') != 'message':
                continue
            msg_count += 1
            m = j.get('message', {}) or {}
            role = m.get('role')
            text = ''
            for part in (m.get('content') or []):
                if isinstance(part, dict) and part.get('type') == 'text':
                    text = part.get('text', '') or ''
                    break
            if role == 'user' and first_user is None:
                first_user = text
            if role == 'assistant':
                last_assistant = text
except OSError:
    sys.exit(0)

mtime = datetime.datetime.fromtimestamp(st.st_mtime).strftime('%Y-%m-%d %H:%M:%S')
size_kb = st.st_size / 1024.0
print(f"path:     {file_path}")
print(f"id:       {sid}")
print(f"cwd:      {cwd}")
print(f"started:  {ts}")
print(f"updated:  {mtime}")
print(f"size:     {size_kb:.1f} KB")
print(f"messages: {msg_count}")
print()
def show(label, txt):
    print(f"--- {label} ---")
    if not txt:
        print("(empty)")
        return
    wrapped = textwrap.fill(txt, width=80, replace_whitespace=False, drop_whitespace=False)
    for ln in wrapped.splitlines()[:25]:
        print(ln)
    if len(wrapped.splitlines()) > 25:
        print("...")
show("first user message", first_user or '')
print()
show("last assistant message", last_assistant or '')
PY
}

prune_pi_delete() {
    local -a ids=("$@")
    local n=${#ids[@]}
    (( n == 0 )) && { _ui_dim "[prune pi] nothing to delete"; return 0; }

    # Resolve short_ids -> full paths via one inventory snapshot.
    local inv
    inv=$(prune_pi_inventory)
    local i=0 failed=0 sid target
    for sid in "${ids[@]}"; do
        i=$(( i + 1 ))
        target=$(printf '%s' "$inv" | awk -F'\t' -v s="$sid" '$1==s {print $6; exit}')
        if [[ -z "$target" || ! -f "$target" ]]; then
            printf '\r[%d/%d] skipping %s (not found)\n' "$i" "$n" "$sid" >&2
            failed=$(( failed + 1 ))
            continue
        fi
        printf '\r[%d/%d] deleting %s...' "$i" "$n" "$sid"
        if ! command rm -f -- "$target"; then
            failed=$(( failed + 1 ))
        fi
    done
    printf '\r'

    # Clean up empty parent dirs (walk up from leaf, collapse chained empties).
    local removed_dirs=0
    if [[ -d "$PRUNE_PI_SESSIONS_DIR" ]]; then
        local root_real
        root_real=$(cd -P "$PRUNE_PI_SESSIONS_DIR" && pwd)
        # `find -mindepth 1 -depth -type d -empty -delete` walks deepest-first
        # AND deletes during traversal, so chains like a/b/c/d collapse all the
        # way up in one pass. Pre-count the dirs we'll remove for the message.
        removed_dirs=$(find "$root_real" -mindepth 1 -depth -type d -empty 2>/dev/null | wc -l | tr -d ' ')
        find "$root_real" -mindepth 1 -depth -type d -empty -delete 2>/dev/null || true
    fi

    if (( failed > 0 )); then
        _ui_warn "deleted $(( n - failed )) of ${n} session(s) (${failed} failed)"
        return 1
    fi
    if (( removed_dirs > 0 )); then
        _ui_ok "deleted ${n} session(s) (${removed_dirs} empty dir(s) removed)"
    else
        _ui_ok "deleted ${n} session(s)"
    fi
}
