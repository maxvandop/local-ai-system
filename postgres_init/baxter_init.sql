-- =============================================================================
-- Baxter v2 — Complete Database Initialisation
-- File: baxter_init.sql
--
-- Covers all tables required by the Baxter workflow stack:
--   1. n8n_chat_histories      — short-term rolling memory (n8n Postgres memory node)
--   2. message_history         — structured conversation log
--   3. baxter_memory_tracker   — Qdrant ingestion bookmark (DailyHistorySummarizer)
--   4. user_profile            — soul, personality, onboarding state
--   5. projects                — top-level project containers
--   6. tasks                   — individual tasks linked to projects
--   7. subtasks                — child items of tasks
--   8. reminders               — time-based alerts (ReminderHeartbeat)
--   9. news_sources            — curated RSS feed list
--  10. news_items              — fetched and parsed news articles
--
-- SAFE TO RE-RUN — every statement uses IF NOT EXISTS or OR REPLACE.
-- No data is ever dropped or truncated.
--
-- Usage
-- ─────
-- Fresh install (automatic):
--   Place this file in postgres_init/ — Postgres runs it on first container boot.
--
-- Existing install (manual):
--   docker exec -i postgres psql -U $POSTGRES_USER -d $POSTGRES_DB < postgres_init/baxter_init.sql
--
-- pgAdmin:
--   Open Query Tool against the n8n database, paste contents, press F5.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- =============================================================================
-- 1. N8N CHAT HISTORIES
--    Written automatically by the n8n Postgres Chat Memory node.
--    Defined here so indexes exist from first use.
-- =============================================================================

CREATE TABLE IF NOT EXISTS n8n_chat_histories (
    id          SERIAL        PRIMARY KEY,
    session_id  VARCHAR(255)  NOT NULL,
    message     JSONB         NOT NULL,
    created_at  TIMESTAMPTZ   DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS n8n_chat_histories_session_idx
    ON n8n_chat_histories (session_id);

CREATE INDEX IF NOT EXISTS n8n_chat_histories_created_idx
    ON n8n_chat_histories (created_at DESC);


-- =============================================================================
-- 2. MESSAGE HISTORY
--    Structured log of every user<>Baxter exchange.
--    Written by the Orchestrator after each agent call.
--    Read by DailyHistorySummarizer for Qdrant ingestion.
-- =============================================================================

CREATE TABLE IF NOT EXISTS message_history (
    id             SERIAL        PRIMARY KEY,
    channel_id     BIGINT        NOT NULL,
    message_id     BIGINT,                       -- Telegram message ID (null for non-Telegram)
    input_type     VARCHAR(50),                  -- 'text' | 'voice' | 'chat'
    user_input     TEXT,
    agent_response TEXT,
    created_at     TIMESTAMPTZ   DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS message_history_channel_idx
    ON message_history (channel_id);

CREATE INDEX IF NOT EXISTS message_history_created_idx
    ON message_history (created_at DESC);


-- =============================================================================
-- 3. BAXTER MEMORY TRACKER
--    Single-row bookmark used by DailyHistorySummarizer.
--    Stores the highest message_history.id already summarised and pushed to
--    Qdrant (baxter_memory collection), so each run only processes new rows.
--
--    Schema matches existing table exactly:
--      id               SERIAL PK
--      last_ingested_id INTEGER
--      last_run         TIMESTAMP (without time zone)
-- =============================================================================

CREATE TABLE IF NOT EXISTS baxter_memory_tracker (
    id                SERIAL     PRIMARY KEY,
    last_ingested_id  INTEGER    NOT NULL DEFAULT 0,
    last_run          TIMESTAMP                      -- intentionally without time zone
);

-- Seed the single tracking row if the table is empty (no-op on re-runs).
INSERT INTO baxter_memory_tracker (last_ingested_id, last_run)
SELECT 0, NULL
WHERE NOT EXISTS (SELECT 1 FROM baxter_memory_tracker);


-- =============================================================================
-- 4. USER PROFILE  (Soul & Personality)
--    Fetched before every agent call to build the dynamic system prompt.
--    Updated by Baxter via the UpdateProfile tool as the user shares info.
--    onboarding_step: 1-3 = setup in progress | 0 = complete
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_profile (
    channel_id       BIGINT       PRIMARY KEY,
    soul             TEXT,
    user_profile     TEXT,
    preferences      TEXT,
    current_focus    TEXT,
    onboarding_step  INTEGER      NOT NULL DEFAULT 1,
    created_at       TIMESTAMPTZ  DEFAULT NOW(),
    updated_at       TIMESTAMPTZ  DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- Optional: seed your profile manually to skip the in-chat onboarding flow.
-- Uncomment, fill in your values, then re-run this file.
-- ---------------------------------------------------------------------------
-- INSERT INTO user_profile
--     (channel_id, soul, user_profile, preferences, current_focus, onboarding_step)
-- VALUES (
--     8497733638,
--     'Baxter — sharp, witty and brutally honest — a critical thinking companion...',
--     'Max, based in Rotterdam, Netherlands...',
--     'Concise and direct, English only',
--     '',
--     0
-- )
-- ON CONFLICT (channel_id) DO NOTHING;


-- =============================================================================
-- 5. PROJECTS
--    Top-level containers for related tasks.
-- =============================================================================

CREATE TABLE IF NOT EXISTS projects (
    id           SERIAL        PRIMARY KEY,
    channel_id   BIGINT        NOT NULL,
    name         VARCHAR(255)  NOT NULL,
    description  TEXT,
    status       VARCHAR(50)   NOT NULL DEFAULT 'active',  -- 'active' | 'on_hold' | 'completed'
    due_date     DATE,
    created_at   TIMESTAMPTZ   DEFAULT NOW(),
    updated_at   TIMESTAMPTZ   DEFAULT NOW(),

    CONSTRAINT projects_channel_name_uq UNIQUE (channel_id, name)
);

CREATE INDEX IF NOT EXISTS projects_channel_idx  ON projects (channel_id);
CREATE INDEX IF NOT EXISTS projects_status_idx   ON projects (status);


-- =============================================================================
-- 6. TASKS
--    Linked optionally to a project.
--    priority: 'low' | 'medium' | 'high' | 'critical'
-- =============================================================================

CREATE TABLE IF NOT EXISTS tasks (
    id          SERIAL        PRIMARY KEY,
    channel_id  BIGINT        NOT NULL,
    project_id  INTEGER       REFERENCES projects (id) ON DELETE SET NULL,
    title       VARCHAR(500)  NOT NULL,
    details     TEXT,
    category    VARCHAR(100),
    priority    VARCHAR(20)   NOT NULL DEFAULT 'medium',
    due_date    DATE,
    completed   BOOLEAN       NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ   DEFAULT NOW(),
    updated_at  TIMESTAMPTZ   DEFAULT NOW(),

    CONSTRAINT tasks_channel_title_uq UNIQUE (channel_id, title)
);

CREATE INDEX IF NOT EXISTS tasks_channel_idx    ON tasks (channel_id);
CREATE INDEX IF NOT EXISTS tasks_project_idx    ON tasks (project_id);
CREATE INDEX IF NOT EXISTS tasks_due_date_idx   ON tasks (due_date ASC NULLS LAST);
CREATE INDEX IF NOT EXISTS tasks_completed_idx  ON tasks (completed);


-- =============================================================================
-- 7. SUBTASKS
--    Child items belonging to a task.
--    Cascade-deleted automatically when the parent task is removed.
-- =============================================================================

CREATE TABLE IF NOT EXISTS subtasks (
    id          SERIAL        PRIMARY KEY,
    task_id     INTEGER       NOT NULL REFERENCES tasks (id) ON DELETE CASCADE,
    title       VARCHAR(500)  NOT NULL,
    completed   BOOLEAN       NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ   DEFAULT NOW(),

    CONSTRAINT subtasks_task_title_uq UNIQUE (task_id, title)
);

CREATE INDEX IF NOT EXISTS subtasks_task_idx ON subtasks (task_id);


-- =============================================================================
-- 8. REMINDERS
--    Polled every minute by ReminderHeartbeat.
--    Can be standalone or linked to a task and/or subtask.
-- =============================================================================

CREATE TABLE IF NOT EXISTS reminders (
    id          SERIAL       PRIMARY KEY,
    channel_id  BIGINT       NOT NULL,
    task_id     INTEGER      REFERENCES tasks    (id) ON DELETE SET NULL,
    subtask_id  INTEGER      REFERENCES subtasks (id) ON DELETE SET NULL,
    remind_at   TIMESTAMPTZ  NOT NULL,
    message     TEXT,
    sent        BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ  DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS reminders_channel_idx   ON reminders (channel_id);

-- Partial index: only unsent reminders — keeps the heartbeat query fast.
CREATE INDEX IF NOT EXISTS reminders_unsent_idx
    ON reminders (remind_at ASC)
    WHERE sent = FALSE;


-- =============================================================================
-- UPDATED_AT TRIGGER
--    Automatically stamps updated_at on any UPDATE row.
--    Applied to tables that have the column: projects, tasks, user_profile.
-- =============================================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_projects_updated_at     ON projects;
DROP TRIGGER IF EXISTS trg_tasks_updated_at        ON tasks;
DROP TRIGGER IF EXISTS trg_user_profile_updated_at ON user_profile;

CREATE TRIGGER trg_projects_updated_at
    BEFORE UPDATE ON projects
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_tasks_updated_at
    BEFORE UPDATE ON tasks
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_user_profile_updated_at
    BEFORE UPDATE ON user_profile
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- =============================================================================
-- 9. NEWS SOURCES
--    Managed in pgAdmin — add, disable or categorise sources without touching
--    any workflow. The NewsDigest workflow reads active sources each run.
--    categories: technology | local | world
-- =============================================================================

CREATE TABLE IF NOT EXISTS news_sources (
    id          SERIAL        PRIMARY KEY,
    name        VARCHAR(255)  NOT NULL,
    feed_url    TEXT          NOT NULL UNIQUE,
    category    VARCHAR(100)  NOT NULL DEFAULT 'general',
    active      BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ   DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS news_sources_active_idx   ON news_sources (active);
CREATE INDEX IF NOT EXISTS news_sources_category_idx ON news_sources (category);

-- Seed active sources — safe to re-run (ON CONFLICT updates name and active flag).
INSERT INTO news_sources (name, feed_url, category, active) VALUES
    ('Hacker News',    'https://hnrss.org/frontpage',                    'technology', TRUE),
    ('MIT Tech Review','https://www.technologyreview.com/feed/',          'technology', TRUE),
    ('The Verge',      'https://www.theverge.com/rss/index.xml',         'technology', TRUE),
    ('NOS Nieuws',     'https://feeds.nos.nl/nosnieuwsalgemeen',          'local',      TRUE),
    ('RTV Rijnmond',   'https://www.rijnmond.nl/rss/nieuws',             'local',      TRUE),
    ('BBC World',      'https://feeds.bbci.co.uk/news/world/rss.xml',    'world',      TRUE)
ON CONFLICT (feed_url) DO UPDATE SET
    name   = EXCLUDED.name,
    active = EXCLUDED.active;


-- =============================================================================
-- 10. NEWS ITEMS
--     Fetched and parsed by NewsDigest. Cleaned up after 30 days.
--     ingested_to_qdrant tracks which items have been embedded into Qdrant
--     (news_knowledge collection) for semantic retrieval.
-- =============================================================================

CREATE TABLE IF NOT EXISTS news_items (
    id                  SERIAL        PRIMARY KEY,
    source_id           INTEGER       NOT NULL REFERENCES news_sources (id) ON DELETE CASCADE,
    title               VARCHAR(500)  NOT NULL,
    summary             TEXT,
    url                 TEXT          UNIQUE,
    published_at        TIMESTAMPTZ   DEFAULT NOW(),
    ingested_to_qdrant  BOOLEAN       NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ   DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS news_items_source_idx    ON news_items (source_id);
CREATE INDEX IF NOT EXISTS news_items_published_idx ON news_items (published_at DESC);
CREATE INDEX IF NOT EXISTS news_items_unindexed_idx ON news_items (ingested_to_qdrant)
    WHERE ingested_to_qdrant = FALSE;


-- =============================================================================
-- 11. AGENT TASKS
--     Structured task registry for the agent orchestration system.
--     Replaces tasks + subtasks over time.
--     Also replaces the former agent_jobs table — agent_jobs is NOT defined
--     here and should not be created. Background work is now routed through
--     agent_tasks (type='task', status='pending') and picked up by JobRunner.
--
--     type:    'orchestrator' (delegates to subtasks) | 'task' (does the work)
--     status:  pending → in_progress → awaiting_approval → completed | failed
--
--     Self-referencing FKs use DEFERRABLE INITIALLY DEFERRED so that sibling
--     links (previous_task_id / next_task_id) can be inserted in any order.
-- =============================================================================

CREATE TABLE IF NOT EXISTS agent_tasks (
    id                UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
    name              VARCHAR(500)  NOT NULL,
    type              VARCHAR(20)   NOT NULL DEFAULT 'task',
    status            VARCHAR(30)   NOT NULL DEFAULT 'pending',
    agent             VARCHAR(100),

    -- Relationships
    project_id        INTEGER       REFERENCES projects (id) ON DELETE SET NULL,
    parent_task_id    UUID          REFERENCES agent_tasks (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    previous_task_id  UUID          REFERENCES agent_tasks (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    next_task_id      UUID          REFERENCES agent_tasks (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    depends_on        JSONB         NOT NULL DEFAULT '[]',   -- array of UUIDs
    subtasks          JSONB         NOT NULL DEFAULT '[]',   -- array of UUIDs (orchestrator only)

    -- Approval
    requires_approval BOOLEAN       NOT NULL DEFAULT FALSE,

    -- Prompts
    prompts           JSONB         NOT NULL DEFAULT '{}',   -- {user, core, context}
    context_file      TEXT,

    -- Output
    result            JSONB,
    response          TEXT,

    -- Origin / metadata
    input_type        VARCHAR(50),                           -- 'text' | 'voice' | 'chat' | 'scheduled' | 'webhook'
    channel_id        BIGINT,                                -- Telegram channel_id
    message_id        BIGINT,                                -- Telegram message_id

    -- Timestamps
    created_at        TIMESTAMPTZ   DEFAULT NOW(),
    updated_at        TIMESTAMPTZ   DEFAULT NOW(),

    CONSTRAINT agent_tasks_type_check   CHECK (type   IN ('orchestrator', 'task')),
    CONSTRAINT agent_tasks_status_check CHECK (status IN ('pending', 'in_progress', 'awaiting_approval', 'completed', 'failed'))
);

CREATE INDEX IF NOT EXISTS agent_tasks_status_idx      ON agent_tasks (status);
CREATE INDEX IF NOT EXISTS agent_tasks_parent_idx      ON agent_tasks (parent_task_id);
CREATE INDEX IF NOT EXISTS agent_tasks_project_idx     ON agent_tasks (project_id);
CREATE INDEX IF NOT EXISTS agent_tasks_channel_idx     ON agent_tasks (channel_id);
CREATE INDEX IF NOT EXISTS agent_tasks_pending_idx     ON agent_tasks (created_at ASC) WHERE status = 'pending';

DROP TRIGGER IF EXISTS trg_agent_tasks_updated_at ON agent_tasks;

CREATE TRIGGER trg_agent_tasks_updated_at
    BEFORE UPDATE ON agent_tasks
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- =============================================================================
-- VERIFICATION
--    Returns one row per table with its column count.
--    All 11 tables should appear.
-- =============================================================================

SELECT
    t.table_name,
    COUNT(c.column_name) AS columns
FROM information_schema.tables t
JOIN information_schema.columns c
    ON  c.table_name   = t.table_name
    AND c.table_schema = 'public'
WHERE t.table_schema = 'public'
  AND t.table_type   = 'BASE TABLE'
  AND t.table_name IN (
      'n8n_chat_histories',
      'message_history',
      'baxter_memory_tracker',
      'user_profile',
      'projects',
      'tasks',
      'subtasks',
      'reminders',
      'news_sources',
      'news_items',
      'agent_tasks'
  )
GROUP BY t.table_name
ORDER BY t.table_name;
