-- Forge .forge.db schema (extracted from Forge local install).
-- Augmented with sample rows for fixture-based testing.

CREATE TABLE conversations (
    conversation_id TEXT PRIMARY KEY NOT NULL,
    title TEXT,
    workspace_id BIGINT NOT NULL,
    context TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    metrics TEXT
);

INSERT INTO conversations (conversation_id, title, workspace_id, context, created_at, updated_at) VALUES
  ('conv-fixture-001', 'first forge fixture',  1, '<current_working_directory>/tmp/prune-test</current_working_directory><message role="user">hola forge fixture 1</message><message role="assistant">respuesta forge 1</message>', '2026-01-01 10:00:00', '2026-01-01 10:05:00'),
  ('conv-fixture-002', 'second forge fixture', 1, '<current_working_directory>/tmp/prune-test</current_working_directory><message role="user">forge dos</message>',                                                                                  '2026-02-01 12:00:00', '2026-02-01 12:30:00'),
  ('conv-fixture-003', NULL,                   1, '<current_working_directory>/home/fake/project</current_working_directory><message role="user">forge tres untitled</message>',                                                                  '2026-03-01 14:00:00', '2026-03-01 14:15:00'),
  ('conv-fixture-orphan', 'orphan no context', 1, NULL,                                                                                                                                                                                            '2026-03-15 09:00:00', NULL);
