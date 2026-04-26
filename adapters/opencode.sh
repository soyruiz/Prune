# shellcheck shell=bash
# Adapter: opencode (sst/opencode)
# Storage: ~/.local/share/opencode/opencode.db (SQLite)
#
# We query the DB directly with sqlite3 because:
#   - The official `opencode session list` filters by `project_id = "global"`,
#     hiding sessions from project subdirectories. The user wants ALL sessions.
#   - Direct SQL avoids depending on the `opencode` CLI for inventory/preview.
#
# Deletion uses sqlite3 with PRAGMA foreign_keys=ON so that ON DELETE CASCADE
# on `message`/`part` cleans dependents in one transaction. This matches what
# the official `opencode session delete` does.
#
# Override the DB path with PRUNE_OPENCODE_DB (used by tests).

_PRUNE_OPENCODE_DEFAULT_DB="$HOME/.local/share/opencode/opencode.db"
PRUNE_OPENCODE_DB="${PRUNE_OPENCODE_DB:-$_PRUNE_OPENCODE_DEFAULT_DB}"

# Use the official `opencode` CLI (for preview & delete) only when operating
# on the real DB. With a custom PRUNE_OPENCODE_DB (tests/fixtures), the CLI
# would ignore our path, so fall back to direct SQL.
_prune_opencode_can_use_cli() {
    [[ "$PRUNE_OPENCODE_DB" == "$_PRUNE_OPENCODE_DEFAULT_DB" ]] \
        && command -v opencode >/dev/null 2>&1
}

prune_opencode_doctor() {
    if ! command -v sqlite3 >/dev/null 2>&1; then
        printf 'opencode: sqlite3 not installed (required to query/delete)\n' >&2
        return 1
    fi
    if [[ ! -f "$PRUNE_OPENCODE_DB" ]]; then
        printf 'opencode: DB not found: %s\n' "$PRUNE_OPENCODE_DB" >&2
        return 1
    fi
    return 0
}

# stdout: id<TAB>title<TAB>directory<TAB>updated<TAB>messages<TAB>project<TAB>worktree
prune_opencode_inventory() {
    [[ -f "$PRUNE_OPENCODE_DB" ]] || return 0
    sqlite3 -separator $'\t' "$PRUNE_OPENCODE_DB" "
        SELECT s.id,
               COALESCE(NULLIF(s.title, ''), '(untitled)'),
               s.directory,
               strftime('%Y-%m-%d %H:%M', s.time_updated/1000, 'unixepoch'),
               (SELECT COUNT(*) FROM message m WHERE m.session_id = s.id),
               substr(COALESCE(s.project_id, ''), 1, 12),
               COALESCE(p.worktree, '')
        FROM session s
        LEFT JOIN project p ON s.project_id = p.id
        WHERE s.parent_id IS NULL AND s.time_archived IS NULL
        ORDER BY s.time_updated DESC;
    " 2>/dev/null
}

prune_opencode_preview() {
    local sid="$1"
    [[ -z "$sid" || "$sid" == "HEADER" ]] && return 0

    if _prune_opencode_can_use_cli; then
        local out
        out=$(timeout 5 opencode export "$sid" 2>/dev/null)
        if [[ -n "$out" ]]; then
            PRUNE_OPENCODE_EXPORT="$out" python3 <<'PY'
import json, os, sys, textwrap
data = None
raw = os.environ.get('PRUNE_OPENCODE_EXPORT', '')
try:
    data = json.loads(raw)
except Exception:
    pass
if not data:
    print("(preview unavailable)")
    sys.exit(0)
info = data.get('info', {}) or {}
msgs = data.get('messages', []) or []
print(f"id:        {info.get('id', '')}")
print(f"title:     {info.get('title', '')}")
print(f"directory: {info.get('directory', '')}")
print(f"project:   {info.get('projectID', '')}")
t = info.get('time') or {}
print(f"created:   {t.get('created', '')}")
print(f"updated:   {t.get('updated', '')}")
print(f"messages:  {len(msgs)}")
print()

def first_text(parts):
    for p in (parts or []):
        if isinstance(p, dict) and p.get('type') == 'text':
            return p.get('text', '') or ''
    return ''

first_user = None
last_assistant = None
for m in msgs:
    role = (m.get('info', {}) or {}).get('role')
    txt = first_text(m.get('parts', []))
    if role == 'user' and first_user is None and txt:
        first_user = txt
    if role == 'assistant' and txt:
        last_assistant = txt

def show(label, txt):
    print(f"--- {label} ---")
    if not txt:
        print("(empty)")
        return
    wrapped = textwrap.fill(txt, width=80, replace_whitespace=False, drop_whitespace=False)
    for ln in wrapped.splitlines()[:25]:
        print(ln)
    if len(wrapped.splitlines()) > 25:
        print('...')
show("first user message", first_user or '')
print()
show("last assistant message", last_assistant or '')
PY
            return 0
        fi
    fi

    # Fallback: build preview directly from the DB.
    [[ -f "$PRUNE_OPENCODE_DB" ]] || { printf '(no DB)\n'; return 0; }
    PRUNE_OPENCODE_SID="$sid" PRUNE_OPENCODE_DB="$PRUNE_OPENCODE_DB" python3 <<'PY'
import json, os, re, subprocess, sys, textwrap
sid = os.environ.get('PRUNE_OPENCODE_SID', '')
db  = os.environ.get('PRUNE_OPENCODE_DB', '')
if not re.match(r'^[A-Za-z0-9_\-]+$', sid):
    print(f"(invalid id: {sid})")
    sys.exit(0)

def q(sql):
    out = subprocess.run(['sqlite3', '-json', db, sql],
                         capture_output=True, text=True, check=False).stdout
    if not out.strip():
        return []
    try:
        return json.loads(out)
    except Exception:
        return []

s_rows = q(f"SELECT id, title, directory, project_id, time_created, time_updated FROM session WHERE id='{sid}'")
if not s_rows:
    print(f"(session not found: {sid})")
    sys.exit(0)
s = s_rows[0]
print(f"id:        {s.get('id','')}")
print(f"title:     {s.get('title','')}")
print(f"directory: {s.get('directory','')}")
print(f"project:   {s.get('project_id','')}")
print(f"created:   {s.get('time_created','')}")
print(f"updated:   {s.get('time_updated','')}")

# Both message.data (carries 'role') and part.data (carries 'type:text' + 'text')
# are JSON strings; parse them in python.
msg_count = len(q(f"SELECT id FROM message WHERE session_id='{sid}'"))
print(f"messages:  {msg_count}")
print()

rows = q(f"""
    SELECT m.data AS m_data, p.data AS p_data
    FROM message m
    JOIN part p ON p.message_id = m.id
    WHERE m.session_id = '{sid}'
    ORDER BY m.time_created ASC, p.time_created ASC
""")

def role_of(raw):
    try:
        return (json.loads(raw or '{}') or {}).get('role', '')
    except Exception:
        return ''

def text_of(raw):
    try:
        d = json.loads(raw or '{}')
    except Exception:
        return ''
    if isinstance(d, dict) and d.get('type') == 'text':
        return d.get('text', '') or ''
    return ''

first_user = None
last_assistant = None
for r in rows:
    role = role_of(r.get('m_data', ''))
    txt  = text_of(r.get('p_data', ''))
    if role == 'user' and first_user is None and txt:
        first_user = txt
    if role == 'assistant' and txt:
        last_assistant = txt

def show(label, txt):
    print(f"--- {label} ---")
    if not txt:
        print("(empty)")
        return
    wrapped = textwrap.fill(txt, width=80, replace_whitespace=False, drop_whitespace=False)
    for ln in wrapped.splitlines()[:25]:
        print(ln)
show("first user message", first_user or '')
print()
show("last assistant message", last_assistant or '')
PY
}

prune_opencode_delete() {
    local -a ids=("$@")
    local n=${#ids[@]}
    (( n == 0 )) && { _ui_dim "[prune opencode] nothing to delete"; return 0; }

    if [[ -f "$PRUNE_OPENCODE_DB" ]] && _prune_opencode_can_use_cli; then
        # Prefer the official CLI when both DB and CLI exist (it's silent and
        # cascade-correct). Fall back to direct SQL on per-id failure.
        local i=0 failed=0 sid
        for sid in "${ids[@]}"; do
            i=$(( i + 1 ))
            printf '\r[%d/%d] deleting %s...' "$i" "$n" "$sid"
            if ! command opencode session delete "$sid" >/dev/null 2>&1; then
                failed=$(( failed + 1 ))
            fi
        done
        printf '\r'
        if (( failed > 0 )); then
            _ui_warn "deleted $(( n - failed )) of ${n} (${failed} failed)"
            return 1
        fi
        _ui_ok "deleted ${n} session(s)"
        return 0
    fi

    # SQL fallback: works without the CLI (used in CI / fixtures).
    if ! command -v sqlite3 >/dev/null 2>&1; then
        _ui_err "opencode: neither opencode CLI nor sqlite3 found"
        return 1
    fi
    if [[ ! -f "$PRUNE_OPENCODE_DB" ]]; then
        _ui_err "opencode: DB not found: $PRUNE_OPENCODE_DB"
        return 1
    fi
    local quoted="" id esc
    for id in "${ids[@]}"; do
        esc=${id//\'/\'\'}
        if [[ -z "$quoted" ]]; then
            quoted="'$esc'"
        else
            quoted="${quoted},'$esc'"
        fi
    done
    printf '[prune opencode] removing %d session(s) via SQL...\n' "$n"
    if ! sqlite3 "$PRUNE_OPENCODE_DB" >/dev/null 2>&1 <<SQL
PRAGMA foreign_keys=ON;
BEGIN;
DELETE FROM session WHERE id IN (${quoted});
COMMIT;
PRAGMA wal_checkpoint(TRUNCATE);
SQL
    then
        _ui_err "opencode: sqlite3 transaction failed"
        return 1
    fi
    _ui_ok "deleted ${n} session(s)"
}
