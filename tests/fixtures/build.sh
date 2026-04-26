#!/usr/bin/env bash
# Build SQLite fixtures from .sql schemas. Idempotent — overwrites .db files.
set -euo pipefail

HERE=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)

for schema in "$HERE"/*/schema.sql; do
    [[ -e "$schema" ]] || continue
    dir=$(dirname "$schema")
    db_name=$(basename "$schema" .sql)
    case "$db_name" in
        # Some harnesses use a non-default DB filename
        schema)
            # Default fallback: derive from the parent dir name
            db_path="$dir/$(basename "$dir").db"
            ;;
        *)
            db_path="$dir/${db_name}.db"
            ;;
    esac

    # The dir name dictates which DB filename the adapter expects, so prefer
    # that mapping when known.
    case "$(basename "$dir")" in
        goose)    db_path="$dir/sessions.db" ;;
        opencode) db_path="$dir/opencode.db" ;;
        forge)    db_path="$dir/.forge.db"   ;;
    esac

    rm -f "$db_path" "${db_path}-wal" "${db_path}-shm"
    sqlite3 "$db_path" < "$schema"
done

printf 'fixtures built\n'
