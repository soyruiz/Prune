# shellcheck shell=bash
# Adapter: Goose (block/goose, AAIF fork)
# Storage: ~/.local/share/goose/sessions/sessions.db (SQLite, since v1.10)
#
# We query the DB directly with sqlite3 for two reasons:
#   - Independence from the `goose` CLI being installed (CI, fresh machines).
#   - Goose v1.31+ reads the `session remove` confirmation from /dev/tty, so
#     `yes | goose session remove` hangs. SQL DELETE inside a transaction is
#     the cleanest, most portable bypass.
#
# Override the DB path with PRUNE_GOOSE_DB (used by tests).

PRUNE_GOOSE_DB="${PRUNE_GOOSE_DB:-$HOME/.local/share/goose/sessions/sessions.db}"

prune_goose_doctor() {
    if ! command -v sqlite3 >/dev/null 2>&1; then
        printf 'goose: sqlite3 not installed (required to query/delete)\n' >&2
        return 1
    fi
    if [[ ! -f "$PRUNE_GOOSE_DB" ]]; then
        printf 'goose: sessions DB not found: %s\n' "$PRUNE_GOOSE_DB" >&2
        return 1
    fi
    return 0
}

# stdout: id<TAB>title<TAB>working_dir<TAB>updated<TAB>messages<TAB>tokens<TAB>model
prune_goose_inventory() {
    [[ -f "$PRUNE_GOOSE_DB" ]] || return 0
    sqlite3 -separator $'\t' "$PRUNE_GOOSE_DB" "
        SELECT s.id,
               COALESCE(NULLIF(s.name, ''), '(unnamed)'),
               s.working_dir,
               strftime('%Y-%m-%d %H:%M', COALESCE(s.updated_at, s.created_at)),
               (SELECT COUNT(*) FROM messages m WHERE m.session_id = s.id),
               COALESCE(s.total_tokens, 0),
               COALESCE(json_extract(s.model_config_json, '\$.model_name'), '?')
        FROM sessions s
        ORDER BY COALESCE(s.updated_at, s.created_at) DESC;
    " 2>/dev/null
}

prune_goose_preview() {
    local sid="$1"
    [[ -z "$sid" || "$sid" == "HEADER" ]] && return 0

    # If `goose` CLI is available, prefer its rendered markdown export.
    if command -v goose >/dev/null 2>&1; then
        local out
        out=$(timeout 5 goose session export --session-id "$sid" --format markdown -o /dev/stdout 2>/dev/null \
              | grep -v '^Session exported to ' \
              | head -150)
        if [[ -n "$out" ]]; then
            printf '%s\n' "$out"
            return 0
        fi
    fi

    # Fallback: build preview directly from the DB.
    [[ -f "$PRUNE_GOOSE_DB" ]] || { printf '(no DB)\n'; return 0; }
    PRUNE_GOOSE_SID="$sid" PRUNE_GOOSE_DB="$PRUNE_GOOSE_DB" python3 <<'PY'
import json, os, subprocess, sys, textwrap
sid = os.environ.get('PRUNE_GOOSE_SID', '')
db  = os.environ.get('PRUNE_GOOSE_DB', '')

def q(sql, *args):
    cmd = ['sqlite3', '-json', db, sql]
    out = subprocess.run(cmd, capture_output=True, text=True, check=False).stdout
    if not out.strip():
        return []
    try:
        return json.loads(out)
    except Exception:
        return []

# We can't use bind-params with sqlite3 -json in this minimal way, so embed sid
# safely (it's a known goose-shaped string id like YYYYMMDD_N).
import re
if not re.match(r'^[A-Za-z0-9_\-]+$', sid):
    print(f"(invalid id: {sid})")
    sys.exit(0)

rows = q(f"SELECT id, name, working_dir, created_at, updated_at, total_tokens, model_config_json FROM sessions WHERE id='{sid}'")
if not rows:
    print(f"(session not found: {sid})")
    sys.exit(0)
s = rows[0]
print(f"id:        {s.get('id','')}")
print(f"name:      {s.get('name','')}")
print(f"cwd:       {s.get('working_dir','')}")
print(f"created:   {s.get('created_at','')}")
print(f"updated:   {s.get('updated_at','')}")
print(f"tokens:    {s.get('total_tokens','')}")
mc = s.get('model_config_json') or '{}'
try:
    print(f"model:     {json.loads(mc).get('model_name','?')}")
except Exception:
    print("model:     ?")
print()

msgs = q(f"SELECT role, content_json FROM messages WHERE session_id='{sid}' ORDER BY id ASC")
print(f"messages:  {len(msgs)}")
print()

def first_text(content_raw):
    try:
        parts = json.loads(content_raw or '[]')
    except Exception:
        return ''
    if isinstance(parts, list):
        for p in parts:
            if isinstance(p, dict) and p.get('type') == 'text':
                return p.get('text', '') or ''
    if isinstance(parts, str):
        return parts
    return ''

first_user = None
last_assistant = None
for m in msgs:
    txt = first_text(m.get('content_json', ''))
    if m.get('role') == 'user' and first_user is None and txt:
        first_user = txt
    if m.get('role') == 'assistant' and txt:
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
}

prune_goose_delete() {
    local -a ids=("$@")
    local n=${#ids[@]}
    (( n == 0 )) && { _ui_dim "[prune goose] nothing to delete"; return 0; }

    if ! command -v sqlite3 >/dev/null 2>&1; then
        _ui_err "goose: sqlite3 not installed"
        return 1
    fi
    if [[ ! -f "$PRUNE_GOOSE_DB" ]]; then
        _ui_err "goose: sessions DB not found: $PRUNE_GOOSE_DB"
        return 1
    fi

    # Build a SQL IN-list. Defensive single-quote escaping; goose IDs are
    # YYYYMMDD_N so injection is unlikely, but quote anyway.
    local quoted="" id esc
    for id in "${ids[@]}"; do
        esc=${id//\'/\'\'}
        if [[ -z "$quoted" ]]; then
            quoted="'$esc'"
        else
            quoted="${quoted},'$esc'"
        fi
    done

    printf '[prune goose] removing %d session(s) via SQL...\n' "$n"
    if ! sqlite3 "$PRUNE_GOOSE_DB" >/dev/null 2>&1 <<SQL
BEGIN;
DELETE FROM messages WHERE session_id IN (${quoted});
DELETE FROM thread_messages WHERE session_id IN (${quoted});
DELETE FROM sessions WHERE id IN (${quoted});
COMMIT;
PRAGMA wal_checkpoint(TRUNCATE);
SQL
    then
        _ui_err "goose: sqlite3 transaction failed"
        return 1
    fi

    # Verify by re-counting.
    local survived=0 survivor
    for id in "${ids[@]}"; do
        esc=${id//\'/\'\'}
        survivor=$(sqlite3 "$PRUNE_GOOSE_DB" "SELECT 1 FROM sessions WHERE id='$esc' LIMIT 1;" 2>/dev/null)
        if [[ -n "$survivor" ]]; then
            survived=$(( survived + 1 ))
        fi
    done

    if (( survived > 0 )); then
        _ui_warn "goose: ${survived} session(s) survived removal (DB locked?)"
        return 1
    fi
    _ui_ok "deleted ${n} session(s)"
}
