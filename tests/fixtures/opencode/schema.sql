-- opencode opencode.db schema (extracted from opencode v1.14).
-- Augmented with sample rows.
-- Note: real opencode has FK ON DELETE CASCADE. We replicate the FK so the
-- adapter's `opencode session delete` semantics (cascade messages) hold here.

PRAGMA foreign_keys = ON;

CREATE TABLE project (
    id text PRIMARY KEY,
    worktree text NOT NULL,
    vcs text,
    name text,
    time_created integer NOT NULL,
    time_updated integer NOT NULL
);

CREATE TABLE session (
    id text PRIMARY KEY,
    project_id text NOT NULL,
    parent_id text,
    slug text NOT NULL DEFAULT '',
    directory text NOT NULL,
    title text NOT NULL,
    version text NOT NULL DEFAULT '',
    time_created integer NOT NULL,
    time_updated integer NOT NULL,
    time_archived integer,
    CONSTRAINT fk_session_project FOREIGN KEY (project_id) REFERENCES project(id) ON DELETE CASCADE
);

CREATE TABLE message (
    id text PRIMARY KEY,
    session_id text NOT NULL,
    time_created integer NOT NULL,
    time_updated integer NOT NULL,
    data text NOT NULL,
    CONSTRAINT fk_message_session FOREIGN KEY (session_id) REFERENCES session(id) ON DELETE CASCADE
);

CREATE TABLE part (
    id text PRIMARY KEY,
    message_id text NOT NULL,
    session_id text NOT NULL,
    time_created integer NOT NULL,
    time_updated integer NOT NULL,
    data text NOT NULL,
    CONSTRAINT fk_part_message FOREIGN KEY (message_id) REFERENCES message(id) ON DELETE CASCADE
);

INSERT INTO project (id, worktree, name, time_created, time_updated) VALUES
  ('global',           '/',                            NULL,         1735689600000, 1740960000000),
  ('proj_fakeprojabc', '/home/fake/project',           'fakeproj',   1735689600000, 1740960000000);

INSERT INTO session (id, project_id, slug, directory, title, time_created, time_updated) VALUES
  ('ses_fixture00000000000000001', 'global',           'first',  '/tmp/prune-test',    'first opencode fixture',  1735689600000, 1735689700000),
  ('ses_fixture00000000000000002', 'global',           'second', '/tmp/prune-test',    'second opencode fixture', 1738411200000, 1738411500000),
  ('ses_fixture00000000000000003', 'proj_fakeprojabc', 'third',  '/home/fake/project', 'third opencode fixture',  1740855600000, 1740855700000);

INSERT INTO message (id, session_id, time_created, time_updated, data) VALUES
  ('msg_fix1_user', 'ses_fixture00000000000000001', 1735689601000, 1735689601000, '{"role":"user"}'),
  ('msg_fix1_asst', 'ses_fixture00000000000000001', 1735689602000, 1735689602000, '{"role":"assistant"}'),
  ('msg_fix2_user', 'ses_fixture00000000000000002', 1738411201000, 1738411201000, '{"role":"user"}'),
  ('msg_fix3_user', 'ses_fixture00000000000000003', 1740855601000, 1740855601000, '{"role":"user"}');

INSERT INTO part (id, message_id, session_id, time_created, time_updated, data) VALUES
  ('prt_fix1_u', 'msg_fix1_user', 'ses_fixture00000000000000001', 1735689601000, 1735689601000, '{"type":"text","text":"hola opencode fixture 1"}'),
  ('prt_fix1_a', 'msg_fix1_asst', 'ses_fixture00000000000000001', 1735689602000, 1735689602000, '{"type":"text","text":"respuesta opencode 1"}'),
  ('prt_fix2_u', 'msg_fix2_user', 'ses_fixture00000000000000002', 1738411201000, 1738411201000, '{"type":"text","text":"sesión opencode dos"}'),
  ('prt_fix3_u', 'msg_fix3_user', 'ses_fixture00000000000000003', 1740855601000, 1740855601000, '{"type":"text","text":"sesión opencode tres"}');
