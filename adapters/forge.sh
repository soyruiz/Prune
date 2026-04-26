# shellcheck shell=bash
# Adapter: Forge (proprietary; tested against the local install)
# Storage: ~/.forge/.forge.db (SQLite, single `conversations` table)
#
# The `context` column embeds an XML-ish blob whose <current_working_directory>
# tag captures the cwd. NULL context indicates an "orphan" conversation that
# Forge's own `forge conversation delete` may fail to remove — so we always
# DELETE via SQL inside a transaction (this is the same pattern Forge's
# original `:prune` script uses as a fallback).
#
# Override the DB path with PRUNE_FORGE_DB (used by tests).

PRUNE_FORGE_DB="${PRUNE_FORGE_DB:-$HOME/.forge/.forge.db}"

prune_forge_doctor() {
    if ! command -v sqlite3 >/dev/null 2>&1; then
        printf 'forge: sqlite3 not installed\n' >&2
        return 1
    fi
    if [[ ! -f "$PRUNE_FORGE_DB" ]]; then
        printf 'forge: DB not found: %s\n' "$PRUNE_FORGE_DB" >&2
        return 1
    fi
    return 0
}

# stdout: id<TAB>title<TAB>directory<TAB>updated<TAB>messages
prune_forge_inventory() {
    [[ -f "$PRUNE_FORGE_DB" ]] || return 0
    PRUNE_FORGE_DB="$PRUNE_FORGE_DB" python3 <<'PY'
import json, os, re, sqlite3, sys
db = os.environ.get('PRUNE_FORGE_DB', '')
if not db or not os.path.isfile(db):
    sys.exit(0)

con = sqlite3.connect(db)
try:
    cur = con.execute("""
        SELECT conversation_id,
               COALESCE(NULLIF(title,''), '(untitled)') AS title,
               context,
               COALESCE(updated_at, created_at) AS upd
        FROM conversations
        ORDER BY COALESCE(updated_at, created_at) DESC
    """)
    rx_cwd = re.compile(r'<current_working_directory>([^<]+)</current_working_directory>')
    rx_msg = re.compile(r'<message\b', flags=re.IGNORECASE)
    for cid, title, ctx, upd in cur:
        cwd = ''
        msgs = 0
        orphan = ctx is None
        if ctx:
            m = rx_cwd.search(ctx)
            if m:
                cwd = m.group(1).strip()
            msgs = len(rx_msg.findall(ctx))
        upd_fmt = (upd or '')[:16].replace('T', ' ')
        title_disp = title.replace('\t', ' ').replace('\n', ' ').strip() or '(untitled)'
        if orphan and not title_disp.startswith('[orphan]'):
            title_disp = '[orphan] ' + title_disp
        print(f"{cid}\t{title_disp}\t{cwd}\t{upd_fmt}\t{msgs}")
finally:
    con.close()
PY
}

prune_forge_preview() {
    local sid="$1"
    [[ -z "$sid" || "$sid" == "HEADER" ]] && return 0

    if command -v forge >/dev/null 2>&1 \
       && [[ "$PRUNE_FORGE_DB" == "$HOME/.forge/.forge.db" ]]; then
        local out
        out=$(timeout 5 forge conversation show "$sid" 2>/dev/null | head -150)
        if [[ -n "$out" ]]; then
            printf '%s\n' "$out"
            return 0
        fi
    fi

    [[ -f "$PRUNE_FORGE_DB" ]] || { printf '(no DB)\n'; return 0; }
    PRUNE_FORGE_SID="$sid" PRUNE_FORGE_DB="$PRUNE_FORGE_DB" python3 <<'PY'
import os, re, sqlite3, sys, textwrap
sid = os.environ.get('PRUNE_FORGE_SID', '')
db  = os.environ.get('PRUNE_FORGE_DB', '')
if not re.match(r'^[A-Za-z0-9_\-]+$', sid):
    print(f"(invalid id: {sid})")
    sys.exit(0)
con = sqlite3.connect(db)
try:
    cur = con.execute(
        "SELECT conversation_id, title, context, created_at, updated_at "
        "FROM conversations WHERE conversation_id=?", (sid,))
    row = cur.fetchone()
finally:
    con.close()
if not row:
    print(f"(conversation not found: {sid})")
    sys.exit(0)
cid, title, ctx, created, updated = row
rx_cwd = re.compile(r'<current_working_directory>([^<]+)</current_working_directory>')
rx_msg = re.compile(r'<message[^>]*>([^<]*)</message>', flags=re.IGNORECASE | re.DOTALL)
rx_role = re.compile(r'<message\s+role="([^"]+)"', flags=re.IGNORECASE)
cwd = ''
if ctx:
    m = rx_cwd.search(ctx); cwd = m.group(1) if m else ''
print(f"id:        {cid}")
print(f"title:     {title or '(untitled)'}")
print(f"cwd:       {cwd}")
print(f"created:   {created or ''}")
print(f"updated:   {updated or ''}")

# Pull inline message text — best effort; Forge's context format is opaque.
first_user = None
last_assistant = None
n = 0
if ctx:
    msgs = rx_msg.findall(ctx)
    roles = rx_role.findall(ctx)
    n = len(msgs)
    for role, txt in zip(roles, msgs):
        if role.lower() == 'user' and first_user is None and txt.strip():
            first_user = txt.strip()
        if role.lower() == 'assistant' and txt.strip():
            last_assistant = txt.strip()
print(f"messages:  {n}")
print()

def show(label, txt):
    print(f"--- {label} ---")
    if not txt:
        print("(empty)"); return
    wrapped = textwrap.fill(txt, width=80, replace_whitespace=False, drop_whitespace=False)
    for ln in wrapped.splitlines()[:25]:
        print(ln)
show("first user message", first_user or '')
print()
show("last assistant message", last_assistant or '')
PY
}

prune_forge_delete() {
    local -a ids=("$@")
    local n=${#ids[@]}
    (( n == 0 )) && { _ui_dim "[prune forge] nothing to delete"; return 0; }

    if ! command -v sqlite3 >/dev/null 2>&1; then
        _ui_err "forge: sqlite3 not installed"
        return 1
    fi
    if [[ ! -f "$PRUNE_FORGE_DB" ]]; then
        _ui_err "forge: DB not found: $PRUNE_FORGE_DB"
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

    printf '[prune forge] removing %d conversation(s) via SQL...\n' "$n"
    if ! sqlite3 "$PRUNE_FORGE_DB" >/dev/null 2>&1 <<SQL
BEGIN;
DELETE FROM conversations WHERE conversation_id IN (${quoted});
COMMIT;
PRAGMA wal_checkpoint(TRUNCATE);
SQL
    then
        _ui_err "forge: sqlite3 transaction failed"
        return 1
    fi

    local survived=0
    for id in "${ids[@]}"; do
        esc=${id//\'/\'\'}
        local exists
        exists=$(sqlite3 "$PRUNE_FORGE_DB" "SELECT 1 FROM conversations WHERE conversation_id='$esc' LIMIT 1;" 2>/dev/null)
        [[ -n "$exists" ]] && survived=$(( survived + 1 ))
    done
    if (( survived > 0 )); then
        _ui_warn "forge: ${survived} conversation(s) survived removal"
        return 1
    fi
    _ui_ok "deleted ${n} conversation(s)"
}
