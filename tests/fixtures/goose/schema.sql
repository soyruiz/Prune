-- Goose sessions.db schema (extracted from goose v1.31).
-- Augmented with sample rows for fixture-based testing.

CREATE TABLE schema_version (
    version INTEGER PRIMARY KEY,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    user_set_name BOOLEAN DEFAULT FALSE,
    session_type TEXT NOT NULL DEFAULT 'user',
    working_dir TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    extension_data TEXT DEFAULT '{}',
    total_tokens INTEGER,
    input_tokens INTEGER,
    output_tokens INTEGER,
    accumulated_total_tokens INTEGER,
    accumulated_input_tokens INTEGER,
    accumulated_output_tokens INTEGER,
    schedule_id TEXT,
    recipe_json TEXT,
    user_recipe_values_json TEXT,
    provider_name TEXT,
    model_config_json TEXT,
    goose_mode TEXT NOT NULL DEFAULT 'auto',
    thread_id TEXT
);

CREATE TABLE messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id TEXT,
    session_id TEXT NOT NULL REFERENCES sessions(id),
    role TEXT NOT NULL,
    content_json TEXT NOT NULL,
    created_timestamp INTEGER NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    tokens INTEGER,
    metadata_json TEXT
);

CREATE TABLE thread_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id TEXT,
    session_id TEXT,
    message_id TEXT,
    role TEXT NOT NULL,
    content_json TEXT NOT NULL,
    created_timestamp INTEGER NOT NULL,
    metadata_json TEXT DEFAULT '{}'
);

-- Sample data: 3 sessions across two working dirs, varying timestamps.
-- Note: the goose adapter doesn't shell out to `goose` for inventory anymore;
-- it queries this DB directly via sqlite3, so these fixtures are sufficient.

INSERT INTO sessions (id, name, working_dir, created_at, updated_at, total_tokens, provider_name, model_config_json) VALUES
  ('20260101_1', 'first fixture session',  '/tmp/prune-test',     '2026-01-01 10:00:00', '2026-01-01 10:05:00',  1000, 'openrouter', '{"model_name":"glm-5"}'),
  ('20260201_1', 'second fixture session', '/tmp/prune-test',     '2026-02-01 12:00:00', '2026-02-01 12:30:00',  3500, 'openrouter', '{"model_name":"qwen-coder"}'),
  ('20260301_1', 'third fixture session',  '/home/fake/project',  '2026-03-01 14:00:00', '2026-03-01 14:15:00',   500, 'anthropic',  '{"model_name":"claude-sonnet-4-6"}');

INSERT INTO messages (message_id, session_id, role, content_json, created_timestamp) VALUES
  ('m1', '20260101_1', 'user',      '[{"type":"text","text":"hola goose fixture 1"}]',     1735718400000),
  ('m2', '20260101_1', 'assistant', '[{"type":"text","text":"hola, soy goose"}]',          1735718401000),
  ('m1', '20260201_1', 'user',      '[{"type":"text","text":"continuamos con la fixture 2"}]', 1738411200000),
  ('m2', '20260201_1', 'assistant', '[{"type":"text","text":"claro, sigamos"}]',           1738411201000),
  ('m3', '20260201_1', 'user',      '[{"type":"text","text":"otra pregunta"}]',            1738411300000),
  ('m1', '20260301_1', 'user',      '[{"type":"text","text":"sesión tres en otro cwd"}]',  1740855600000);
