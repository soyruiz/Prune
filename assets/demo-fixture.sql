-- Synthetic Goose-format DB used by the README demo GIF.
-- Build it (idempotent):
--   sqlite3 /tmp/prune-demo-fixture.db < assets/demo-fixture.sql
-- Then regenerate the GIF:
--   vhs assets/demo.tape

PRAGMA foreign_keys = ON;

CREATE TABLE schema_version (version INTEGER PRIMARY KEY);
CREATE TABLE sessions (
    id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    user_set_name BOOLEAN DEFAULT FALSE,
    session_type TEXT NOT NULL DEFAULT 'user',
    working_dir TEXT NOT NULL,
    created_at TIMESTAMP, updated_at TIMESTAMP,
    extension_data TEXT DEFAULT '{}',
    total_tokens INTEGER, input_tokens INTEGER, output_tokens INTEGER,
    accumulated_total_tokens INTEGER, accumulated_input_tokens INTEGER, accumulated_output_tokens INTEGER,
    schedule_id TEXT, recipe_json TEXT, user_recipe_values_json TEXT,
    provider_name TEXT, model_config_json TEXT,
    goose_mode TEXT NOT NULL DEFAULT 'auto', thread_id TEXT
);
CREATE TABLE messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT, message_id TEXT,
    session_id TEXT NOT NULL REFERENCES sessions(id),
    role TEXT NOT NULL, content_json TEXT NOT NULL,
    created_timestamp INTEGER NOT NULL, timestamp TIMESTAMP, tokens INTEGER, metadata_json TEXT
);
CREATE TABLE thread_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT, thread_id TEXT, session_id TEXT,
    message_id TEXT, role TEXT NOT NULL, content_json TEXT NOT NULL,
    created_timestamp INTEGER NOT NULL, metadata_json TEXT DEFAULT '{}'
);

INSERT INTO sessions (id, name, working_dir, created_at, updated_at, total_tokens, model_config_json) VALUES
  ('20260426_8', 'Refactor auth middleware to TS', '/home/dev/myapp',          '2026-04-26 14:30:00', '2026-04-26 15:12:00', 12450, '{"model_name":"claude-sonnet-4-6"}'),
  ('20260426_7', 'Investigate flaky CI tests',     '/home/dev/myapp',          '2026-04-26 11:20:00', '2026-04-26 12:45:00',  8930, '{"model_name":"glm-5"}'),
  ('20260425_4', 'Set up nginx reverse proxy',     '/home/dev/infra',          '2026-04-25 18:00:00', '2026-04-25 19:30:00',  4200, '{"model_name":"gpt-5-codex"}'),
  ('20260425_3', 'Optimize SQL query for orders',  '/home/dev/myapp',          '2026-04-25 09:15:00', '2026-04-25 10:40:00', 21800, '{"model_name":"claude-opus-4-7"}'),
  ('20260424_5', 'Quick fix typo in README',       '/home/dev/myapp',          '2026-04-24 22:10:00', '2026-04-24 22:12:00',   320, '{"model_name":"qwen3-coder"}'),
  ('20260424_2', 'Migrate from webpack to vite',   '/home/dev/dashboard',      '2026-04-24 14:00:00', '2026-04-24 17:25:00', 34550, '{"model_name":"claude-sonnet-4-6"}'),
  ('20260423_9', 'Wire up Stripe webhooks',        '/home/dev/billing-svc',    '2026-04-23 16:00:00', '2026-04-23 18:45:00', 18200, '{"model_name":"glm-5"}'),
  ('20260423_4', 'Tune Postgres connection pool',  '/home/dev/billing-svc',    '2026-04-23 10:30:00', '2026-04-23 11:50:00',  6700, '{"model_name":"gpt-5-codex"}'),
  ('20260422_6', 'Trial: rewrite parser in Rust',  '/home/dev/lab/parser-rs',  '2026-04-22 20:15:00', '2026-04-22 23:40:00', 28900, '{"model_name":"claude-opus-4-7"}'),
  ('20260422_1', 'CLI Session',                    '/home/dev',                '2026-04-22 09:00:00', '2026-04-22 09:01:00',     0, '{"model_name":"glm-5"}'),
  ('20260421_3', 'Read docs on tree-sitter',       '/home/dev/notes',          '2026-04-21 21:00:00', '2026-04-21 21:35:00',  3100, '{"model_name":"qwen3-coder"}'),
  ('20260420_5', 'Bump deps + audit',              '/home/dev/myapp',          '2026-04-20 13:00:00', '2026-04-20 13:55:00',  5400, '{"model_name":"claude-sonnet-4-6"}');

INSERT INTO messages (message_id, session_id, role, content_json, created_timestamp) VALUES
  ('m1', '20260426_8', 'user',      '[{"type":"text","text":"Vamos a refactorizar el middleware de auth a TypeScript. Empieza por reescribir auth-middleware.js como auth-middleware.ts manteniendo toda la lógica intacta."}]', 1761491400000),
  ('m2', '20260426_8', 'assistant', '[{"type":"text","text":"Perfecto. He creado src/middleware/auth-middleware.ts copiando la lógica de auth-middleware.js. Próximos pasos: 1) Añadir tipos para Request/Response, 2) Tipar el payload del JWT, 3) Migrar los tests..."}]', 1761491460000),
  ('m1', '20260426_7', 'user',      '[{"type":"text","text":"Los tests de CI están fallando intermitentemente. ¿Puedes investigar qué tests son flaky?"}]', 1761479000000),
  ('m1', '20260425_4', 'user',      '[{"type":"text","text":"Necesito configurar nginx como reverse proxy para los servicios de backend"}]', 1761399000000);
