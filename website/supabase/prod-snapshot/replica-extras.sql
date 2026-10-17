-- replica-extras.sql: objects production (xlseqwgyjuqhktrguhyc) has that no file in this repository creates.
-- Applied by website/scripts/db/build-replica.sh, one "-- @section <name>" at a time, at the point website/scripts/db/manifest.txt
-- names (production's migration order). Never apply this file to production: it only rebuilds what production already has.
--
-- Where each section comes from (all read-only extraction, 17 Oct 2026):
--   * Sections named after a production migration (w2_*, w3_*, w3b_*, m33f_*_runid_window, m33f_*_prune, spark_b46_*) are
--     the exact SQL production recorded for that migration in supabase_migrations.schema_migrations.statements (each
--     section's md5 equals md5(array_to_string(statements, E'\n')) on production). A section starting "-- @skip" is
--     recorded but not run (a data-only migration).
--   * n8n_internal, backup_tables, witty_backup_20261007, b2b_tmp_transfer: reconstructed from production's pg_catalog (tables and
--     functions created by hand or by n8n, outside any migration; schema only, no rows).
--   * catalog_drift: functions whose production body differs from the repository's only in comments or line endings
--     (the 15 Oct connector chunks dropped comment lines; some baseline functions were saved from Windows with CRLF).
--     Each body here is the repository body made byte-identical to production's (md5 of prosrc checked); behaviour is unchanged.

-- @section n8n_internal
-- n8n's own tables in public (the Witty workflows' n8n instance keeps its database here), reconstructed from production's
-- catalog on 17 Oct 2026: 109 tables, their sequences, constraints, indexes, the workflow_version_increment trigger. Schema only.
-- n8n migrates these itself on every n8n upgrade (its table public.migrations), so this snapshot ages with n8n's version;
-- re-extract it (see website/docs/discovery/replica.md) when the fingerprint shows public drifting only in these tables.
-- Never write to them from the website. CHECK constraints and partial indexes over varchar columns are written in n8n's
-- original "col IN (...)" form: re-parsing pg_get_constraintdef's text would store a different (equivalent) expression.

create sequence if not exists public.auth_provider_sync_history_id_seq as integer;
create sequence if not exists public.execution_annotations_id_seq as integer;
create sequence if not exists public.execution_entity_id_seq as integer;
create sequence if not exists public.execution_metadata_temp_id_seq as integer;
create sequence if not exists public.instance_version_history_id_seq as integer;
create sequence if not exists public.migrations_id_seq as integer;
create sequence if not exists public.workflow_statistics_id_seq as integer;

create table public.agent_chat_subscriptions ("agentId" character varying(36) not null, "integrationType" character varying(64) not null, "credentialId" character varying(255) not null, "threadId" character varying(255) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.agent_checkpoints ("runId" character varying(255) not null, "agentId" character varying(255), state text, expired boolean not null default false, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.agent_execution (id character varying(36) not null, "threadId" character varying(128) not null, status character varying(16) not null, "startedAt" timestamp(3) with time zone, "stoppedAt" timestamp(3) with time zone, duration integer not null default 0, "userMessage" text not null, "assistantResponse" text not null, model character varying(255), "promptTokens" integer, "completionTokens" integer, "totalTokens" integer, cost double precision, "toolCalls" json, timeline json, error text, "hitlStatus" character varying(16), source character varying(32), "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.agent_execution_threads (id character varying(128) not null, "agentId" character varying(36) not null, "agentName" character varying(255) not null, "projectId" character varying(255) not null, "sessionNumber" integer not null default 0, "totalPromptTokens" integer not null default 0, "totalCompletionTokens" integer not null default 0, "totalCost" double precision not null default 0, "totalDuration" integer not null default 0, title character varying(255), emoji character varying(8), "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "taskId" character varying(32), "taskVersionId" character varying(36), "parentThreadId" character varying(128), "parentAgentId" character varying(36));
create table public.agent_files (id character varying(16) not null, "agentId" character varying(36) not null, "binaryDataId" text not null, "fileName" character varying(255) not null, "mimeType" character varying(255) not null, "fileSizeBytes" integer not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.agent_history ("versionId" character varying(36) not null, "agentId" character varying(36) not null, schema json, tools json, skills json, "publishedById" uuid, author character varying(255) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.agent_task_definition (id character varying(32) not null, "agentId" character varying(36) not null, name character varying(128) not null, objective text not null, "cronExpression" character varying(128) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.agent_task_run_lock ("agentId" character varying(36) not null, "taskId" character varying(32) not null, "holderId" uuid not null, "heldUntil" timestamp(3) with time zone not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.agent_task_snapshot ("versionId" character varying(36) not null, "taskId" character varying(32) not null, enabled boolean not null, name character varying(128) not null, objective text not null, "cronExpression" character varying(128) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.agents (id character varying(36) not null, name character varying(128) not null, description character varying(512), "projectId" character varying(255) not null, integrations json not null default '[]'::json, schema json, tools json not null default '{}'::json, skills json not null default '{}'::json, "versionId" character varying(36), "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "activeVersionId" character varying(36));
create table public.agents_memory_entries (id character varying(36) not null, "agentId" character varying(36) not null, "resourceId" character varying(255) not null, content text not null, "contentHash" character varying(64) not null, status character varying(16) not null, "supersededBy" character varying(36), "embeddingModel" character varying(128), embedding json, metadata json, "lastSeenAt" timestamp(3) with time zone not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.agents_memory_entry_cursors ("agentId" character varying(36) not null, "observationScopeId" character varying(255) not null, "lastIndexedObservationId" character varying(36) not null, "lastIndexedObservationCreatedAt" timestamp(3) with time zone not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.agents_memory_entry_locks ("agentId" character varying(36) not null, "resourceId" character varying(255) not null, "holderId" character varying(64) not null, "heldUntil" timestamp(3) with time zone not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.agents_memory_entry_sources (id character varying(36) not null, "agentId" character varying(36) not null, "memoryEntryId" character varying(36) not null, "observationId" character varying(36) not null, "threadId" character varying(255) not null, "evidenceHash" character varying(64) not null, "evidenceText" text not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.agents_messages (id character varying(36) not null, "threadId" character varying(255) not null, "resourceId" character varying(255) not null, role character varying(36) not null, type character varying(36), content json not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.agents_observation_cursors ("agentId" character varying(36) not null, "observationScopeId" character varying(255) not null, "lastObservedMessageId" character varying(36) not null, "lastObservedAt" timestamp(3) with time zone not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.agents_observation_locks ("agentId" character varying(36) not null, "observationScopeId" character varying(255) not null, "taskKind" character varying(20) not null, "holderId" character varying(64) not null, "heldUntil" timestamp(3) with time zone not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.agents_observations (id character varying(36) not null, "agentId" character varying(36) not null, "observationScopeId" character varying(255) not null, marker character varying(16) not null, text text not null, "parentId" character varying(36), "tokenCount" integer not null default 0, status character varying(16) not null, "supersededBy" character varying(36), "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.agents_resources (id character varying(255) not null, metadata text, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.agents_threads (id character varying(128) not null, "resourceId" character varying(255) not null, title character varying(255), metadata text, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.ai_builder_temporary_workflow ("workflowId" character varying(36) not null, "threadId" uuid not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.annotation_tag_entity (id character varying(16) not null, name character varying(24) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.auth_identity ("userId" uuid, "providerId" character varying(255) not null, "providerType" character varying(32) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.auth_provider_sync_history (id integer not null default nextval('auth_provider_sync_history_id_seq'::regclass), "providerType" character varying(32) not null, "runMode" text not null, status text not null, "startedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP, "endedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP, scanned integer not null, created integer not null, updated integer not null, disabled integer not null, error text);
create table public.binary_data ("fileId" uuid not null, "sourceType" character varying(50) not null, "sourceId" character varying(255) not null, data bytea not null, "mimeType" character varying(255), "fileName" character varying(255), "fileSize" integer not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.chat_hub_agent_tools ("agentId" uuid not null, "toolId" uuid not null);
create table public.chat_hub_agents (id uuid not null, name character varying(256) not null, description character varying(512), "systemPrompt" text not null, "ownerId" uuid not null, "credentialId" character varying(36), provider character varying(16) not null, model character varying(64) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), icon json, files json not null default '[]'::json, "suggestedPrompts" json not null default '[]'::json);
create table public.chat_hub_messages (id uuid not null, "sessionId" uuid not null, "previousMessageId" uuid, "revisionOfMessageId" uuid, "retryOfMessageId" uuid, type character varying(16) not null, name character varying(128) not null, content text not null, provider character varying(16), model character varying(256), "workflowId" character varying(36), "executionId" integer, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "agentId" uuid, status character varying(16) not null default 'success'::character varying, attachments json);
create table public.chat_hub_session_tools ("sessionId" uuid not null, "toolId" uuid not null);
create table public.chat_hub_sessions (id uuid not null, title character varying(256) not null, "ownerId" uuid not null, "lastMessageAt" timestamp(3) with time zone not null, "credentialId" character varying(36), provider character varying(16), model character varying(256), "workflowId" character varying(36), "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "agentId" uuid, "agentName" character varying(128), type character varying(16) not null default 'production'::character varying);
create table public.chat_hub_tools (id uuid not null, name character varying(255) not null, type character varying(255) not null, "typeVersion" double precision not null, "ownerId" uuid not null, definition json not null, enabled boolean not null default true, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.credential_dependency (id integer generated by default as identity, "credentialId" character varying(36) not null, "dependencyType" character varying(64) not null, "dependencyId" character varying(255) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.credentials_entity (name character varying(128) not null, data text not null, type character varying(128) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), id character varying(36) not null, "isManaged" boolean not null default false, "isGlobal" boolean not null default false, "isResolvable" boolean not null default false, "resolvableAllowFallback" boolean not null default false, "resolverId" character varying(16));
create table public.data_table (id character varying(36) not null, name character varying(128) not null, "projectId" character varying(36) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.data_table_column (id character varying(36) not null, name character varying(128) not null, type character varying(32) not null, index integer not null, "dataTableId" character varying(36) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.deployment_key (id character varying(36) not null, type character varying(64) not null, value text not null, algorithm character varying(20), status character varying(20) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.dynamic_credential_entry (credential_id character varying(16) not null, subject_id character varying(2048) not null, resolver_id character varying(16) not null, data text not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.dynamic_credential_resolver (id character varying(16) not null, name character varying(128) not null, type character varying(128) not null, config text not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.dynamic_credential_user_entry ("credentialId" character varying(16) not null, "userId" uuid not null, "resolverId" character varying(16) not null, data text not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.evaluation_collection (id character varying(36) not null, name character varying(128) not null, description text, "workflowId" character varying(36) not null, "evaluationConfigId" character varying(36) not null, "createdById" uuid, "insightsCache" json, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.evaluation_config (id character varying(36) not null, "workflowId" character varying(36) not null, name character varying(128) not null, status character varying(16) not null default 'valid'::character varying, "invalidReason" character varying(64), "datasetSource" character varying(32) not null, "datasetRef" json not null, "startNodeName" character varying(255) not null, "endNodeName" character varying(255) not null, metrics json not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.event_destinations (id uuid not null, destination jsonb not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.execution_annotation_tags ("annotationId" integer not null, "tagId" character varying(24) not null);
create table public.execution_annotations (id integer not null default nextval('execution_annotations_id_seq'::regclass), "executionId" integer not null, vote character varying(6), note text, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.execution_data ("executionId" integer not null, "workflowData" json not null, data text not null, "workflowVersionId" character varying(36));
create table public.execution_entity (id integer not null default nextval('execution_entity_id_seq'::regclass), finished boolean not null, mode character varying not null, "retryOf" character varying, "retrySuccessId" character varying, "startedAt" timestamp(3) with time zone, "stoppedAt" timestamp(3) with time zone, "waitTill" timestamp(3) with time zone, status character varying not null, "workflowId" character varying(36) not null, "deletedAt" timestamp(3) with time zone, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "storedAt" character varying(2) not null default 'db'::character varying, "tracingContext" json, "deduplicationKey" character varying(255), "jsonSizeBytes" bigint not null default 0, "workflowVersionId" character varying(36) default NULL::character varying);
create table public.execution_metadata (id integer not null default nextval('execution_metadata_temp_id_seq'::regclass), "executionId" integer not null, key character varying(255) not null, value text not null);
create table public.folder (id character varying(36) not null, name character varying(128) not null, "parentFolderId" character varying(36), "projectId" character varying(36) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.folder_tag ("folderId" character varying(36) not null, "tagId" character varying(36) not null);
create table public.insights_by_period (id integer generated by default as identity, "metaId" integer not null, type integer not null, value bigint not null, "periodUnit" integer not null, "periodStart" timestamp(0) with time zone default CURRENT_TIMESTAMP);
create table public.insights_metadata ("metaId" integer generated by default as identity, "workflowId" character varying(36), "projectId" character varying(36), "workflowName" character varying(128) not null, "projectName" character varying(255) not null);
create table public.insights_raw (id integer generated by default as identity, "metaId" integer not null, type integer not null, value bigint not null, "timestamp" timestamp(0) with time zone not null default CURRENT_TIMESTAMP);
create table public.installed_nodes (name character varying(200) not null, type character varying(200) not null, "latestVersion" integer not null default 1, package character varying(241) not null);
create table public.installed_packages ("packageName" character varying(214) not null, "installedVersion" character varying(50) not null, "authorName" character varying(70), "authorEmail" character varying(70), "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.instance_ai_checkpoints (key character varying(255) not null, "runId" character varying(255), "threadId" uuid not null, "resourceId" character varying(255), state json, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "expiredAt" timestamp(3) with time zone);
create table public.instance_ai_iteration_logs (id character varying(36) not null, "threadId" uuid not null, "taskKey" character varying not null, entry text not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.instance_ai_mcp_registry_connections (id uuid not null, "credentialId" character varying(36) not null, "serverSlug" character varying(255) not null, "toolFilter" json, "userId" uuid not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.instance_ai_messages (id character varying(36) not null, "threadId" uuid not null, content text not null, role character varying(16) not null, type character varying(32), "resourceId" character varying(255), "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.instance_ai_observation_cursors ("observationScopeId" uuid not null, "lastObservedMessageId" character varying(36) not null, "lastObservedAt" timestamp(3) with time zone not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.instance_ai_observation_locks ("observationScopeId" uuid not null, "taskKind" character varying(20) not null, "holderId" character varying(64) not null, "heldUntil" timestamp(3) with time zone not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.instance_ai_observational_memory (id character varying(36) not null, "lookupKey" character varying(255) not null, scope character varying(16) not null, "threadId" uuid, "resourceId" character varying(255) not null, "activeObservations" text not null default ''::text, "originType" character varying(32) not null, config text not null, "generationCount" integer not null default 0, "lastObservedAt" timestamp(3) with time zone, "pendingMessageTokens" integer not null default 0, "totalTokensObserved" integer not null default 0, "observationTokenCount" integer not null default 0, "isObserving" boolean not null default false, "isReflecting" boolean not null default false, "observedMessageIds" json, "observedTimezone" character varying, "bufferedObservations" text, "bufferedObservationTokens" integer, "bufferedMessageIds" json, "bufferedReflection" text, "bufferedReflectionTokens" integer, "bufferedReflectionInputTokens" integer, "reflectedObservationLineCount" integer, "bufferedObservationChunks" json, "isBufferingObservation" boolean not null default false, "isBufferingReflection" boolean not null default false, "lastBufferedAtTokens" integer not null default 0, "lastBufferedAtTime" timestamp(3) with time zone, metadata json, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.instance_ai_observations (id character varying(36) not null, "observationScopeId" uuid not null, marker character varying(16) not null, text text not null, "parentId" character varying(36), "tokenCount" integer not null default 0, status character varying(16) not null, "supersededBy" character varying(36), "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.instance_ai_pending_confirmations ("requestId" character varying(36) not null, "threadId" uuid not null, "userId" uuid not null, kind character varying(16) not null, "runId" character varying(36) not null, "toolCallId" character varying(64), "messageGroupId" character varying(36), "checkpointKey" character varying(255), "checkpointTaskId" character varying(36), "expiresAt" timestamp(3) with time zone, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.instance_ai_resources (id character varying(255) not null, "workingMemory" text, metadata json, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.instance_ai_run_snapshots ("threadId" uuid not null, "runId" character varying(36) not null, "messageGroupId" character varying(36), "runIds" json, tree text not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "langsmithRunId" character varying(36), "langsmithTraceId" character varying(36), "traceId" character varying(64), "spanId" character varying(64));
create table public.instance_ai_threads (id uuid not null, "resourceId" character varying(255) not null, title text not null default ''::text, metadata json, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "projectId" character varying(36) not null);
create table public.instance_ai_workflow_snapshots ("runId" character varying(36) not null, "workflowName" character varying(255) not null, "resourceId" character varying(255), status character varying, snapshot text not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.instance_version_history (id integer not null default nextval('instance_version_history_id_seq'::regclass), major integer not null, minor integer not null, patch integer not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.invalid_auth_token (token character varying(512) not null, "expiresAt" timestamp(3) with time zone not null);
create table public.mcp_registry_server (slug character varying(255) not null, status character varying(50) not null, version character varying(50) not null, "registryUpdatedAt" timestamp(3) without time zone not null, data json not null default '{}'::json, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.migrations (id integer not null default nextval('migrations_id_seq'::regclass), "timestamp" bigint not null, name character varying not null);
create table public.oauth_access_tokens (token character varying not null, "clientId" character varying not null, "userId" uuid not null);
create table public.oauth_authorization_codes (code character varying(255) not null, "clientId" character varying not null, "userId" uuid not null, "redirectUri" character varying not null, "codeChallenge" character varying not null, "codeChallengeMethod" character varying(255) not null, "expiresAt" bigint not null, state character varying, used boolean not null default false, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), resource character varying, scope json not null default '["tool:listWorkflows","tool:getWorkflowDetails"]'::json);
create table public.oauth_clients (id character varying not null, name character varying(255) not null, "redirectUris" json not null, "grantTypes" json not null, "clientSecret" character varying(255), "clientSecretExpiresAt" bigint, "tokenEndpointAuthMethod" character varying(255) not null default 'none'::character varying, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.oauth_refresh_tokens (token character varying(255) not null, "clientId" character varying not null, "userId" uuid not null, "expiresAt" bigint not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), scope json not null default '["tool:listWorkflows","tool:getWorkflowDetails"]'::json);
create table public.oauth_user_consents (id integer generated by default as identity, "userId" uuid not null, "clientId" character varying not null, "grantedAt" bigint not null);
create table public.processed_data ("workflowId" character varying(36) not null, context character varying(255) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), value text not null);
create table public.project (id character varying(36) not null, name character varying(255) not null, type character varying(36) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), icon json, description character varying(512), "creatorId" uuid, "customTelemetryTags" json not null default '[]'::json);
create table public.project_relation ("projectId" character varying(36) not null, "userId" uuid not null, role character varying not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.project_secrets_provider_access ("secretsProviderConnectionId" integer not null, "projectId" character varying(36) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), role character varying(128) not null default 'secretsProviderConnection:user'::character varying);
create table public.role (slug character varying(128) not null, "displayName" text, description text, "roleType" text, "systemRole" boolean not null default false, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.role_mapping_rule (id character varying(16) not null, expression text not null, role character varying(128) not null, type character varying(64) not null, "order" integer not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.role_mapping_rule_project ("roleMappingRuleId" character varying(16) not null, "projectId" character varying(36) not null);
create table public.role_scope ("roleSlug" character varying(128) not null, "scopeSlug" character varying(128) not null);
create table public.scope (slug character varying(128) not null, "displayName" text, description text);
create table public.secrets_provider_connection (id integer generated by default as identity, "providerKey" character varying(128) not null, type character varying(36) not null, "encryptedSettings" text not null, "isEnabled" boolean not null default false, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.settings (key character varying(255) not null, value text not null, "loadOnStartup" boolean not null default false);
create table public.shared_credentials ("credentialsId" character varying(36) not null, "projectId" character varying(36) not null, role text not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.shared_workflow ("workflowId" character varying(36) not null, "projectId" character varying(36) not null, role text not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.tag_entity (name character varying(24) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), id character varying(36) not null);
create table public.test_case_execution (id character varying(36) not null, "testRunId" character varying(36) not null, "executionId" integer, status character varying not null, "runAt" timestamp(3) with time zone, "completedAt" timestamp(3) with time zone, "errorCode" character varying, "errorDetails" json, metrics json, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), inputs json, outputs json, "runIndex" integer);
create table public.test_run (id character varying(36) not null, "workflowId" character varying(36) not null, status character varying not null, "errorCode" character varying, "errorDetails" json, "runAt" timestamp(3) with time zone, "completedAt" timestamp(3) with time zone, metrics json, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "runningInstanceId" character varying(255), "cancelRequested" boolean not null default false, "workflowVersionId" character varying(36), "evaluationConfigId" character varying(36), "evaluationConfigSnapshot" jsonb, "collectionId" character varying(36));
create table public.token_exchange_jti (jti character varying(255) not null, "expiresAt" timestamp(3) with time zone not null, "createdAt" timestamp(3) with time zone not null);
create table public.trusted_key ("sourceId" character varying(36) not null, kid character varying(255) not null, data text not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.trusted_key_source (id character varying(36) not null, type character varying(32) not null, config text not null, status character varying(32) not null default 'pending'::character varying, "lastError" text, "lastRefreshedAt" timestamp(3) with time zone, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public."user" (id uuid not null default gen_random_uuid(), email character varying(255), "firstName" character varying(32), "lastName" character varying(32), password character varying(255), "personalizationAnswers" json, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), settings json, disabled boolean not null default false, "mfaEnabled" boolean not null default false, "mfaSecret" text, "mfaRecoveryCodes" text, "lastActiveAt" date, "roleSlug" character varying(128) not null default 'global:member'::character varying);
create table public.user_api_keys (id character varying(36) not null, "userId" uuid not null, label character varying(100) not null, "apiKey" character varying not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), scopes json, audience character varying not null default 'public-api'::character varying, "lastUsedAt" timestamp(3) with time zone);
create table public.user_favorites (id integer generated by default as identity, "userId" uuid not null, "resourceId" character varying(255) not null, "resourceType" character varying(64) not null);
create table public.variables (key character varying(50) not null, type character varying(50) not null default 'string'::character varying, value text, id character varying(36) not null, "projectId" character varying(36));
create table public.webhook_entity ("webhookPath" character varying not null, method character varying not null, node character varying not null, "webhookId" character varying, "pathLength" integer, "workflowId" character varying(36) not null);
create table public.workflow_builder_session (id uuid not null, "workflowId" character varying(36) not null, "userId" uuid not null, messages json not null default '[]'::json, "previousSummary" text, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "activeVersionCardId" character varying(255), "resumeAfterRestoreMessageId" character varying(255));
create table public.workflow_dependency (id integer generated by default as identity, "workflowId" character varying(36) not null, "workflowVersionId" integer not null, "dependencyType" character varying(32) not null, "dependencyKey" character varying(255) not null, "dependencyInfo" json, "indexVersionId" smallint not null default 1, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "publishedVersionId" character varying(36));
create table public.workflow_entity (name character varying(128) not null, active boolean not null, nodes json not null, connections json not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), settings json, "staticData" json, "pinData" json, "versionId" character(36) not null, "triggerCount" integer not null default 0, id character varying(36) not null, meta json, "parentFolderId" character varying(36) default NULL::character varying, "isArchived" boolean not null default false, "versionCounter" integer not null default 1, description text, "activeVersionId" character varying(36), "nodeGroups" json not null default '[]'::json, "sourceWorkflowId" character varying);
create table public.workflow_history ("versionId" character varying(36) not null, "workflowId" character varying(36) not null, authors character varying(255) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), nodes json not null, connections json not null, name character varying(128), autosaved boolean not null default false, description text, "nodeGroups" json not null default '[]'::json);
create table public.workflow_publication_outbox (id integer generated by default as identity, "workflowId" character varying(36) not null, "publishedVersionId" character varying(36) not null, status character varying(20) not null, "errorMessage" text, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.workflow_publish_history (id integer generated by default as identity, "workflowId" character varying(36) not null, "versionId" character varying(36), event character varying(36) not null, "userId" uuid, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.workflow_published_version ("workflowId" character varying(36) not null, "publishedVersionId" character varying(36) not null, "createdAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3), "updatedAt" timestamp(3) with time zone not null default CURRENT_TIMESTAMP(3));
create table public.workflow_statistics (count bigint default 0, "latestEvent" timestamp(3) with time zone, name character varying(128) not null, "workflowId" character varying(36) not null, "rootCount" bigint default 0, id integer not null default nextval('workflow_statistics_id_seq'::regclass), "workflowName" character varying(128));
create table public.workflows_tags ("workflowId" character varying(36) not null, "tagId" character varying(36) not null);

alter sequence public.auth_provider_sync_history_id_seq owned by public.auth_provider_sync_history.id;
alter sequence public.execution_annotations_id_seq owned by public.execution_annotations.id;
alter sequence public.execution_entity_id_seq owned by public.execution_entity.id;
alter sequence public.execution_metadata_temp_id_seq owned by public.execution_metadata.id;
alter sequence public.instance_version_history_id_seq owned by public.instance_version_history.id;
alter sequence public.migrations_id_seq owned by public.migrations.id;
alter sequence public.workflow_statistics_id_seq owned by public.workflow_statistics.id;

alter table public.agent_chat_subscriptions add constraint "CHK_agent_chat_subscriptions_integrationType" CHECK ((("integrationType") IN ('telegram', 'slack', 'linear')));
alter table public.agent_chat_subscriptions add constraint "PK_76598cf91038bee1f3ac94c94bc" PRIMARY KEY ("agentId", "integrationType", "credentialId", "threadId");
alter table public.agent_checkpoints add constraint "PK_50a27cbafa6806c9b162304b5fd" PRIMARY KEY ("runId");
alter table public.agent_execution add constraint "CHK_agent_execution_hitlStatus" CHECK ((("hitlStatus") IN ('suspended', 'resumed')));
alter table public.agent_execution add constraint "CHK_agent_execution_status" CHECK (((status) IN ('success', 'error')));
alter table public.agent_execution add constraint "PK_ba438acc8532addc12d1ef17049" PRIMARY KEY (id);
alter table public.agent_execution_threads add constraint "PK_22373dbf6ba6929d8ac50093309" PRIMARY KEY (id);
alter table public.agent_files add constraint "PK_692920e59217af7d124cd95106f" PRIMARY KEY (id);
alter table public.agent_history add constraint "PK_65ffcfe7a8e112fb826311fb092" PRIMARY KEY ("versionId");
alter table public.agent_task_definition add constraint "PK_1756c11c637903e97629a7a784a" PRIMARY KEY (id);
alter table public.agent_task_run_lock add constraint "PK_f593adaf7230e964d3c25deda64" PRIMARY KEY ("agentId", "taskId");
alter table public.agent_task_snapshot add constraint "PK_2142a8bcda2360c3c5e34f82640" PRIMARY KEY ("versionId", "taskId");
alter table public.agents add constraint "PK_9c653f28ae19c5884d5baf6a1d9" PRIMARY KEY (id);
alter table public.agents_memory_entries add constraint "CHK_agents_memory_entries_status" CHECK (((status) IN ('active', 'superseded', 'dropped')));
alter table public.agents_memory_entries add constraint "PK_bfbc45dc88f66fae4e4b4a15fec" PRIMARY KEY (id);
alter table public.agents_memory_entry_cursors add constraint "PK_b31a1d5c009a27f4cc5ef8f102a" PRIMARY KEY ("agentId", "observationScopeId");
alter table public.agents_memory_entry_locks add constraint "PK_a8e0f570d04a174292bea104ae6" PRIMARY KEY ("agentId", "resourceId");
alter table public.agents_memory_entry_sources add constraint "PK_278f05e98e74baaaa93f52b4bab" PRIMARY KEY (id);
alter table public.agents_messages add constraint "PK_81020dc608dfb0af1ede386d907" PRIMARY KEY (id);
alter table public.agents_observation_cursors add constraint "PK_eb777ac57ab872d38f8ebd19317" PRIMARY KEY ("agentId", "observationScopeId");
alter table public.agents_observation_locks add constraint "CHK_agents_observation_locks_taskKind" CHECK ((("taskKind") IN ('observer', 'reflector')));
alter table public.agents_observation_locks add constraint "PK_7e2e315162ac3d80587e15ac2c3" PRIMARY KEY ("agentId", "observationScopeId", "taskKind");
alter table public.agents_observations add constraint "CHK_agents_observations_marker" CHECK (((marker) IN ('critical', 'important', 'info', 'completion')));
alter table public.agents_observations add constraint "CHK_agents_observations_status" CHECK (((status) IN ('active', 'superseded', 'dropped')));
alter table public.agents_observations add constraint "PK_9ad319654d12c2649f7caf27135" PRIMARY KEY (id);
alter table public.agents_resources add constraint "PK_fa6b20b2d31a9991529dbf8ef7d" PRIMARY KEY (id);
alter table public.agents_threads add constraint "PK_4a3feb0a13ffe315c009cce64e5" PRIMARY KEY (id);
alter table public.ai_builder_temporary_workflow add constraint "PK_85a87a1ba0f61999fe11dc56325" PRIMARY KEY ("workflowId");
alter table public.annotation_tag_entity add constraint "PK_69dfa041592c30bbc0d4b84aa00" PRIMARY KEY (id);
alter table public.auth_identity add constraint auth_identity_pkey PRIMARY KEY ("providerId", "providerType");
alter table public.auth_provider_sync_history add constraint auth_provider_sync_history_pkey PRIMARY KEY (id);
alter table public.binary_data add constraint "CHK_binary_data_sourceType" CHECK ((("sourceType") IN ('execution', 'chat_message_attachment', 'agent_file')));
alter table public.binary_data add constraint "PK_fc3691585b39408bb0551122af6" PRIMARY KEY ("fileId");
alter table public.chat_hub_agent_tools add constraint "PK_cc8806fdea48297a7d497035d72" PRIMARY KEY ("agentId", "toolId");
alter table public.chat_hub_agents add constraint "PK_f39a3b36bbdf0e2979ddb21cf78" PRIMARY KEY (id);
alter table public.chat_hub_messages add constraint "PK_7704a5add6baed43eef835f0bfb" PRIMARY KEY (id);
alter table public.chat_hub_session_tools add constraint "PK_87aea76ff4c274c4a5ac838ebe3" PRIMARY KEY ("sessionId", "toolId");
alter table public.chat_hub_sessions add constraint "CHK_chat_hub_sessions_type" CHECK (((type) IN ('production', 'manual')));
alter table public.chat_hub_sessions add constraint "PK_1eafef1273c70e4464fec703412" PRIMARY KEY (id);
alter table public.chat_hub_tools add constraint "PK_696d26426c704fba79b2c195ef5" PRIMARY KEY (id);
alter table public.credential_dependency add constraint "PK_80212729ed0ffa0709417ab28f4" PRIMARY KEY (id);
alter table public.credentials_entity add constraint credentials_entity_pkey PRIMARY KEY (id);
alter table public.data_table add constraint "PK_e226d0001b9e6097cbfe70617cb" PRIMARY KEY (id);
alter table public.data_table add constraint "UQ_b23096ef747281ac944d28e8b0d" UNIQUE ("projectId", name);
alter table public.data_table_column add constraint "PK_673cb121ee4a8a5e27850c72c51" PRIMARY KEY (id);
alter table public.data_table_column add constraint "UQ_8082ec4890f892f0bc77473a123" UNIQUE ("dataTableId", name);
alter table public.deployment_key add constraint "PK_94bb7aeb5def5a0284a5fe9f9a0" PRIMARY KEY (id);
alter table public.dynamic_credential_entry add constraint "PK_5135ffcabecad4727ff6b9b803d" PRIMARY KEY (credential_id, subject_id, resolver_id);
alter table public.dynamic_credential_resolver add constraint "PK_b76cfb088dcdaf5275e9980bb64" PRIMARY KEY (id);
alter table public.dynamic_credential_user_entry add constraint "PK_74f548e633abc66dc27c8f0ca77" PRIMARY KEY ("credentialId", "userId", "resolverId");
alter table public.evaluation_collection add constraint "PK_e720b6efc1e45b878ebb0b2ca30" PRIMARY KEY (id);
alter table public.evaluation_config add constraint "PK_59c14dccf8989df94070c2dcfda" PRIMARY KEY (id);
alter table public.evaluation_config add constraint "UQ_3c3c99a712e971835c52292e44c" UNIQUE ("workflowId", name);
alter table public.event_destinations add constraint event_destinations_pkey PRIMARY KEY (id);
alter table public.execution_annotation_tags add constraint "PK_979ec03d31294cca484be65d11f" PRIMARY KEY ("annotationId", "tagId");
alter table public.execution_annotations add constraint "PK_7afcf93ffa20c4252869a7c6a23" PRIMARY KEY (id);
alter table public.execution_data add constraint execution_data_pkey PRIMARY KEY ("executionId");
alter table public.execution_entity add constraint "execution_entity_storedAt_check" CHECK ((("storedAt") IN ('db', 'fs', 's3')));
alter table public.execution_entity add constraint pk_e3e63bbf986767844bbe1166d4e PRIMARY KEY (id);
alter table public.execution_metadata add constraint "PK_17a0b6284f8d626aae88e1c16e4" PRIMARY KEY (id);
alter table public.folder add constraint "PK_6278a41a706740c94c02e288df8" PRIMARY KEY (id);
alter table public.folder_tag add constraint "PK_27e4e00852f6b06a925a4d83a3e" PRIMARY KEY ("folderId", "tagId");
alter table public.insights_by_period add constraint "PK_b606942249b90cc39b0265f0575" PRIMARY KEY (id);
alter table public.insights_metadata add constraint "PK_f448a94c35218b6208ce20cf5a1" PRIMARY KEY ("metaId");
alter table public.insights_raw add constraint "PK_ec15125755151e3a7e00e00014f" PRIMARY KEY (id);
alter table public.installed_nodes add constraint "PK_8ebd28194e4f792f96b5933423fc439df97d9689" PRIMARY KEY (name);
alter table public.installed_packages add constraint "PK_08cc9197c39b028c1e9beca225940576fd1a5804" PRIMARY KEY ("packageName");
alter table public.instance_ai_checkpoints add constraint "PK_5315a45f0846d1f9d128c18a2ed" PRIMARY KEY (key);
alter table public.instance_ai_checkpoints add constraint instance_ai_checkpoints_state_tombstone_check CHECK (((("expiredAt" IS NOT NULL) AND (state IS NULL)) OR ("expiredAt" IS NULL)));
alter table public.instance_ai_iteration_logs add constraint "PK_21c2b214b44bc6c34a6d3551c90" PRIMARY KEY (id);
alter table public.instance_ai_mcp_registry_connections add constraint "PK_e34e4d15d78eabbe8217e33ef03" PRIMARY KEY (id);
alter table public.instance_ai_messages add constraint "PK_156c6f287225e9befe0181bb02b" PRIMARY KEY (id);
alter table public.instance_ai_observation_cursors add constraint "PK_5b6319b2e9a37c1064a72428f9a" PRIMARY KEY ("observationScopeId");
alter table public.instance_ai_observation_locks add constraint "CHK_instance_ai_observation_locks_taskKind" CHECK ((("taskKind") IN ('observer', 'reflector')));
alter table public.instance_ai_observation_locks add constraint "PK_fc491dd378b9448655c3c683f85" PRIMARY KEY ("observationScopeId", "taskKind");
alter table public.instance_ai_observational_memory add constraint "PK_7192dd00cddba039bf1d3e6a098" PRIMARY KEY (id);
alter table public.instance_ai_observations add constraint "CHK_instance_ai_observations_marker" CHECK (((marker) IN ('critical', 'important', 'info', 'completion')));
alter table public.instance_ai_observations add constraint "CHK_instance_ai_observations_status" CHECK (((status) IN ('active', 'superseded', 'dropped')));
alter table public.instance_ai_observations add constraint "PK_4d9b514cdf0f0b577650caf2ac2" PRIMARY KEY (id);
alter table public.instance_ai_pending_confirmations add constraint "CHK_instance_ai_pending_confirmations_kind" CHECK (((kind) IN ('suspended', 'inline')));
alter table public.instance_ai_pending_confirmations add constraint "PK_25c38179c8d45095b168adfff80" PRIMARY KEY ("requestId");
alter table public.instance_ai_resources add constraint "PK_45b5b0b6f715dae4292b86603d8" PRIMARY KEY (id);
alter table public.instance_ai_run_snapshots add constraint "PK_0a5fc9690a84950ebf1416fb146" PRIMARY KEY ("threadId", "runId");
alter table public.instance_ai_threads add constraint "PK_35575100e45cdedeb89ae0643e9" PRIMARY KEY (id);
alter table public.instance_ai_workflow_snapshots add constraint "PK_93f2696eb321dfe1d7defe7073f" PRIMARY KEY ("runId", "workflowName");
alter table public.instance_version_history add constraint "PK_874f58cb616935bf49d9dbd67e9" PRIMARY KEY (id);
alter table public.invalid_auth_token add constraint "PK_5779069b7235b256d91f7af1a15" PRIMARY KEY (token);
alter table public.mcp_registry_server add constraint "CHK_tmp_mcp_registry_server_status" CHECK (((status) IN ('active', 'deprecated')));
alter table public.mcp_registry_server add constraint "PK_12fd89a1fb8489513b0a91f5d31" PRIMARY KEY (slug);
alter table public.migrations add constraint "PK_8c82d7f526340ab734260ea46be" PRIMARY KEY (id);
alter table public.oauth_access_tokens add constraint "PK_dcd71f96a5d5f4bf79e67d322bf" PRIMARY KEY (token);
alter table public.oauth_authorization_codes add constraint "PK_fb91ab932cfbd694061501cc20f" PRIMARY KEY (code);
alter table public.oauth_clients add constraint "PK_c4759172d3431bae6f04e678e0d" PRIMARY KEY (id);
alter table public.oauth_refresh_tokens add constraint "PK_74abaed0b30711b6532598b0392" PRIMARY KEY (token);
alter table public.oauth_user_consents add constraint "PK_85b9ada746802c8993103470f05" PRIMARY KEY (id);
alter table public.oauth_user_consents add constraint "UQ_083721d99ce8db4033e2958ebb4" UNIQUE ("userId", "clientId");
alter table public.processed_data add constraint "PK_ca04b9d8dc72de268fe07a65773" PRIMARY KEY ("workflowId", context);
alter table public.project add constraint "PK_4d68b1358bb5b766d3e78f32f57" PRIMARY KEY (id);
alter table public.project_relation add constraint "PK_1caaa312a5d7184a003be0f0cb6" PRIMARY KEY ("projectId", "userId");
alter table public.project_secrets_provider_access add constraint "CHK_project_secrets_provider_access_role" CHECK (((role) IN ('secretsProviderConnection:owner', 'secretsProviderConnection:user')));
alter table public.project_secrets_provider_access add constraint "PK_0402b7fcec5415246656f102f83" PRIMARY KEY ("secretsProviderConnectionId", "projectId");
alter table public.role add constraint "PK_35c9b140caaf6da09cfabb0d675" PRIMARY KEY (slug);
alter table public.role_mapping_rule add constraint "PK_d772c8ec1a89b52d31c882bc560" PRIMARY KEY (id);
alter table public.role_mapping_rule add constraint "UQ_b33ac896ad3099fc8de36fdc1c4" UNIQUE (type, "order");
alter table public.role_mapping_rule_project add constraint "PK_198c5b5aea509d139274efcaf9a" PRIMARY KEY ("roleMappingRuleId", "projectId");
alter table public.role_scope add constraint "PK_role_scope" PRIMARY KEY ("roleSlug", "scopeSlug");
alter table public.scope add constraint "PK_bfc45df0481abd7f355d6187da1" PRIMARY KEY (slug);
alter table public.secrets_provider_connection add constraint "PK_4350ae85e76f9ba7df1370acb5d" PRIMARY KEY (id);
alter table public.settings add constraint "PK_dc0fe14e6d9943f268e7b119f69ab8bd" PRIMARY KEY (key);
alter table public.shared_credentials add constraint "PK_8ef3a59796a228913f251779cff" PRIMARY KEY ("credentialsId", "projectId");
alter table public.shared_workflow add constraint "PK_5ba87620386b847201c9531c58f" PRIMARY KEY ("workflowId", "projectId");
alter table public.tag_entity add constraint tag_entity_pkey PRIMARY KEY (id);
alter table public.test_case_execution add constraint "PK_90c121f77a78a6580e94b794bce" PRIMARY KEY (id);
alter table public.test_run add constraint "PK_011c050f566e9db509a0fadb9b9" PRIMARY KEY (id);
alter table public.token_exchange_jti add constraint "PK_d8e8a6f737d530fdd2dd716e89c" PRIMARY KEY (jti);
alter table public.trusted_key add constraint "PK_dc7d93798f3dbb6959f974c97e1" PRIMARY KEY ("sourceId", kid);
alter table public.trusted_key_source add constraint "PK_99e8908ce2c2cdccce487db7fc6" PRIMARY KEY (id);
alter table public."user" add constraint "PK_ea8f538c94b6e352418254ed6474a81f" PRIMARY KEY (id);
alter table public."user" add constraint "UQ_e12875dfb3b1d92d7d7c5377e2" UNIQUE (email);
alter table public.user_api_keys add constraint "PK_978fa5caa3468f463dac9d92e69" PRIMARY KEY (id);
alter table public.user_favorites add constraint "PK_6c472a19a7423cfbbf6b7c75939" PRIMARY KEY (id);
alter table public.user_favorites add constraint "UQ_cf6ae658ead9ffc124723413c65" UNIQUE ("userId", "resourceId", "resourceType");
alter table public.variables add constraint variables_pkey PRIMARY KEY (id);
alter table public.variables add constraint variables_value_max_len CHECK (((value IS NULL) OR (char_length(value) <= 1000)));
alter table public.webhook_entity add constraint "PK_b21ace2e13596ccd87dc9bf4ea6" PRIMARY KEY ("webhookPath", method);
alter table public.workflow_builder_session add constraint "PK_e69ef0d385986e273423b0e8695" PRIMARY KEY (id);
alter table public.workflow_builder_session add constraint "UQ_ec2aa73632932d485a1d5192ce1" UNIQUE ("workflowId", "userId");
alter table public.workflow_dependency add constraint "PK_52325e34cd7a2f0f67b0f3cad65" PRIMARY KEY (id);
alter table public.workflow_entity add constraint workflow_entity_pkey PRIMARY KEY (id);
alter table public.workflow_history add constraint "PK_b6572dd6173e4cd06fe79937b58" PRIMARY KEY ("versionId");
alter table public.workflow_publication_outbox add constraint "CHK_workflow_publication_outbox_status" CHECK (((status) IN ('pending', 'in_progress', 'completed', 'partial_success', 'failed')));
alter table public.workflow_publication_outbox add constraint "PK_b3e2eeee36a4bd044d56468d311" PRIMARY KEY (id);
alter table public.workflow_publish_history add constraint "CHK_workflow_publish_history_event" CHECK (((event) IN ('activated', 'deactivated')));
alter table public.workflow_publish_history add constraint "PK_c788f7caf88e91e365c97d6d04a" PRIMARY KEY (id);
alter table public.workflow_published_version add constraint "PK_5c76fb7ee939fe2530374d3f75a" PRIMARY KEY ("workflowId");
alter table public.workflow_statistics add constraint workflow_statistics_pkey PRIMARY KEY (id);
alter table public.workflows_tags add constraint pk_workflows_tags PRIMARY KEY ("workflowId", "tagId");
alter table public.agent_chat_subscriptions add constraint "FK_e79153bd179c011e779d5016796" FOREIGN KEY ("agentId") REFERENCES agents(id) ON DELETE CASCADE;
alter table public.agent_checkpoints add constraint "FK_5e31c210f896d539964bf99fe32" FOREIGN KEY ("agentId") REFERENCES agents(id) ON DELETE CASCADE;
alter table public.agent_execution add constraint "FK_add2432fb6034cc18b6af299dce" FOREIGN KEY ("threadId") REFERENCES agent_execution_threads(id) ON DELETE CASCADE;
alter table public.agent_execution_threads add constraint "FK_0468a9dc35597314e641d4722aa" FOREIGN KEY ("agentId") REFERENCES agents(id) ON DELETE CASCADE;
alter table public.agent_execution_threads add constraint "FK_0e2f8bf92a7a9c88b89670f701c" FOREIGN KEY ("projectId") REFERENCES project(id) ON DELETE CASCADE;
alter table public.agent_execution_threads add constraint "FK_f00b52d74fe11838e1fe086deea" FOREIGN KEY ("taskVersionId") REFERENCES agent_history("versionId") ON DELETE SET NULL;
alter table public.agent_files add constraint "FK_aca4514cb500494b64356c2e164" FOREIGN KEY ("agentId") REFERENCES agents(id) ON DELETE CASCADE;
alter table public.agent_history add constraint "FK_8771675f44c58fb40e0feb9ee35" FOREIGN KEY ("publishedById") REFERENCES "user"(id) ON DELETE SET NULL;
alter table public.agent_history add constraint "FK_87cd5a8da20304b089ea2f83fec" FOREIGN KEY ("agentId") REFERENCES agents(id) ON DELETE CASCADE;
alter table public.agent_task_definition add constraint "FK_f45d0535a2ed59b6c2dd6da98a0" FOREIGN KEY ("agentId") REFERENCES agents(id) ON DELETE CASCADE;
alter table public.agent_task_run_lock add constraint "FK_b57a2862ae869aab24e54cefd48" FOREIGN KEY ("agentId") REFERENCES agents(id) ON DELETE CASCADE;
alter table public.agent_task_snapshot add constraint "FK_1acedce6690392ef1611cca8b88" FOREIGN KEY ("versionId") REFERENCES agent_history("versionId") ON DELETE CASCADE;
alter table public.agents add constraint "FK_940597dfe9753375309ce6aeea0" FOREIGN KEY ("activeVersionId") REFERENCES agent_history("versionId") ON DELETE SET NULL;
alter table public.agents add constraint "FK_a30d560207c4071d98aa03c179c" FOREIGN KEY ("projectId") REFERENCES project(id) ON DELETE CASCADE;
alter table public.agents_memory_entries add constraint "FK_0edf1226b77ddc525eae4938079" FOREIGN KEY ("supersededBy") REFERENCES agents_memory_entries(id);
alter table public.agents_memory_entries add constraint "FK_1443a75e59adbfb796071d66393" FOREIGN KEY ("resourceId") REFERENCES agents_resources(id) ON DELETE CASCADE;
alter table public.agents_memory_entries add constraint "FK_28e981fb675e9b44ce02f0ec1dd" FOREIGN KEY ("agentId") REFERENCES agents(id) ON DELETE CASCADE;
alter table public.agents_memory_entry_cursors add constraint "FK_069e791e428391a5569e7a96b20" FOREIGN KEY ("observationScopeId") REFERENCES agents_threads(id) ON DELETE CASCADE;
alter table public.agents_memory_entry_cursors add constraint "FK_746780fd115e5e4352457a3c617" FOREIGN KEY ("agentId") REFERENCES agents(id) ON DELETE CASCADE;
alter table public.agents_memory_entry_locks add constraint "FK_0ccf6d9ea6f44fa1c264fc2f795" FOREIGN KEY ("agentId") REFERENCES agents(id) ON DELETE CASCADE;
alter table public.agents_memory_entry_locks add constraint "FK_9594c0983cfee1c8ff49b05848b" FOREIGN KEY ("resourceId") REFERENCES agents_resources(id) ON DELETE CASCADE;
alter table public.agents_memory_entry_sources add constraint "FK_451d387a182fa8dd8002dfc3a77" FOREIGN KEY ("threadId") REFERENCES agents_threads(id) ON DELETE CASCADE;
alter table public.agents_memory_entry_sources add constraint "FK_4706f6223313959b7437a2b48df" FOREIGN KEY ("memoryEntryId") REFERENCES agents_memory_entries(id) ON DELETE CASCADE;
alter table public.agents_memory_entry_sources add constraint "FK_c38e8a57a36b880e39a52ada2e8" FOREIGN KEY ("agentId") REFERENCES agents(id) ON DELETE CASCADE;
alter table public.agents_memory_entry_sources add constraint "FK_cb7c15d22fd068a0806aa57fc03" FOREIGN KEY ("observationId") REFERENCES agents_observations(id) ON DELETE CASCADE;
alter table public.agents_messages add constraint "FK_0a8057a61afabd2999608ffd0d9" FOREIGN KEY ("threadId") REFERENCES agents_threads(id) ON DELETE CASCADE;
alter table public.agents_observation_cursors add constraint "FK_64e92819f4b413661ed6e2c3c3d" FOREIGN KEY ("agentId") REFERENCES agents(id) ON DELETE CASCADE;
alter table public.agents_observation_cursors add constraint "FK_87aa187d27ea67eafd164905154" FOREIGN KEY ("observationScopeId") REFERENCES agents_threads(id) ON DELETE CASCADE;
alter table public.agents_observation_locks add constraint "FK_093e44ae20f2518e97d83a95433" FOREIGN KEY ("agentId") REFERENCES agents(id) ON DELETE CASCADE;
alter table public.agents_observation_locks add constraint "FK_6b55089892e447c2f82e5ec60ed" FOREIGN KEY ("observationScopeId") REFERENCES agents_threads(id) ON DELETE CASCADE;
alter table public.agents_observations add constraint "FK_127ee1078ffa952bb37b511efad" FOREIGN KEY ("supersededBy") REFERENCES agents_observations(id);
alter table public.agents_observations add constraint "FK_4cfd8a70ebb0a5b0cf047dca3cf" FOREIGN KEY ("observationScopeId") REFERENCES agents_threads(id) ON DELETE CASCADE;
alter table public.agents_observations add constraint "FK_501e2d1701a10e24fb69ab5fc5f" FOREIGN KEY ("parentId") REFERENCES agents_observations(id);
alter table public.agents_observations add constraint "FK_d206432be97b7ed88d187479b1b" FOREIGN KEY ("agentId") REFERENCES agents(id) ON DELETE CASCADE;
alter table public.ai_builder_temporary_workflow add constraint "FK_39b07732e819fb561d74c38763f" FOREIGN KEY ("threadId") REFERENCES instance_ai_threads(id) ON DELETE CASCADE;
alter table public.ai_builder_temporary_workflow add constraint "FK_85a87a1ba0f61999fe11dc56325" FOREIGN KEY ("workflowId") REFERENCES workflow_entity(id) ON DELETE CASCADE;
alter table public.auth_identity add constraint "auth_identity_userId_fkey" FOREIGN KEY ("userId") REFERENCES "user"(id);
alter table public.chat_hub_agent_tools add constraint "FK_2b53d796b3dbae91b1a9553c048" FOREIGN KEY ("agentId") REFERENCES chat_hub_agents(id) ON DELETE CASCADE;
alter table public.chat_hub_agent_tools add constraint "FK_43e70f04c53344f82483d0570f6" FOREIGN KEY ("toolId") REFERENCES chat_hub_tools(id) ON DELETE CASCADE;
alter table public.chat_hub_agents add constraint "FK_441ba2caba11e077ce3fbfa2cd8" FOREIGN KEY ("ownerId") REFERENCES "user"(id) ON DELETE CASCADE;
alter table public.chat_hub_agents add constraint "FK_9c61ad497dcbae499c96a6a78ba" FOREIGN KEY ("credentialId") REFERENCES credentials_entity(id) ON DELETE SET NULL;
alter table public.chat_hub_messages add constraint "FK_1f4998c8a7dec9e00a9ab15550e" FOREIGN KEY ("revisionOfMessageId") REFERENCES chat_hub_messages(id) ON DELETE CASCADE;
alter table public.chat_hub_messages add constraint "FK_25c9736e7f769f3a005eef4b372" FOREIGN KEY ("retryOfMessageId") REFERENCES chat_hub_messages(id) ON DELETE CASCADE;
alter table public.chat_hub_messages add constraint "FK_6afb260449dd7a9b85355d4e0c9" FOREIGN KEY ("executionId") REFERENCES execution_entity(id) ON DELETE SET NULL;
alter table public.chat_hub_messages add constraint "FK_acf8926098f063cdbbad8497fd1" FOREIGN KEY ("workflowId") REFERENCES workflow_entity(id) ON DELETE SET NULL;
alter table public.chat_hub_messages add constraint "FK_chat_hub_messages_agentId" FOREIGN KEY ("agentId") REFERENCES chat_hub_agents(id) ON DELETE SET NULL;
alter table public.chat_hub_messages add constraint "FK_e22538eb50a71a17954cd7e076c" FOREIGN KEY ("sessionId") REFERENCES chat_hub_sessions(id) ON DELETE CASCADE;
alter table public.chat_hub_messages add constraint "FK_e5d1fa722c5a8d38ac204746662" FOREIGN KEY ("previousMessageId") REFERENCES chat_hub_messages(id) ON DELETE CASCADE;
alter table public.chat_hub_session_tools add constraint "FK_6596a328affd8d4967ffb303eee" FOREIGN KEY ("toolId") REFERENCES chat_hub_tools(id) ON DELETE CASCADE;
alter table public.chat_hub_session_tools add constraint "FK_e649bf1295f4ed8d4299ed290f9" FOREIGN KEY ("sessionId") REFERENCES chat_hub_sessions(id) ON DELETE CASCADE;
alter table public.chat_hub_sessions add constraint "FK_7bc13b4c7e6afbfaf9be326c189" FOREIGN KEY ("credentialId") REFERENCES credentials_entity(id) ON DELETE SET NULL;
alter table public.chat_hub_sessions add constraint "FK_9f9293d9f552496c40e0d1a8f80" FOREIGN KEY ("workflowId") REFERENCES workflow_entity(id) ON DELETE SET NULL;
alter table public.chat_hub_sessions add constraint "FK_chat_hub_sessions_agentId" FOREIGN KEY ("agentId") REFERENCES chat_hub_agents(id) ON DELETE SET NULL;
alter table public.chat_hub_sessions add constraint "FK_e9ecf8ede7d989fcd18790fe36a" FOREIGN KEY ("ownerId") REFERENCES "user"(id) ON DELETE CASCADE;
alter table public.chat_hub_tools add constraint "FK_b8030b47af9213f1fd15450fb7f" FOREIGN KEY ("ownerId") REFERENCES "user"(id) ON DELETE CASCADE;
alter table public.credential_dependency add constraint "FK_5ec8e8c8d3539f3696cf73b43bf" FOREIGN KEY ("credentialId") REFERENCES credentials_entity(id) ON DELETE CASCADE;
alter table public.credentials_entity add constraint "credentials_entity_resolverId_foreign" FOREIGN KEY ("resolverId") REFERENCES dynamic_credential_resolver(id) ON DELETE SET NULL;
alter table public.data_table add constraint "FK_c2a794257dee48af7c9abf681de" FOREIGN KEY ("projectId") REFERENCES project(id) ON DELETE CASCADE;
alter table public.data_table_column add constraint "FK_930b6e8faaf88294cef23484160" FOREIGN KEY ("dataTableId") REFERENCES data_table(id) ON DELETE CASCADE;
alter table public.dynamic_credential_entry add constraint "FK_a6d1dd080958304a47a02952aab" FOREIGN KEY (credential_id) REFERENCES credentials_entity(id) ON DELETE CASCADE;
alter table public.dynamic_credential_entry add constraint "FK_d61a12235d268a49af6a3c09c13" FOREIGN KEY (resolver_id) REFERENCES dynamic_credential_resolver(id) ON DELETE CASCADE;
alter table public.dynamic_credential_user_entry add constraint "FK_6edec973a6450990977bb854c38" FOREIGN KEY ("resolverId") REFERENCES dynamic_credential_resolver(id) ON DELETE CASCADE;
alter table public.dynamic_credential_user_entry add constraint "FK_945ba70b342a066d1306b12ccd2" FOREIGN KEY ("credentialId") REFERENCES credentials_entity(id) ON DELETE CASCADE;
alter table public.dynamic_credential_user_entry add constraint "FK_a36dc616fabc3f736bb82410a22" FOREIGN KEY ("userId") REFERENCES "user"(id) ON DELETE CASCADE;
alter table public.evaluation_collection add constraint "FK_a48ce930c3bc7604894b8f0eaad" FOREIGN KEY ("workflowId") REFERENCES workflow_entity(id) ON DELETE CASCADE;
alter table public.evaluation_collection add constraint "FK_d634a0c93fd7de68a87eab951b2" FOREIGN KEY ("evaluationConfigId") REFERENCES evaluation_config(id) ON DELETE CASCADE;
alter table public.evaluation_collection add constraint "FK_f4561f38b5a22a4f090d5cd3eae" FOREIGN KEY ("createdById") REFERENCES "user"(id) ON DELETE SET NULL;
alter table public.evaluation_config add constraint "FK_fd7542bb123074760285dc1bbf3" FOREIGN KEY ("workflowId") REFERENCES workflow_entity(id) ON DELETE CASCADE;
alter table public.execution_annotation_tags add constraint "FK_a3697779b366e131b2bbdae2976" FOREIGN KEY ("tagId") REFERENCES annotation_tag_entity(id) ON DELETE CASCADE;
alter table public.execution_annotation_tags add constraint "FK_c1519757391996eb06064f0e7c8" FOREIGN KEY ("annotationId") REFERENCES execution_annotations(id) ON DELETE CASCADE;
alter table public.execution_annotations add constraint "FK_97f863fa83c4786f19565084960" FOREIGN KEY ("executionId") REFERENCES execution_entity(id) ON DELETE CASCADE;
alter table public.execution_data add constraint execution_data_fk FOREIGN KEY ("executionId") REFERENCES execution_entity(id) ON DELETE CASCADE;
alter table public.execution_entity add constraint fk_execution_entity_workflow_id FOREIGN KEY ("workflowId") REFERENCES workflow_entity(id) ON DELETE CASCADE;
alter table public.execution_metadata add constraint "FK_31d0b4c93fb85ced26f6005cda3" FOREIGN KEY ("executionId") REFERENCES execution_entity(id) ON DELETE CASCADE;
alter table public.folder add constraint "FK_804ea52f6729e3940498bd54d78" FOREIGN KEY ("parentFolderId") REFERENCES folder(id) ON DELETE CASCADE;
alter table public.folder add constraint "FK_a8260b0b36939c6247f385b8221" FOREIGN KEY ("projectId") REFERENCES project(id) ON DELETE CASCADE;
alter table public.folder_tag add constraint "FK_94a60854e06f2897b2e0d39edba" FOREIGN KEY ("folderId") REFERENCES folder(id) ON DELETE CASCADE;
alter table public.folder_tag add constraint "FK_dc88164176283de80af47621746" FOREIGN KEY ("tagId") REFERENCES tag_entity(id) ON DELETE CASCADE;
alter table public.insights_by_period add constraint "FK_6414cfed98daabbfdd61a1cfbc0" FOREIGN KEY ("metaId") REFERENCES insights_metadata("metaId") ON DELETE CASCADE;
alter table public.insights_metadata add constraint "FK_1d8ab99d5861c9388d2dc1cf733" FOREIGN KEY ("workflowId") REFERENCES workflow_entity(id) ON DELETE SET NULL;
alter table public.insights_metadata add constraint "FK_2375a1eda085adb16b24615b69c" FOREIGN KEY ("projectId") REFERENCES project(id) ON DELETE SET NULL;
alter table public.insights_raw add constraint "FK_6e2e33741adef2a7c5d66befa4e" FOREIGN KEY ("metaId") REFERENCES insights_metadata("metaId") ON DELETE CASCADE;
alter table public.installed_nodes add constraint "FK_73f857fc5dce682cef8a99c11dbddbc969618951" FOREIGN KEY (package) REFERENCES installed_packages("packageName") ON UPDATE CASCADE ON DELETE CASCADE;
alter table public.instance_ai_checkpoints add constraint "FK_2b23f3f24a70bebb990203b011e" FOREIGN KEY ("threadId") REFERENCES instance_ai_threads(id) ON DELETE CASCADE;
alter table public.instance_ai_iteration_logs add constraint "FK_8bfcc6c51fd3d69b1eae8aebd49" FOREIGN KEY ("threadId") REFERENCES instance_ai_threads(id) ON DELETE CASCADE;
alter table public.instance_ai_mcp_registry_connections add constraint "FK_1d25707354d2012da256eb2ec0a" FOREIGN KEY ("serverSlug") REFERENCES mcp_registry_server(slug) ON DELETE CASCADE;
alter table public.instance_ai_mcp_registry_connections add constraint "FK_1e826120e7e53ebc4681f026de8" FOREIGN KEY ("credentialId") REFERENCES credentials_entity(id) ON DELETE CASCADE;
alter table public.instance_ai_mcp_registry_connections add constraint "FK_8b42c08a531d76410980c639a5b" FOREIGN KEY ("userId") REFERENCES "user"(id) ON DELETE CASCADE;
alter table public.instance_ai_messages add constraint "FK_1eeb64cb9d66a927988de759e6e" FOREIGN KEY ("threadId") REFERENCES instance_ai_threads(id) ON DELETE CASCADE;
alter table public.instance_ai_observation_cursors add constraint "FK_5b6319b2e9a37c1064a72428f9a" FOREIGN KEY ("observationScopeId") REFERENCES instance_ai_threads(id) ON DELETE CASCADE;
alter table public.instance_ai_observation_locks add constraint "FK_103e2e5f454860b28ea05a82c74" FOREIGN KEY ("observationScopeId") REFERENCES instance_ai_threads(id) ON DELETE CASCADE;
alter table public.instance_ai_observational_memory add constraint "FK_34018c303885cd37093458e6409" FOREIGN KEY ("threadId") REFERENCES instance_ai_threads(id) ON DELETE SET NULL;
alter table public.instance_ai_observations add constraint "FK_a80e0ee839a2f10ba4b86e19998" FOREIGN KEY ("supersededBy") REFERENCES instance_ai_observations(id);
alter table public.instance_ai_observations add constraint "FK_d54fc84a6c8ac91b5e0db0378a4" FOREIGN KEY ("observationScopeId") REFERENCES instance_ai_threads(id) ON DELETE CASCADE;
alter table public.instance_ai_observations add constraint "FK_daef2195a4a846eb70eed15e039" FOREIGN KEY ("parentId") REFERENCES instance_ai_observations(id);
alter table public.instance_ai_pending_confirmations add constraint "FK_0babdf6e3b897a86fe4678355eb" FOREIGN KEY ("checkpointKey") REFERENCES instance_ai_checkpoints(key) ON DELETE CASCADE;
alter table public.instance_ai_pending_confirmations add constraint "FK_ba67ee8dc311830a2eea89b6e96" FOREIGN KEY ("threadId") REFERENCES instance_ai_threads(id) ON DELETE CASCADE;
alter table public.instance_ai_pending_confirmations add constraint "FK_df5fd25c8bbfd2b042602600d8e" FOREIGN KEY ("userId") REFERENCES "user"(id) ON DELETE CASCADE;
alter table public.instance_ai_run_snapshots add constraint "FK_2f63fa21d09d7918f347ddbdf70" FOREIGN KEY ("threadId") REFERENCES instance_ai_threads(id) ON DELETE CASCADE;
alter table public.instance_ai_threads add constraint "FK_instance_ai_threads_projectId" FOREIGN KEY ("projectId") REFERENCES project(id) ON DELETE CASCADE;
alter table public.oauth_access_tokens add constraint "FK_7234a36d8e49a1fa85095328845" FOREIGN KEY ("userId") REFERENCES "user"(id) ON DELETE CASCADE;
alter table public.oauth_access_tokens add constraint "FK_78b26968132b7e5e45b75876481" FOREIGN KEY ("clientId") REFERENCES oauth_clients(id) ON DELETE CASCADE;
alter table public.oauth_authorization_codes add constraint "FK_64d965bd072ea24fb6da55468cd" FOREIGN KEY ("clientId") REFERENCES oauth_clients(id) ON DELETE CASCADE;
alter table public.oauth_authorization_codes add constraint "FK_aa8d3560484944c19bdf79ffa16" FOREIGN KEY ("userId") REFERENCES "user"(id) ON DELETE CASCADE;
alter table public.oauth_refresh_tokens add constraint "FK_a699f3ed9fd0c1b19bc2608ac53" FOREIGN KEY ("userId") REFERENCES "user"(id) ON DELETE CASCADE;
alter table public.oauth_refresh_tokens add constraint "FK_b388696ce4d8be7ffbe8d3e4b69" FOREIGN KEY ("clientId") REFERENCES oauth_clients(id) ON DELETE CASCADE;
alter table public.oauth_user_consents add constraint "FK_21e6c3c2d78a097478fae6aaefa" FOREIGN KEY ("userId") REFERENCES "user"(id) ON DELETE CASCADE;
alter table public.oauth_user_consents add constraint "FK_a651acea2f6c97f8c4514935486" FOREIGN KEY ("clientId") REFERENCES oauth_clients(id) ON DELETE CASCADE;
alter table public.processed_data add constraint "FK_06a69a7032c97a763c2c7599464" FOREIGN KEY ("workflowId") REFERENCES workflow_entity(id) ON DELETE CASCADE;
alter table public.project add constraint "projects_creatorId_foreign" FOREIGN KEY ("creatorId") REFERENCES "user"(id) ON DELETE SET NULL;
alter table public.project_relation add constraint "FK_5f0643f6717905a05164090dde7" FOREIGN KEY ("userId") REFERENCES "user"(id) ON DELETE CASCADE;
alter table public.project_relation add constraint "FK_61448d56d61802b5dfde5cdb002" FOREIGN KEY ("projectId") REFERENCES project(id) ON DELETE CASCADE;
alter table public.project_relation add constraint "FK_c6b99592dc96b0d836d7a21db91" FOREIGN KEY (role) REFERENCES role(slug);
alter table public.project_secrets_provider_access add constraint "FK_18e5c27d2524b1638b292904e48" FOREIGN KEY ("secretsProviderConnectionId") REFERENCES secrets_provider_connection(id) ON DELETE CASCADE;
alter table public.project_secrets_provider_access add constraint "FK_bd264b81209355b543878deedb1" FOREIGN KEY ("projectId") REFERENCES project(id) ON DELETE CASCADE;
alter table public.role_mapping_rule add constraint "FK_bb66e404c35996b0d6946177501" FOREIGN KEY (role) REFERENCES role(slug) ON UPDATE CASCADE ON DELETE CASCADE;
alter table public.role_mapping_rule_project add constraint "FK_35a78869286c65d9330d02b88f5" FOREIGN KEY ("projectId") REFERENCES project(id) ON DELETE CASCADE;
alter table public.role_mapping_rule_project add constraint "FK_dd7ce4dfa09e95b36a626bd9de3" FOREIGN KEY ("roleMappingRuleId") REFERENCES role_mapping_rule(id) ON DELETE CASCADE;
alter table public.role_scope add constraint "FK_role" FOREIGN KEY ("roleSlug") REFERENCES role(slug) ON UPDATE CASCADE ON DELETE CASCADE;
alter table public.role_scope add constraint "FK_scope" FOREIGN KEY ("scopeSlug") REFERENCES scope(slug) ON UPDATE CASCADE ON DELETE CASCADE;
alter table public.shared_credentials add constraint "FK_416f66fc846c7c442970c094ccf" FOREIGN KEY ("credentialsId") REFERENCES credentials_entity(id) ON DELETE CASCADE;
alter table public.shared_credentials add constraint "FK_812c2852270da1247756e77f5a4" FOREIGN KEY ("projectId") REFERENCES project(id) ON DELETE CASCADE;
alter table public.shared_workflow add constraint "FK_a45ea5f27bcfdc21af9b4188560" FOREIGN KEY ("projectId") REFERENCES project(id) ON DELETE CASCADE;
alter table public.shared_workflow add constraint "FK_daa206a04983d47d0a9c34649ce" FOREIGN KEY ("workflowId") REFERENCES workflow_entity(id) ON DELETE CASCADE;
alter table public.test_case_execution add constraint "FK_8e4b4774db42f1e6dda3452b2af" FOREIGN KEY ("testRunId") REFERENCES test_run(id) ON DELETE CASCADE;
alter table public.test_case_execution add constraint "FK_e48965fac35d0f5b9e7f51d8c44" FOREIGN KEY ("executionId") REFERENCES execution_entity(id) ON DELETE SET NULL;
alter table public.test_run add constraint "FK_d6870d3b6e4c185d33926f423c8" FOREIGN KEY ("workflowId") REFERENCES workflow_entity(id) ON DELETE CASCADE;
alter table public.test_run add constraint "FK_test_run_collection_id" FOREIGN KEY ("collectionId") REFERENCES evaluation_collection(id) ON DELETE SET NULL;
alter table public.test_run add constraint "FK_test_run_evaluation_config_id" FOREIGN KEY ("evaluationConfigId") REFERENCES evaluation_config(id) ON DELETE SET NULL;
alter table public.trusted_key add constraint "FK_8c2938d746943dd8f608d23c891" FOREIGN KEY ("sourceId") REFERENCES trusted_key_source(id) ON DELETE CASCADE;
alter table public."user" add constraint "FK_eaea92ee7bfb9c1b6cd01505d56" FOREIGN KEY ("roleSlug") REFERENCES role(slug);
alter table public.user_api_keys add constraint "FK_e131705cbbc8fb589889b02d457" FOREIGN KEY ("userId") REFERENCES "user"(id) ON DELETE CASCADE;
alter table public.user_favorites add constraint "FK_1dd5c393ad0517be3c31a7af836" FOREIGN KEY ("userId") REFERENCES "user"(id) ON DELETE CASCADE;
alter table public.variables add constraint "FK_42f6c766f9f9d2edcc15bdd6e9b" FOREIGN KEY ("projectId") REFERENCES project(id) ON DELETE CASCADE;
alter table public.webhook_entity add constraint fk_webhook_entity_workflow_id FOREIGN KEY ("workflowId") REFERENCES workflow_entity(id) ON DELETE CASCADE;
alter table public.workflow_builder_session add constraint "FK_00290cdeee4d4d7db84709be936" FOREIGN KEY ("userId") REFERENCES "user"(id) ON DELETE CASCADE;
alter table public.workflow_builder_session add constraint "FK_7983c618db48f47bf5a4cc1e1e4" FOREIGN KEY ("workflowId") REFERENCES workflow_entity(id) ON DELETE CASCADE;
alter table public.workflow_dependency add constraint "FK_a4ff2d9b9628ea988fa9e7d0bf8" FOREIGN KEY ("workflowId") REFERENCES workflow_entity(id) ON DELETE CASCADE;
alter table public.workflow_entity add constraint "FK_08d6c67b7f722b0039d9d5ed620" FOREIGN KEY ("activeVersionId") REFERENCES workflow_history("versionId") ON DELETE RESTRICT;
alter table public.workflow_entity add constraint fk_workflow_parent_folder FOREIGN KEY ("parentFolderId") REFERENCES folder(id) ON DELETE CASCADE;
alter table public.workflow_history add constraint "FK_1e31657f5fe46816c34be7c1b4b" FOREIGN KEY ("workflowId") REFERENCES workflow_entity(id) ON DELETE CASCADE;
alter table public.workflow_publish_history add constraint "FK_6eab5bd9eedabe9c54bd879fc40" FOREIGN KEY ("userId") REFERENCES "user"(id) ON DELETE SET NULL;
alter table public.workflow_publish_history add constraint "FK_b4cfbc7556d07f36ca177f5e473" FOREIGN KEY ("versionId") REFERENCES workflow_history("versionId") ON DELETE SET NULL;
alter table public.workflow_publish_history add constraint "FK_c01316f8c2d7101ec4fa9809267" FOREIGN KEY ("workflowId") REFERENCES workflow_entity(id) ON DELETE CASCADE;
alter table public.workflow_published_version add constraint "FK_5c76fb7ee939fe2530374d3f75a" FOREIGN KEY ("workflowId") REFERENCES workflow_entity(id) ON DELETE RESTRICT;
alter table public.workflow_published_version add constraint "FK_df3428a541b802d6a63ac56e330" FOREIGN KEY ("publishedVersionId") REFERENCES workflow_history("versionId") ON DELETE RESTRICT;
alter table public.workflows_tags add constraint fk_workflows_tags_tag_id FOREIGN KEY ("tagId") REFERENCES tag_entity(id) ON DELETE CASCADE;
alter table public.workflows_tags add constraint fk_workflows_tags_workflow_id FOREIGN KEY ("workflowId") REFERENCES workflow_entity(id) ON DELETE CASCADE;
CREATE INDEX "IDX_5e31c210f896d539964bf99fe3" ON public.agent_checkpoints USING btree ("agentId");
CREATE INDEX "IDX_63d3c3a68b9cebf05f967f0b1c" ON public.agent_execution USING btree ("threadId", "createdAt");
CREATE INDEX "IDX_0468a9dc35597314e641d4722a" ON public.agent_execution_threads USING btree ("agentId");
CREATE INDEX "IDX_0e2f8bf92a7a9c88b89670f701" ON public.agent_execution_threads USING btree ("projectId");
CREATE INDEX "IDX_agent_execution_threads_taskVersionId" ON public.agent_execution_threads USING btree ("taskVersionId");
CREATE INDEX "IDX_45dafc48fe2ce95eac30fc8ffd" ON public.agent_files USING btree ("agentId", "createdAt");
CREATE INDEX "IDX_87cd5a8da20304b089ea2f83fe" ON public.agent_history USING btree ("agentId");
CREATE INDEX "IDX_f45d0535a2ed59b6c2dd6da98a" ON public.agent_task_definition USING btree ("agentId");
CREATE INDEX "IDX_a30d560207c4071d98aa03c179" ON public.agents USING btree ("projectId");
CREATE INDEX "IDX_agents_projectId" ON public.agents USING btree ("projectId");
CREATE INDEX "IDX_0edf1226b77ddc525eae493807" ON public.agents_memory_entries USING btree ("supersededBy");
CREATE INDEX "IDX_1443a75e59adbfb796071d6639" ON public.agents_memory_entries USING btree ("resourceId");
CREATE UNIQUE INDEX "IDX_a03e04e94bea8439dd166d4b52" ON public.agents_memory_entries USING btree ("agentId", "resourceId", "contentHash");
CREATE INDEX "IDX_aff2807b31eccbafe59d0474f0" ON public.agents_memory_entries USING btree ("agentId", "resourceId", status, "createdAt", id);
CREATE INDEX "IDX_069e791e428391a5569e7a96b2" ON public.agents_memory_entry_cursors USING btree ("observationScopeId");
CREATE INDEX "IDX_9594c0983cfee1c8ff49b05848" ON public.agents_memory_entry_locks USING btree ("resourceId");
CREATE INDEX "IDX_451d387a182fa8dd8002dfc3a7" ON public.agents_memory_entry_sources USING btree ("threadId");
CREATE UNIQUE INDEX "IDX_a353ac251315ef0af6ad3c9f0a" ON public.agents_memory_entry_sources USING btree ("memoryEntryId", "observationId", "evidenceHash");
CREATE INDEX "IDX_cb7c15d22fd068a0806aa57fc0" ON public.agents_memory_entry_sources USING btree ("observationId");
CREATE INDEX "IDX_f9573af4ed653f13b0ba1f7b12" ON public.agents_memory_entry_sources USING btree ("agentId", "threadId");
CREATE INDEX "IDX_agents_messages_threadId_createdAt" ON public.agents_messages USING btree ("threadId", "createdAt");
CREATE INDEX "IDX_fc7bf858660bfafd19181e8e35" ON public.agents_messages USING btree ("threadId", "createdAt");
CREATE INDEX "IDX_87aa187d27ea67eafd16490515" ON public.agents_observation_cursors USING btree ("observationScopeId");
CREATE INDEX "IDX_6b55089892e447c2f82e5ec60e" ON public.agents_observation_locks USING btree ("observationScopeId");
CREATE INDEX "IDX_07cb1e4a302629c5fa5d74d2bb" ON public.agents_observations USING btree ("agentId", "observationScopeId", status);
CREATE INDEX "IDX_127ee1078ffa952bb37b511efa" ON public.agents_observations USING btree ("supersededBy");
CREATE INDEX "IDX_4cfd8a70ebb0a5b0cf047dca3c" ON public.agents_observations USING btree ("observationScopeId");
CREATE INDEX "IDX_501e2d1701a10e24fb69ab5fc5" ON public.agents_observations USING btree ("parentId");
CREATE INDEX "IDX_54fa1b94f34a409beafae567a4" ON public.agents_threads USING btree ("resourceId");
CREATE INDEX "IDX_39b07732e819fb561d74c38763" ON public.ai_builder_temporary_workflow USING btree ("threadId");
CREATE UNIQUE INDEX "IDX_ae51b54c4bb430cf92f48b623f" ON public.annotation_tag_entity USING btree (name);
CREATE INDEX "IDX_56900edc3cfd16612e2ef2c6a8" ON public.binary_data USING btree ("sourceType", "sourceId");
CREATE INDEX "IDX_chat_hub_messages_sessionId" ON public.chat_hub_messages USING btree ("sessionId");
CREATE INDEX "IDX_chat_hub_sessions_owner_lastmsg_id" ON public.chat_hub_sessions USING btree ("ownerId", "lastMessageAt" DESC, id);
CREATE UNIQUE INDEX "IDX_4c72ebdb265d1775bf61147af0" ON public.chat_hub_tools USING btree ("ownerId", name);
CREATE INDEX "IDX_5ec8e8c8d3539f3696cf73b43b" ON public.credential_dependency USING btree ("credentialId");
CREATE INDEX "IDX_91ee85fa9619dd6776725e117b" ON public.credential_dependency USING btree ("dependencyType", "dependencyId");
CREATE UNIQUE INDEX "IDX_credential_dependency_credentialId_dependencyType_dependenc" ON public.credential_dependency USING btree ("credentialId", "dependencyType", "dependencyId");
CREATE INDEX idx_07fde106c0b471d8cc80a64fc8 ON public.credentials_entity USING btree (type);
CREATE UNIQUE INDEX pk_credentials_entity_id ON public.credentials_entity USING btree (id);
CREATE UNIQUE INDEX "IDX_deployment_key_data_encryption_active" ON public.deployment_key USING btree (type) WHERE (((status)::text = 'active'::text) AND ((type)::text = 'data_encryption'::text));
CREATE UNIQUE INDEX "IDX_deployment_key_instance_id_active" ON public.deployment_key USING btree (type) WHERE (((status)::text = 'active'::text) AND ((type)::text = 'instance.id'::text));
CREATE UNIQUE INDEX "IDX_deployment_key_jwe_private_key_active" ON public.deployment_key USING btree (type, algorithm) WHERE (((status)::text = 'active'::text) AND ((type)::text = 'jwe.private-key'::text));
CREATE UNIQUE INDEX "IDX_deployment_key_signing_binary_data_active" ON public.deployment_key USING btree (type) WHERE (((status)::text = 'active'::text) AND ((type)::text = 'signing.binary_data'::text));
CREATE UNIQUE INDEX "IDX_deployment_key_signing_hmac_active" ON public.deployment_key USING btree (type) WHERE (((status)::text = 'active'::text) AND ((type)::text = 'signing.hmac'::text));
CREATE UNIQUE INDEX "IDX_deployment_key_signing_jwt_active" ON public.deployment_key USING btree (type) WHERE (((status)::text = 'active'::text) AND ((type)::text = 'signing.jwt'::text));
CREATE INDEX "IDX_62476b94b56d9dc7ed9ed75d3d" ON public.dynamic_credential_entry USING btree (subject_id);
CREATE INDEX "IDX_d61a12235d268a49af6a3c09c1" ON public.dynamic_credential_entry USING btree (resolver_id);
CREATE INDEX "IDX_9c9ee9df586e60bb723234e499" ON public.dynamic_credential_resolver USING btree (type);
CREATE INDEX "IDX_6edec973a6450990977bb854c3" ON public.dynamic_credential_user_entry USING btree ("resolverId");
CREATE INDEX "IDX_a36dc616fabc3f736bb82410a2" ON public.dynamic_credential_user_entry USING btree ("userId");
CREATE INDEX "IDX_a48ce930c3bc7604894b8f0eaa" ON public.evaluation_collection USING btree ("workflowId");
CREATE INDEX "IDX_d634a0c93fd7de68a87eab951b" ON public.evaluation_collection USING btree ("evaluationConfigId");
CREATE INDEX "IDX_fd7542bb123074760285dc1bbf" ON public.evaluation_config USING btree ("workflowId");
CREATE INDEX "IDX_a3697779b366e131b2bbdae297" ON public.execution_annotation_tags USING btree ("tagId");
CREATE INDEX "IDX_c1519757391996eb06064f0e7c" ON public.execution_annotation_tags USING btree ("annotationId");
CREATE UNIQUE INDEX "IDX_97f863fa83c4786f1956508496" ON public.execution_annotations USING btree ("executionId");
CREATE UNIQUE INDEX "IDX_execution_entity_deduplicationKey" ON public.execution_entity USING btree ("deduplicationKey") WHERE ("deduplicationKey" IS NOT NULL);
CREATE INDEX "IDX_execution_entity_deletedAt" ON public.execution_entity USING btree ("deletedAt");
CREATE INDEX "IDX_execution_entity_workflowId_status_id" ON public.execution_entity USING btree ("workflowId", status, id) WHERE ("deletedAt" IS NULL);
CREATE INDEX idx_execution_entity_stopped_at_status_deleted_at ON public.execution_entity USING btree ("stoppedAt", status, "deletedAt") WHERE (("stoppedAt" IS NOT NULL) AND ("deletedAt" IS NULL));
CREATE INDEX idx_execution_entity_wait_till_status_deleted_at ON public.execution_entity USING btree ("waitTill", status, "deletedAt") WHERE (("waitTill" IS NOT NULL) AND ("deletedAt" IS NULL));
CREATE INDEX idx_execution_entity_workflow_id_started_at ON public.execution_entity USING btree ("workflowId", "startedAt") WHERE (("startedAt" IS NOT NULL) AND ("deletedAt" IS NULL));
CREATE UNIQUE INDEX "IDX_cec8eea3bf49551482ccb4933e" ON public.execution_metadata USING btree ("executionId", key);
CREATE UNIQUE INDEX "IDX_14f68deffaf858465715995508" ON public.folder USING btree ("projectId", id);
CREATE UNIQUE INDEX "IDX_60b6a84299eeb3f671dfec7693" ON public.insights_by_period USING btree ("periodStart", type, "periodUnit", "metaId");
CREATE UNIQUE INDEX "IDX_1d8ab99d5861c9388d2dc1cf73" ON public.insights_metadata USING btree ("workflowId");
CREATE INDEX "IDX_insights_raw_timestamp_id" ON public.insights_raw USING btree ("timestamp", id);
CREATE INDEX "IDX_2b23f3f24a70bebb990203b011" ON public.instance_ai_checkpoints USING btree ("threadId");
CREATE INDEX "IDX_768189b506cc26c4fe878b87cb" ON public.instance_ai_checkpoints USING btree ("runId");
CREATE INDEX "IDX_be9d0eca0b19fb93d4eb74b327" ON public.instance_ai_checkpoints USING btree ("resourceId");
CREATE INDEX "IDX_02751202c9a2ad75f2d8e14f5e" ON public.instance_ai_iteration_logs USING btree ("threadId", "taskKey", "createdAt");
CREATE UNIQUE INDEX "IDX_16db3adb7b19df1ee55ff06b27" ON public.instance_ai_mcp_registry_connections USING btree ("userId", "serverSlug", "credentialId");
CREATE INDEX "IDX_1eeb64cb9d66a927988de759e6" ON public.instance_ai_messages USING btree ("threadId");
CREATE INDEX "IDX_76e212c6867fbaa06bf0decd6f" ON public.instance_ai_messages USING btree ("resourceId");
CREATE INDEX "IDX_92f13cb6bc694227e069447f7b" ON public.instance_ai_observational_memory USING btree ("lookupKey");
CREATE UNIQUE INDEX "IDX_a680ac96aae02dc887bbaac512" ON public.instance_ai_observational_memory USING btree (scope, "threadId", "resourceId");
CREATE INDEX "IDX_0d5db648188d338df7fb2a8064" ON public.instance_ai_observations USING btree ("observationScopeId", status, "createdAt", id);
CREATE INDEX "IDX_a80e0ee839a2f10ba4b86e1999" ON public.instance_ai_observations USING btree ("supersededBy");
CREATE INDEX "IDX_daef2195a4a846eb70eed15e03" ON public.instance_ai_observations USING btree ("parentId");
CREATE INDEX "IDX_0babdf6e3b897a86fe4678355e" ON public.instance_ai_pending_confirmations USING btree ("checkpointKey");
CREATE INDEX "IDX_ba67ee8dc311830a2eea89b6e9" ON public.instance_ai_pending_confirmations USING btree ("threadId");
CREATE INDEX "IDX_d7a4aba7440449865e2b924377" ON public.instance_ai_pending_confirmations USING btree ("expiresAt");
CREATE INDEX "IDX_df5fd25c8bbfd2b042602600d8" ON public.instance_ai_pending_confirmations USING btree ("userId");
CREATE INDEX "IDX_d3a2bc880e7a8626802e5474ad" ON public.instance_ai_run_snapshots USING btree ("threadId", "createdAt");
CREATE INDEX "IDX_d926c16c2ad9728cb9a81790c0" ON public.instance_ai_run_snapshots USING btree ("threadId", "messageGroupId");
CREATE INDEX "IDX_f36dea4d38fe92e0e8f44d5a56" ON public.instance_ai_threads USING btree ("resourceId");
CREATE INDEX "IDX_instance_ai_threads_projectId" ON public.instance_ai_threads USING btree ("projectId");
CREATE INDEX "IDX_a371ee6b8e0ebb5635f8baa46d" ON public.instance_ai_workflow_snapshots USING btree ("workflowName", status);
CREATE INDEX "IDX_5f0643f6717905a05164090dde" ON public.project_relation USING btree ("userId");
CREATE INDEX "IDX_61448d56d61802b5dfde5cdb00" ON public.project_relation USING btree ("projectId");
CREATE INDEX project_relation_role_idx ON public.project_relation USING btree (role);
CREATE INDEX project_relation_role_project_idx ON public.project_relation USING btree ("projectId", role);
CREATE UNIQUE INDEX "IDX_UniqueRoleDisplayName" ON public.role USING btree ("displayName");
CREATE INDEX "IDX_bb66e404c35996b0d694617750" ON public.role_mapping_rule USING btree (role);
CREATE INDEX "IDX_35a78869286c65d9330d02b88f" ON public.role_mapping_rule_project USING btree ("projectId");
CREATE INDEX "IDX_role_scope_scopeSlug" ON public.role_scope USING btree ("scopeSlug");
CREATE UNIQUE INDEX "IDX_secrets_provider_connection_providerKey" ON public.secrets_provider_connection USING btree ("providerKey");
CREATE INDEX "IDX_shared_workflow_projectId" ON public.shared_workflow USING btree ("projectId");
CREATE UNIQUE INDEX idx_812eb05f7451ca757fb98444ce ON public.tag_entity USING btree (name);
CREATE UNIQUE INDEX pk_tag_entity_id ON public.tag_entity USING btree (id);
CREATE INDEX "IDX_8e4b4774db42f1e6dda3452b2a" ON public.test_case_execution USING btree ("testRunId");
CREATE INDEX "IDX_d6870d3b6e4c185d33926f423c" ON public.test_run USING btree ("workflowId");
CREATE INDEX "IDX_test_run_collectionId" ON public.test_run USING btree ("collectionId");
CREATE INDEX "IDX_test_run_evaluationConfigId" ON public.test_run USING btree ("evaluationConfigId");
CREATE INDEX user_role_idx ON public."user" USING btree ("roleSlug");
CREATE UNIQUE INDEX "IDX_1ef35bac35d20bdae979d917a3" ON public.user_api_keys USING btree ("apiKey");
CREATE UNIQUE INDEX "IDX_63d7bbae72c767cf162d459fcc" ON public.user_api_keys USING btree ("userId", label);
CREATE INDEX "IDX_1d11050a381548c42c32cc25c4" ON public.user_favorites USING btree ("resourceType", "resourceId");
CREATE INDEX "IDX_1dd5c393ad0517be3c31a7af83" ON public.user_favorites USING btree ("userId");
CREATE UNIQUE INDEX variables_global_key_unique ON public.variables USING btree (key) WHERE ("projectId" IS NULL);
CREATE UNIQUE INDEX variables_project_key_unique ON public.variables USING btree ("projectId", key) WHERE ("projectId" IS NOT NULL);
CREATE INDEX idx_16f4436789e804e3e1c9eeb240 ON public.webhook_entity USING btree ("webhookId", method, "pathLength");
CREATE INDEX "IDX_a4ff2d9b9628ea988fa9e7d0bf" ON public.workflow_dependency USING btree ("workflowId");
CREATE INDEX "IDX_e48a201071ab85d9d09119d640" ON public.workflow_dependency USING btree ("dependencyKey");
CREATE INDEX "IDX_e7fe1cfda990c14a445937d0b9" ON public.workflow_dependency USING btree ("dependencyType");
CREATE INDEX "IDX_workflow_dependency_publishedVersionId" ON public.workflow_dependency USING btree ("publishedVersionId");
CREATE INDEX "IDX_workflow_entity_name" ON public.workflow_entity USING btree (name);
CREATE INDEX "IDX_workflow_entity_sourceWorkflowId" ON public.workflow_entity USING btree ("sourceWorkflowId") WHERE ("sourceWorkflowId" IS NOT NULL);
CREATE UNIQUE INDEX pk_workflow_entity_id ON public.workflow_entity USING btree (id);
CREATE INDEX "IDX_1e31657f5fe46816c34be7c1b4" ON public.workflow_history USING btree ("workflowId");
CREATE UNIQUE INDEX "IDX_workflow_publication_outbox_active_workflow_status" ON public.workflow_publication_outbox USING btree ("workflowId", status) WHERE ((status) IN ('pending', 'in_progress'));
CREATE INDEX "IDX_070b5de842ece9ccdda0d9738b" ON public.workflow_publish_history USING btree ("workflowId", "versionId");
CREATE UNIQUE INDEX "IDX_workflow_statistics_workflow_name" ON public.workflow_statistics USING btree ("workflowId", name);
CREATE INDEX idx_workflows_tags_workflow_id ON public.workflows_tags USING btree ("workflowId");

CREATE OR REPLACE FUNCTION public.increment_workflow_version()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
			BEGIN
				IF NEW."versionCounter" IS NOT DISTINCT FROM OLD."versionCounter"
					AND (NEW."nodes"::text IS DISTINCT FROM OLD."nodes"::text
						OR NEW."settings"::text IS DISTINCT FROM OLD."settings"::text) THEN
					NEW."versionCounter" = OLD."versionCounter" + 1;
				END IF;
				RETURN NEW;
			END;
			$function$;

CREATE TRIGGER workflow_version_increment BEFORE UPDATE ON public.workflow_entity FOR EACH ROW EXECUTE FUNCTION increment_workflow_version();

alter table public.agent_chat_subscriptions enable row level security;
alter table public.agent_checkpoints enable row level security;
alter table public.agent_execution enable row level security;
alter table public.agent_execution_threads enable row level security;
alter table public.agent_files enable row level security;
alter table public.agent_history enable row level security;
alter table public.agent_task_definition enable row level security;
alter table public.agent_task_run_lock enable row level security;
alter table public.agent_task_snapshot enable row level security;
alter table public.agents enable row level security;
alter table public.agents_memory_entries enable row level security;
alter table public.agents_memory_entry_cursors enable row level security;
alter table public.agents_memory_entry_locks enable row level security;
alter table public.agents_memory_entry_sources enable row level security;
alter table public.agents_messages enable row level security;
alter table public.agents_observation_cursors enable row level security;
alter table public.agents_observation_locks enable row level security;
alter table public.agents_observations enable row level security;
alter table public.agents_resources enable row level security;
alter table public.agents_threads enable row level security;
alter table public.ai_builder_temporary_workflow enable row level security;
alter table public.annotation_tag_entity enable row level security;
alter table public.auth_identity enable row level security;
alter table public.auth_provider_sync_history enable row level security;
alter table public.binary_data enable row level security;
alter table public.chat_hub_agent_tools enable row level security;
alter table public.chat_hub_agents enable row level security;
alter table public.chat_hub_messages enable row level security;
alter table public.chat_hub_session_tools enable row level security;
alter table public.chat_hub_sessions enable row level security;
alter table public.chat_hub_tools enable row level security;
alter table public.credential_dependency enable row level security;
alter table public.credentials_entity enable row level security;
alter table public.data_table enable row level security;
alter table public.data_table_column enable row level security;
alter table public.deployment_key enable row level security;
alter table public.dynamic_credential_entry enable row level security;
alter table public.dynamic_credential_resolver enable row level security;
alter table public.dynamic_credential_user_entry enable row level security;
alter table public.evaluation_collection enable row level security;
alter table public.evaluation_config enable row level security;
alter table public.event_destinations enable row level security;
alter table public.execution_annotation_tags enable row level security;
alter table public.execution_annotations enable row level security;
alter table public.execution_data enable row level security;
alter table public.execution_entity enable row level security;
alter table public.execution_metadata enable row level security;
alter table public.folder enable row level security;
alter table public.folder_tag enable row level security;
alter table public.insights_by_period enable row level security;
alter table public.insights_metadata enable row level security;
alter table public.insights_raw enable row level security;
alter table public.installed_nodes enable row level security;
alter table public.installed_packages enable row level security;
alter table public.instance_ai_checkpoints enable row level security;
alter table public.instance_ai_iteration_logs enable row level security;
alter table public.instance_ai_mcp_registry_connections enable row level security;
alter table public.instance_ai_messages enable row level security;
alter table public.instance_ai_observation_cursors enable row level security;
alter table public.instance_ai_observation_locks enable row level security;
alter table public.instance_ai_observational_memory enable row level security;
alter table public.instance_ai_observations enable row level security;
alter table public.instance_ai_pending_confirmations enable row level security;
alter table public.instance_ai_resources enable row level security;
alter table public.instance_ai_run_snapshots enable row level security;
alter table public.instance_ai_threads enable row level security;
alter table public.instance_ai_workflow_snapshots enable row level security;
alter table public.instance_version_history enable row level security;
alter table public.invalid_auth_token enable row level security;
alter table public.mcp_registry_server enable row level security;
alter table public.migrations enable row level security;
alter table public.oauth_access_tokens enable row level security;
alter table public.oauth_authorization_codes enable row level security;
alter table public.oauth_clients enable row level security;
alter table public.oauth_refresh_tokens enable row level security;
alter table public.oauth_user_consents enable row level security;
alter table public.processed_data enable row level security;
alter table public.project enable row level security;
alter table public.project_relation enable row level security;
alter table public.project_secrets_provider_access enable row level security;
alter table public.role enable row level security;
alter table public.role_mapping_rule enable row level security;
alter table public.role_mapping_rule_project enable row level security;
alter table public.role_scope enable row level security;
alter table public.scope enable row level security;
alter table public.secrets_provider_connection enable row level security;
alter table public.settings enable row level security;
alter table public.shared_credentials enable row level security;
alter table public.shared_workflow enable row level security;
alter table public.tag_entity enable row level security;
alter table public.test_case_execution enable row level security;
alter table public.test_run enable row level security;
alter table public.token_exchange_jti enable row level security;
alter table public.trusted_key enable row level security;
alter table public.trusted_key_source enable row level security;
alter table public."user" enable row level security;
alter table public.user_api_keys enable row level security;
alter table public.user_favorites enable row level security;
alter table public.variables enable row level security;
alter table public.webhook_entity enable row level security;
alter table public.workflow_builder_session enable row level security;
alter table public.workflow_dependency enable row level security;
alter table public.workflow_entity enable row level security;
alter table public.workflow_history enable row level security;
alter table public.workflow_publication_outbox enable row level security;
alter table public.workflow_publish_history enable row level security;
alter table public.workflow_published_version enable row level security;
alter table public.workflow_statistics enable row level security;
alter table public.workflows_tags enable row level security;


-- @section witty_backup_20261007
-- Reconstructed from production's catalog (not in any migration: created by hand with release W1 on 7 Oct 2026).
-- w3_witty_soft_gate_a creates b2b.witty_backup_20261016 "like" this table.
create table if not exists b2b.witty_backup_20261007 (
  kind text not null,
  name text not null,
  def text,
  saved_at timestamp with time zone default now(),
  constraint witty_backup_20261007_pkey PRIMARY KEY (kind, name)
);
alter table b2b.witty_backup_20261007 enable row level security;


-- @section w2_witty_b2c
-- Witty release W2 (B2C CRM), b2c-crm/docs/WITTY_CHANGES_B2C.md: W2.1, W2.2 and the w2_crm_payload line of W2.3.
-- Previous definitions are kept in b2b.witty_backup_20261015 (rollback: run each saved def).
create table if not exists b2b.witty_backup_20261015 (kind text, name text, def text, saved_at timestamptz default now());
insert into b2b.witty_backup_20261015 (kind, name, def)
select 'function', p.proname, pg_get_functiondef(p.oid) from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.proname in ('w2_try_claim', 'w2_commit_turn', 'w2_crm_payload')
   and not exists (select 1 from b2b.witty_backup_20261015 b where b.kind = 'function' and b.name = p.proname);

create or replace function public.w2_try_claim(p_phone text, p_run text, p_lease_seconds integer default 45)
 returns jsonb
 language plpgsql
as $function$
declare
  v_conv   w2_conversations;
  v_msgs   jsonb;
  v_text   text;
  v_access jsonb;
  v_bot    jsonb;
  v_rating smallint;
  v_ids    text[];
begin
  insert into w2_conversations (phone) values (p_phone) on conflict (phone) do nothing;
  update w2_conversations
     set lock_id = p_run, lock_until = now() + make_interval(secs => p_lease_seconds)
   where phone = p_phone and (lock_until is null or lock_until < now() or lock_id = p_run)
  returning * into v_conv;
  if not found then
    return jsonb_build_object('acquired', false);
  end if;

  with c as (
    update w2_inbox set claimed_by = p_run
     where phone = p_phone and processed_at is null
    returning *
  )
  select coalesce(jsonb_agg(to_jsonb(c) order by c.received_at), '[]'::jsonb) into v_msgs from c;
  select coalesce(array_agg(m->>'message_id'), '{}') into v_ids from jsonb_array_elements(v_msgs) m;
  select string_agg(coalesce(m->>'content', ''), E'\n' order by m->>'received_at') into v_text from jsonb_array_elements(v_msgs) m;

  -- 1. Bots: a blocked number gets no reply at all; its messages are kept for review.
  if cardinality(v_ids) > 0 then
    if w2_is_blocked(p_phone) then
      v_bot := jsonb_build_object('blocked', true, 'reason', 'already blocked');
    else
      v_bot := w2_bot_check(p_phone);
    end if;
    if (v_bot->>'blocked')::boolean then
      update w2_inbox set processed_at = now() where message_id = any(v_ids);
      update w2_messages set kind = 'blocked' where direction = 'in' and message_id = any(v_ids);
      return jsonb_build_object('acquired', true, 'blocked', true, 'bot', v_bot, 'conversation', to_jsonb(v_conv), 'messages', '[]'::jsonb);
    end if;
  end if;

  -- 1b. CRM owns the lead (assigned in-house or sent to a partner): Witty stays silent, the message is logged for the timeline.
  if cardinality(v_ids) > 0 and w2_crm_owned(p_phone) then
    update w2_inbox set processed_at = now() where message_id = any(v_ids);
    update w2_messages set kind = 'crm_paused' where direction = 'in' and message_id = any(v_ids);
    -- W2.2 (B2C CRM): record the unanswered message on the lead, one touchpoint per lead per day; never block Witty.
    begin
      perform lead_intake(jsonb_build_object(
        'source_system', 'witty', 'event_type', 'chat.reenquiry',
        'idempotency_key', p_phone || ':paused:' || to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD'),
        'phone', p_phone, 'lead', '{}'::jsonb));
    exception when others then null;
    end;
    return jsonb_build_object('acquired', true, 'crm_paused', true, 'conversation', to_jsonb(v_conv), 'messages', '[]'::jsonb);
  end if;

  -- 1c. W2.1 (B2C CRM): a chat Witty paused at escalation, whose lead now sits in B2C (allocation in_house, handed_off)
  --     with no counsellor, gets Witty back. escalated_at stays, so Witty never promises a counsellor twice.
  --     Not owned by the CRM here: step 1b returned otherwise. The Chatwoot label witty-handoff is not removed by this function.
  if cardinality(v_ids) > 0 and v_conv.bot_paused and exists (
       select 1 from crm_find_lead(p_phone) l
         join b2b.allocations a on a.id = l.allocation_id and a.lead_id = l.id
        where l.id is not null and l.owner_user_id is null
          and a.destination_type = 'in_house' and a.status = 'handed_off') then
    update w2_conversations
       set bot_paused = false, state = coalesce(state, '{}'::jsonb) || jsonb_build_object('bot_paused', false)
     where phone = p_phone
    returning * into v_conv;
  end if;

  -- 2. A one-tap answer to "Was this chat helpful?" is recorded, not answered.
  if cardinality(v_ids) > 0 and v_conv.state ? 'feedback_asked_at' and not coalesce((v_conv.state->>'feedback_done')::boolean, false)
     and (v_conv.state->>'feedback_asked_at')::timestamptz > now() - interval '48 hours' then
    v_rating := w2_parse_rating(v_text);
    if v_rating is not null then
      insert into w2_feedback (phone, source, rating, label, comment, meta)
      values (p_phone, 'student', v_rating, case v_rating when 1 then 'helpful' when -1 then 'not helpful' else 'neutral' end, left(v_text, 500),
              jsonb_build_object('asked_after', v_conv.state->>'feedback_asked_mode'));
      update w2_conversations set state = state || jsonb_build_object('feedback_done', true, 'feedback_rating', v_rating)
       where phone = p_phone returning * into v_conv;
      update w2_inbox set processed_at = now() where message_id = any(v_ids);
      update w2_messages set kind = 'feedback' where direction = 'in' and message_id = any(v_ids);
      return jsonb_build_object('acquired', true, 'feedback', v_rating, 'conversation', to_jsonb(v_conv), 'messages', '[]'::jsonb);
    end if;
  end if;

  -- 3. Access code gate.
  if v_conv.access_code is not null then
    v_access := jsonb_build_object('status', 'verified', 'code', v_conv.access_code, 'source', v_conv.lead_source, 'attribution', v_conv.attribution);
  else
    v_access := w2_redeem_code(p_phone, v_text);
    if v_access->>'status' = 'ok' then
      update w2_conversations
         set access_code = coalesce(v_access->>'code', 'LEGACY'), access_at = now(), lead_source = v_access->>'source',
             attribution = v_access->'attribution'
       where phone = p_phone
      returning * into v_conv;
    elsif v_access->>'status' in ('invalid', 'taken', 'expired') then
      insert into w2_security_log (phone, kind, detail) values (p_phone, 'bad_code', jsonb_build_object('status', v_access->>'status', 'code', v_access->>'code'));
    end if;
  end if;

  return jsonb_build_object('acquired', true, 'conversation', to_jsonb(v_conv), 'messages', v_msgs, 'access', v_access,
                            'activation_code', v_access->>'code', 'lead_source', v_conv.lead_source, 'prompts', w2_turn_prompts(),
                            'kb_ready', exists (select 1 from w2_kb_docs d where d.active and d.chunks > 0));
end $function$;

create or replace function public.w2_crm_payload(p_phone text, p_event text, p_key text, p jsonb)
 returns jsonb
 language plpgsql
 stable
as $function$
declare
  c  w2_conversations;
  s  jsonb;
  pr jsonb;
  a  jsonb;
  v_lead jsonb;
begin
  select * into c from w2_conversations where phone = p_phone;
  s  := coalesce(c.state, '{}'::jsonb);
  pr := coalesce(s->'profile', '{}'::jsonb);
  a  := coalesce(c.attribution, '{}'::jsonb);
  v_lead := jsonb_strip_nulls(jsonb_build_object(
    'full_name',            w2_pv(pr, 'student_name'),
    'is_name_confirmed',    pr->'student_name'->>'status' = 'confirmed',
    'email',                w2_pv(pr, 'email_id'),
    'is_email_confirmed',   pr->'email_id'->>'status' = 'confirmed',
    'interested_course',    w2_pv(pr, 'interested_course'),
    'interested_specialization', w2_pv(pr, 'specialization'),
    'field_of_interest',    w2_pv(pr, 'field_of_interest'),
    'university_preference', w2_pv(pr, 'university_preference'), 'interested_university', case when pr->'final_program'->>'status' = 'confirmed' then pr->'final_program'->>'university' end,
    'programme_level',      w2_pv(pr, 'program_level'),
    'study_mode_preference', w2_pv(pr, 'study_mode_preference'),
    'highest_qualification', w2_pv(pr, 'highest_qualification'),
    'current_study',        w2_pv(pr, 'current_study'),
    'academic_score_raw',   w2_pv(pr, 'academic_score'),
    'academic_score_pct',   crm_num(w2_pv(pr, 'academic_score')),
    'work_experience_raw',  w2_pv(pr, 'work_experience_years'),
    'work_experience_years_num', crm_num(w2_pv(pr, 'work_experience_years')),
    'current_job_role',     w2_pv(pr, 'current_job_role'),
    'annual_budget_raw',    w2_pv(pr, 'annual_budget'),
    'annual_budget_inr',    crm_num(w2_pv(pr, 'annual_budget')),
    'enrollment_timeline',  w2_pv(pr, 'enrollment_timeline'),
    'primary_motivation',   w2_pv(pr, 'primary_motivation'),
    'location_raw',         w2_pv(pr, 'current_city_country')
  )) || jsonb_strip_nulls(jsonb_build_object(   -- two objects: jsonb_build_object takes at most 100 arguments
    'preferred_language',   s->>'language',
    'enquirer_relation',    s->'enquirer'->>'relation',
    'guardian_name',        case when s->'enquirer'->>'relation' in ('father', 'mother', 'parent') then s->'enquirer'->>'name' end,
    'classification',       c.classification,
    'classification_ai',    c.classification,
    'readiness',            c.readiness,
    'eligibility',          c.eligibility,
    'conversation_phase',   s->>'phase',
    'last_intent',          (select string_agg(x, ',') from jsonb_array_elements_text(coalesce(p->'event'->'payload'->'intents', '[]'::jsonb)) x),
    'source',               c.lead_source,
    'channel',              'whatsapp',
    'source_detail',        a->>'kind',
    'campaign',             coalesce(a->>'campaign', a->>'utm_campaign', a->>'parent_campaign'),
    'utm_source',           a->>'utm_source',
    'utm_medium',           a->>'utm_medium',
    'utm_campaign',         a->>'utm_campaign',
    'utm_content',          a->>'utm_content',
    'utm_term',             a->>'utm_term',
    'click_ids',            a->'click_ids',
    'landing_url',          a->>'landing_url',
    'referrer_url',         a->>'referrer',
    'referred_by_code',     a->>'via',
    'access_code',          nullif(c.access_code, 'LEGACY'),
    'ip_address',           a->>'ip',
    'device_type',          a->>'device_type',
    'device_fingerprint',   a->>'fingerprint',
    'consent_sales_at',     c.consent_at,
    -- Addendum 3 PART 7.1: set by Witty when the consent line naming admission partners is shown
    'consent_partner_share_at', case when s->>'consent_partner_share_at' ~ '^\d{4}-\d{2}-\d{2}' then (s->>'consent_partner_share_at')::timestamptz end,
    -- W2.3 (B2C CRM): set by Witty when the consent line covering marketing is shown (version witty-notice-2026-10-v3)
    'consent_marketing_at', case when s->>'consent_marketing_at' ~ '^\d{4}-\d{2}-\d{2}' then (s->>'consent_marketing_at')::timestamptz end,
    'consent_text_version', s->>'consent_text_version',
    'is_opted_out',         c.opted_out,
    'first_agent_channel',  'whatsapp',
    'chatwoot_conversation_id', c.conversation_id,
    'is_bot_paused',        c.bot_paused,
    'last_agent_message_at', case when coalesce(p->'log'->>'content', '') <> '' then now() end
  ));
  return jsonb_build_object('source_system', 'witty', 'event_type', p_event, 'idempotency_key', p_key, 'phone', p_phone,
                            'lead', v_lead, 'attribution', a, 'occurred_at', coalesce((a->>'first_click_at')::timestamptz, c.created_at),
                            'is_test', w2_is_test(p_phone));
end $function$;

-- @section m33f_cron_history_performance_runid_window
-- M33f: health_check and system_overview read only the newest cron runs, found through the runid primary key.
create or replace function b2b.health_check()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_stale int;
  v_failed int;
  v_dead int;
  v_waiting int;
  v_cursor_age numeric;
begin
  -- the latest run and its status per job, from the newest 6,000 runs (about 2.5 hours)
  with last_run as (
    select distinct on (d.jobid) d.jobid, d.start_time, d.status
      from cron.job_run_details d
     where d.runid > (select max(x.runid) - 6000 from cron.job_run_details x)
     order by d.jobid, d.runid desc)
  select count(*) filter (where (j.schedule ~ 'second' or j.schedule ~ '^\* \* \* \* \*$') and coalesce(r.start_time, '-infinity') < now() - interval '15 minutes'),
         count(*) filter (where r.status = 'failed')
    into v_stale, v_failed
    from cron.job j left join last_run r on r.jobid = j.jobid
   where j.jobname like 'b2b-%' and j.active;
  select count(*) filter (where status = 'dead'), count(*) filter (where status in ('pending', 'failed') and created_at < now() - interval '1 hour')
    into v_dead, v_waiting from b2b.integration_outbox where endpoint_id is not null and created_at > now() - interval '7 days';
  select extract(epoch from now() - (value ->> 'last_run')::timestamptz) into v_cursor_age from b2b.b2c_link_state where key = 'cursor';
  return jsonb_build_object(
    'ok', v_stale = 0 and v_failed = 0 and coalesce(v_cursor_age, 0) < 600,
    'at', now(),
    'jobs', jsonb_build_object('stale', v_stale, 'last_run_failed', v_failed),
    'deliveries', jsonb_build_object('dead_7d', v_dead, 'waiting_over_1h', v_waiting),
    'b2c_sync', jsonb_build_object('cursor_age_seconds', round(coalesce(v_cursor_age, 0))));
end $fn$;

create or replace function b2b.system_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare v_jobs jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  -- the jobs card, from the newest 75,000 runs (about 30 hours)
  with recent as materialized (
    select d.jobid, d.runid, d.start_time, d.status, d.return_message
      from cron.job_run_details d where d.runid > (select max(x.runid) - 75000 from cron.job_run_details x)),
  last_run as (select distinct on (r.jobid) r.jobid, r.start_time, r.status from recent r order by r.jobid, r.runid desc),
  failed as (select r.jobid, count(*) as n from recent r where r.status = 'failed' and r.start_time > now() - interval '1 day' group by r.jobid),
  last_err as (
    select distinct on (r.jobid) r.jobid, left(r.return_message, 200) as msg
      from recent r where r.status = 'failed' and r.start_time > now() - interval '1 day' order by r.jobid, r.runid desc)
  select coalesce(jsonb_agg(jsonb_build_object('name', j.jobname, 'schedule', j.schedule, 'active', j.active,
                             'last_status', r.status, 'last_run', r.start_time, 'last_error', e.msg, 'failed_24h', coalesce(f.n, 0)) order by j.jobname), '[]')
    into v_jobs
    from cron.job j
    left join last_run r on r.jobid = j.jobid
    left join failed f on f.jobid = j.jobid
    left join last_err e on e.jobid = j.jobid
   where j.jobname like 'b2b-%';
  return jsonb_build_object(
    'api_keys', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'name', k.name, 'scopes', k.scopes, 'prefix', k.key_prefix, 'created_at', k.created_at,
                                                              'last_used_at', k.last_used_at, 'revoked_at', k.revoked_at,
                                                              'expires_at', k.expires_at, 'rate_per_minute', k.rate_per_minute, 'note', k.note,
                                                              'requests_1h', (select coalesce(sum(u.n), 0) from b2b.api_key_usage u where u.api_key_id = k.id and u.minute > now() - interval '1 hour'),
                                                              'requests_24h', (select coalesce(sum(u.n), 0) from b2b.api_key_usage u where u.api_key_id = k.id and u.minute > now() - interval '24 hours'))
                                                   order by k.revoked_at nulls first, k.created_at desc)
                          from b2b.api_keys k), '[]'),
    'api_limits', coalesce((select value from b2b.settings where key = 'api_limits'), '{}'),
    'endpoints', coalesce((select jsonb_agg(to_jsonb(w) - 'secret_id' || jsonb_build_object('has_secret', w.secret_id is not null,
                             'pending', (select count(*) from b2b.integration_outbox o where o.endpoint_id = w.id and o.status in ('pending', 'failed', 'sending')),
                             'dead', (select count(*) from b2b.integration_outbox o where o.endpoint_id = w.id and o.status = 'dead'),
                             'delivered_24h', (select count(*) from b2b.integration_outbox o where o.endpoint_id = w.id and o.status = 'delivered' and o.delivered_at > now() - interval '1 day'))
                           order by w.id) from b2b.webhook_endpoints w), '[]'),
    'deliveries', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'event_type', o.event_type, 'endpoint_id', o.endpoint_id,
                              'endpoint', (select w.name from b2b.webhook_endpoints w where w.id = o.endpoint_id), 'status', o.status, 'attempts', o.attempts,
                              'response_status', o.response_status, 'last_error', o.last_error, 'created_at', o.created_at, 'delivered_at', o.delivered_at,
                              'next_attempt_at', o.next_attempt_at, 'lead_id', (o.payload ->> 'lead_id')::bigint) order by o.id desc)
                            from (select * from b2b.integration_outbox where endpoint_id is not null order by id desc limit 100) o), '[]'),
    'product_events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'source', e.source, 'event_type', e.event_type, 'lead_id', e.lead_id,
                                  'status', e.status, 'result', e.result, 'received_at', e.received_at) order by e.id desc)
                                from (select * from b2b.product_events order by id desc limit 50) e), '[]'),
    'erasure_open', (select count(*) from b2b.erasure_requests where status = 'open'),
    'jobs', v_jobs);
end $fn$;

-- @section m33f_cron_history_prune
/* Seven days of run history is enough for the Health screen and the alerts; the rest goes nightly (22:15 UTC, 03:45 IST). */
do $cron$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'b2b-cron-prune';
  perform cron.schedule('b2b-cron-prune', '15 22 * * *', $j$delete from cron.job_run_details where start_time < now() - interval '7 days'$j$);
end $cron$;

-- @section w3_witty_soft_gate_a_backup_inbox_redeem_agentpause
-- W3 (16 Oct 2026) part A: backup, referral column, w2_inbox_add, w2_redeem_code (attempted flag), w2_agent_pause.
create table if not exists b2b.witty_backup_20261016 (like b2b.witty_backup_20261007 including all);
insert into b2b.witty_backup_20261016 (kind, name, def, saved_at)
select 'function', p.proname, pg_get_functiondef(p.oid), now()
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('w2_try_claim', 'w2_redeem_code', 'w2_inbox_add', 'w2_crm_payload');

alter table w2_inbox add column if not exists referral jsonb;

create or replace function public.w2_inbox_add(p jsonb) returns jsonb language plpgsql as $function$
declare v_id text;
begin
insert into w2_inbox (message_id, phone, conversation_id, account_id, content, content_type, has_attachment, labels, referral)
values (p->>'message_id', p->>'phone', (p->>'conversation_id')::bigint, (p->>'account_id')::bigint, p->>'content',
p->>'content_type', coalesce((p->>'has_attachment')::boolean, false), p->'labels',
case when jsonb_typeof(p->'referral') = 'object' then p->'referral' end)
on conflict (message_id) do nothing
returning message_id into v_id;
if v_id is not null then
insert into w2_messages (phone, direction, kind, message_id, content, meta)
values (p->>'phone', 'in', 'chat', v_id, p->>'content',
jsonb_build_object('conversation_id', p->>'conversation_id', 'content_type', p->>'content_type', 'has_attachment', coalesce((p->>'has_attachment')::boolean, false),
'referral', case when jsonb_typeof(p->'referral') = 'object' then p->'referral' end))
on conflict do nothing;
end if;
return jsonb_build_object('inserted', v_id is not null, 'phone', p->>'phone');
end $function$;

create or replace function public.w2_redeem_code(p_phone text, p_text text) returns jsonb language plpgsql as $function$
declare
v_phone  text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
v_text   text := coalesce(p_text, '');
v_cands  text[] := '{}';
v_c      text;
r        w2_access_codes;
v_status text := 'none';
v_bad    text;
v_leg    record;
v_said   boolean := true;   -- the student said "access code ..." (a bare 6-letter word may just be a word)
begin
-- Hermes test agent (Chatwoot API contacts +91 90000 000NN, not on WhatsApp): no access code needed. Added 4 Oct 2026.
if v_phone ~ '^9190000000[0-9]{2}$' then
return jsonb_build_object('status', 'ok', 'via', 'test_hermes', 'code', 'HERMES', 'kind', 'test', 'source', 'test_hermes',
'attribution', jsonb_build_object('code', 'HERMES', 'kind', 'test', 'source', 'test_hermes'));
end if;
select coalesce(array_agg(distinct upper(m[1])), '{}') into v_cands
from regexp_matches(v_text, '(?:access|activation)\s*code\s*(?:is|:|-)?\s*\m([A-Za-z0-9]{6})\M', 'gi') m;
if cardinality(v_cands) = 0 then
v_said := false;
select coalesce(array_agg(distinct upper(m[1])), '{}') into v_cands
from regexp_matches(v_text, '(?:^|\n)\s*([A-Za-z0-9]{6})\s*[.!]?\s*(?:$|\n)', 'g') m;
end if;
foreach v_c in array v_cands loop
select * into r from w2_access_codes where code = v_c for update;
if found then
if r.kind = 'campaign' or r.phone = v_phone then
update w2_access_codes set redeem_count = redeem_count + 1, last_redeemed_at = now() where code = v_c;
return jsonb_build_object('status', 'ok', 'via', 'code', 'code', v_c, 'kind', r.kind, 'source', r.source, 'campaign', r.campaign,
'attribution', r.attribution || jsonb_build_object('code', v_c, 'kind', r.kind));
elsif r.phone is null and (r.expires_at is null or r.expires_at > now()) then
update w2_access_codes set phone = v_phone, bound_at = now(), redeem_count = redeem_count + 1, last_redeemed_at = now() where code = v_c;
return jsonb_build_object('status', 'ok', 'via', 'code', 'code', v_c, 'kind', r.kind, 'source', r.source, 'campaign', r.campaign,
'attribution', r.attribution || jsonb_build_object('code', v_c, 'kind', r.kind));
elsif r.phone is null then
v_status := 'expired'; v_bad := v_c;
else
v_status := 'taken'; v_bad := v_c;
end if;
else
begin
select referral_code into v_leg from student_leads where upper(activation_code) = v_c order by created_at desc limit 1;
if found then
return jsonb_build_object('status', 'ok', 'via', 'legacy_code', 'code', v_c, 'kind', 'legacy', 'source', coalesce(nullif(v_leg.referral_code, ''), 'legacy'),
'attribution', jsonb_build_object('code', v_c, 'kind', 'legacy', 'legacy_referral', v_leg.referral_code));
end if;
exception when others then null;
end;
if v_status = 'none' and v_said then v_status := 'invalid'; v_bad := v_c; end if;
end if;
end loop;
select * into r from w2_access_codes where phone = v_phone order by bound_at desc limit 1;
if found then
return jsonb_build_object('status', 'ok', 'via', 'returning', 'code', r.code, 'kind', r.kind, 'source', r.source, 'campaign', r.campaign,
'attribution', r.attribution || jsonb_build_object('code', r.code, 'kind', r.kind));
end if;
begin
select activation_code, referral_code into v_leg from student_leads
where regexp_replace(coalesce(whatsapp_number, ''), '\D', '', 'g') = v_phone order by created_at desc limit 1;
if found then
return jsonb_build_object('status', 'ok', 'via', 'legacy_phone', 'code', upper(v_leg.activation_code), 'kind', 'legacy',
'source', coalesce(nullif(v_leg.referral_code, ''), 'legacy'),
'attribution', jsonb_build_object('code', upper(v_leg.activation_code), 'kind', 'legacy', 'legacy_referral', v_leg.referral_code));
end if;
exception when others then null;
end;
-- W3: 'attempted' tells the gateway whether the student actually typed a code that failed (then one correction line is shown),
-- as opposed to a chat with no code at all (then nothing is shown and the chat simply continues as a direct lead).
return jsonb_build_object('status', v_status, 'code', v_bad, 'attempted', v_status <> 'none');
end $function$;

create or replace function public.w2_agent_pause(p jsonb) returns jsonb language plpgsql as $function$
declare v_phone text := regexp_replace(coalesce(p->>'phone', ''), '\D', '', 'g');
begin
if v_phone = '' then return jsonb_build_object('paused', false, 'reason', 'no phone'); end if;
insert into w2_conversations (phone) values (v_phone) on conflict (phone) do nothing;
update w2_conversations
   set bot_paused = true,
       state = coalesce(state, '{}'::jsonb) || jsonb_build_object('bot_paused', true, 'paused_by', 'agent', 'paused_at', now(), 'paused_agent', p->>'agent'),
       updated_at = now()
 where phone = v_phone;
insert into w2_events (phone, type, run_id, payload) values (v_phone, 'agent_takeover', p->>'run_id', jsonb_build_object('agent', p->>'agent', 'conversation_id', p->>'conversation_id'));
return jsonb_build_object('paused', true, 'phone', v_phone);
end $function$;

-- @section w3_witty_soft_gate_b_try_claim
-- W3 (16 Oct 2026) part B: w2_try_claim with the soft access gate (every chat is a lead), referral binding, agent pause.
create or replace function public.w2_try_claim(p_phone text, p_run text, p_lease_seconds integer default 45) returns jsonb language plpgsql as $function$
declare
  v_conv   w2_conversations;
  v_msgs   jsonb;
  v_text   text;
  v_access jsonb;
  v_up     jsonb;
  v_bot    jsonb;
  v_rating smallint;
  v_ids    text[];
  v_ref    jsonb;
  v_src    text;
  v_attr   jsonb;
  v_utm    jsonb;
begin
  insert into w2_conversations (phone) values (p_phone) on conflict (phone) do nothing;
  update w2_conversations
     set lock_id = p_run, lock_until = now() + make_interval(secs => p_lease_seconds)
   where phone = p_phone and (lock_until is null or lock_until < now() or lock_id = p_run)
  returning * into v_conv;
  if not found then
    return jsonb_build_object('acquired', false);
  end if;

  with c as (
    update w2_inbox set claimed_by = p_run
     where phone = p_phone and processed_at is null
    returning *
  )
  select coalesce(jsonb_agg(to_jsonb(c) order by c.received_at), '[]'::jsonb) into v_msgs from c;
  select coalesce(array_agg(m->>'message_id'), '{}') into v_ids from jsonb_array_elements(v_msgs) m;
  select string_agg(coalesce(m->>'content', ''), E'\n' order by m->>'received_at') into v_text from jsonb_array_elements(v_msgs) m;

  -- 1. Bots: a blocked number gets no reply at all; its messages are kept for review.
  if cardinality(v_ids) > 0 then
    if w2_is_blocked(p_phone) then
      v_bot := jsonb_build_object('blocked', true, 'reason', 'already blocked');
    else
      v_bot := w2_bot_check(p_phone);
    end if;
    if (v_bot->>'blocked')::boolean then
      update w2_inbox set processed_at = now() where message_id = any(v_ids);
      update w2_messages set kind = 'blocked' where direction = 'in' and message_id = any(v_ids);
      return jsonb_build_object('acquired', true, 'blocked', true, 'bot', v_bot, 'conversation', to_jsonb(v_conv), 'messages', '[]'::jsonb);
    end if;
  end if;

  -- 1b. CRM owns the lead (assigned in-house or sent to a partner): Witty stays silent, the message is logged for the timeline.
  if cardinality(v_ids) > 0 and w2_crm_owned(p_phone) then
    update w2_inbox set processed_at = now() where message_id = any(v_ids);
    update w2_messages set kind = 'crm_paused' where direction = 'in' and message_id = any(v_ids);
    -- W2.2 (B2C CRM): record the unanswered message on the lead, one touchpoint per lead per day; never block Witty.
    begin
      perform lead_intake(jsonb_build_object(
        'source_system', 'witty', 'event_type', 'chat.reenquiry',
        'idempotency_key', p_phone || ':paused:' || to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD'),
        'phone', p_phone, 'lead', '{}'::jsonb));
    exception when others then null;
    end;
    return jsonb_build_object('acquired', true, 'crm_paused', true, 'conversation', to_jsonb(v_conv), 'messages', '[]'::jsonb);
  end if;

  -- 1c. W2.1 (B2C CRM): a chat Witty paused at escalation, whose lead now sits in B2C (allocation in_house, handed_off)
  --     with no counsellor, gets Witty back. escalated_at stays, so Witty never promises a counsellor twice.
  if cardinality(v_ids) > 0 and v_conv.bot_paused and coalesce(v_conv.state->>'paused_by', '') <> 'agent' and exists (
       select 1 from crm_find_lead(p_phone) l
         join b2b.allocations a on a.id = l.allocation_id and a.lead_id = l.id
        where l.id is not null and l.owner_user_id is null
          and a.destination_type = 'in_house' and a.status = 'handed_off') then
    update w2_conversations
       set bot_paused = false, state = coalesce(state, '{}'::jsonb) || jsonb_build_object('bot_paused', false)
     where phone = p_phone
    returning * into v_conv;
  end if;

  -- 1d. W3: a human agent replied in Chatwoot (w2_agent_pause). Witty stays quiet for 4 hours after the pause, then answers again.
  if cardinality(v_ids) > 0 and coalesce(v_conv.state->>'paused_by', '') = 'agent' then
    if coalesce((v_conv.state->>'paused_at')::timestamptz, now()) > now() - interval '4 hours' then
      update w2_inbox set processed_at = now() where message_id = any(v_ids);
      update w2_messages set kind = 'agent_paused' where direction = 'in' and message_id = any(v_ids);
      return jsonb_build_object('acquired', true, 'agent_paused', true, 'conversation', to_jsonb(v_conv), 'messages', '[]'::jsonb);
    end if;
    update w2_conversations
       set bot_paused = false, state = (coalesce(state, '{}'::jsonb) - 'paused_by' - 'paused_at' - 'paused_agent') || jsonb_build_object('bot_paused', false)
     where phone = p_phone
    returning * into v_conv;
  end if;

  -- 2. A one-tap answer to "Was this chat helpful?" is recorded, not answered.
  if cardinality(v_ids) > 0 and v_conv.state ? 'feedback_asked_at' and not coalesce((v_conv.state->>'feedback_done')::boolean, false)
     and (v_conv.state->>'feedback_asked_at')::timestamptz > now() - interval '48 hours' then
    v_rating := w2_parse_rating(v_text);
    if v_rating is not null then
      insert into w2_feedback (phone, source, rating, label, comment, meta)
      values (p_phone, 'student', v_rating, case v_rating when 1 then 'helpful' when -1 then 'not helpful' else 'neutral' end, left(v_text, 500),
              jsonb_build_object('asked_after', v_conv.state->>'feedback_asked_mode'));
      update w2_conversations set state = state || jsonb_build_object('feedback_done', true, 'feedback_rating', v_rating)
       where phone = p_phone returning * into v_conv;
      update w2_inbox set processed_at = now() where message_id = any(v_ids);
      update w2_messages set kind = 'feedback' where direction = 'in' and message_id = any(v_ids);
      return jsonb_build_object('acquired', true, 'feedback', v_rating, 'conversation', to_jsonb(v_conv), 'messages', '[]'::jsonb);
    end if;
  end if;

  -- 3. Access code: attribution only (W3 soft gate, 16 Oct 2026). Every chat becomes a lead on its first message.
  if v_conv.access_code is not null then
    v_access := jsonb_build_object('status', 'verified', 'code', v_conv.access_code, 'source', v_conv.lead_source, 'attribution', v_conv.attribution);
    -- A direct lead that later types a real code is upgraded once, so ad attribution is not lost.
    if v_conv.access_code = 'DIRECT' and cardinality(v_ids) > 0 and v_text ~* '(access|activation)\s*code' then
      v_up := w2_redeem_code(p_phone, v_text);
      if v_up->>'status' = 'ok' and v_up->>'via' in ('code', 'legacy_code') then
        update w2_conversations
           set access_code = v_up->>'code', access_at = now(), lead_source = v_up->>'source',
               attribution = coalesce(attribution, '{}'::jsonb) || coalesce(v_up->'attribution', '{}'::jsonb) || jsonb_build_object('upgraded_from', 'DIRECT')
         where phone = p_phone
        returning * into v_conv;
        v_access := jsonb_build_object('status', 'verified', 'code', v_conv.access_code, 'source', v_conv.lead_source, 'attribution', v_conv.attribution, 'upgraded', true);
      end if;
    end if;
  else
    v_access := w2_redeem_code(p_phone, v_text);
    if v_access->>'status' = 'ok' then
      update w2_conversations
         set access_code = coalesce(v_access->>'code', 'LEGACY'), access_at = now(), lead_source = v_access->>'source',
             attribution = v_access->'attribution'
       where phone = p_phone
      returning * into v_conv;
    else
      if v_access->>'status' in ('invalid', 'taken', 'expired') then
        insert into w2_security_log (phone, kind, detail) values (p_phone, 'bad_code', jsonb_build_object('status', v_access->>'status', 'code', v_access->>'code'));
      end if;
      if cardinality(v_ids) > 0 then
        -- Bind the conversation now: a click-to-WhatsApp referral makes it a paid Meta lead, otherwise an organic direct lead.
        select referral into v_ref from w2_inbox where phone = p_phone and referral is not null order by received_at limit 1;
        if v_ref is not null then
          v_utm := '{}'::jsonb;
          if coalesce(v_ref->>'source_url', '') ~ 'utm_' then
            select coalesce(jsonb_object_agg(m[1], m[2]), '{}'::jsonb) into v_utm
              from regexp_matches(v_ref->>'source_url', '(utm_[a-z]+)=([^&#]+)', 'g') m;
          end if;
          v_src := 'meta_ctwa';
          v_attr := jsonb_strip_nulls(jsonb_build_object('kind', 'paid', 'source', 'meta', 'via', 'ctwa',
                      'campaign', coalesce(v_ref->>'headline', v_ref->>'source_id'), 'landing_url', v_ref->>'source_url',
                      'click_ids', jsonb_strip_nulls(jsonb_build_object('ctwa_clid', v_ref->>'ctwa_clid', 'ad_id', v_ref->>'source_id')),
                      'utm_source', coalesce(v_utm->>'utm_source', 'meta'), 'utm_medium', coalesce(v_utm->>'utm_medium', 'paid_social'),
                      'utm_campaign', v_utm->>'utm_campaign', 'utm_content', v_utm->>'utm_content', 'utm_term', v_utm->>'utm_term',
                      'referral', v_ref, 'first_message_at', now()));
        else
          v_src := 'whatsapp_direct';
          v_attr := jsonb_build_object('kind', 'organic', 'source', 'whatsapp_direct', 'via', 'direct', 'first_message_at', now());
        end if;
        update w2_conversations
           set access_code = 'DIRECT', access_at = now(), lead_source = v_src, attribution = v_attr
         where phone = p_phone
        returning * into v_conv;
        if v_access->>'status' in ('invalid', 'taken', 'expired') and coalesce((v_access->>'attempted')::boolean, false) then
          -- the student typed a code that failed: the gateway shows one correction line, and the chat goes on as a direct lead
          v_access := v_access || jsonb_build_object('bound', true, 'source', v_src, 'attribution', v_attr);
        else
          v_access := jsonb_build_object('status', 'ok', 'via', 'direct', 'code', 'DIRECT', 'source', v_src, 'attribution', v_attr);
        end if;
      end if;
    end if;
  end if;

  return jsonb_build_object('acquired', true, 'conversation', to_jsonb(v_conv), 'messages', v_msgs, 'access', v_access,
                            'activation_code', v_access->>'code', 'lead_source', v_conv.lead_source, 'prompts', w2_turn_prompts(),
                            'kb_ready', exists (select 1 from w2_kb_docs d where d.active and d.chunks > 0),
                            'kb_chunks', (select coalesce(sum(d.chunks), 0) from w2_kb_docs d where d.active));
end $function$;

-- @section w3_witty_soft_gate_c_payload_sweep
-- W3 (16 Oct 2026) part C: w2_crm_payload (DIRECT is not a code; final programme; programmes shown; volunteered refusal), block sweep.
create or replace function public.w2_crm_payload(p_phone text, p_event text, p_key text, p jsonb) returns jsonb language plpgsql stable as $function$
declare
  c  w2_conversations;
  s  jsonb;
  pr jsonb;
  a  jsonb;
  v_lead jsonb;
begin
  select * into c from w2_conversations where phone = p_phone;
  s  := coalesce(c.state, '{}'::jsonb);
  pr := coalesce(s->'profile', '{}'::jsonb);
  a  := coalesce(c.attribution, '{}'::jsonb);
  v_lead := jsonb_strip_nulls(jsonb_build_object(
    'full_name',            w2_pv(pr, 'student_name'),
    'is_name_confirmed',    pr->'student_name'->>'status' = 'confirmed',
    'email',                w2_pv(pr, 'email_id'),
    'is_email_confirmed',   pr->'email_id'->>'status' = 'confirmed',
    'interested_course',    w2_pv(pr, 'interested_course'),
    'interested_specialization', w2_pv(pr, 'specialization'),
    'field_of_interest',    w2_pv(pr, 'field_of_interest'),
    'university_preference', w2_pv(pr, 'university_preference'),
    'interested_university', case when pr->'final_program'->>'status' = 'confirmed' then pr->'final_program'->>'university' end,
    'final_program_id',     case when pr->'final_program'->>'status' = 'confirmed' then pr->'final_program'->>'id' end,
    'final_program_name',   case when pr->'final_program'->>'status' = 'confirmed' then pr->'final_program'->>'program_name' end,
    'final_program_confirmed_at', case when pr->'final_program'->>'status' = 'confirmed' and pr->'final_program'->>'at' ~ '^\d{4}-\d{2}-\d{2}' then (pr->'final_program'->>'at')::timestamptz end,
    'programs_shown',       case when jsonb_typeof(s->'flags'->'shown_rows') = 'array' then s->'flags'->'shown_rows' end,
    'programme_level',      w2_pv(pr, 'program_level'),
    'study_mode_preference', w2_pv(pr, 'study_mode_preference'),
    'highest_qualification', w2_pv(pr, 'highest_qualification'),
    'current_study',        w2_pv(pr, 'current_study'),
    'academic_score_raw',   w2_pv(pr, 'academic_score'),
    'academic_score_pct',   crm_num(w2_pv(pr, 'academic_score')),
    'work_experience_raw',  w2_pv(pr, 'work_experience_years'),
    'work_experience_years_num', crm_num(w2_pv(pr, 'work_experience_years')),
    'current_job_role',     w2_pv(pr, 'current_job_role'),
    'annual_budget_raw',    w2_pv(pr, 'annual_budget'),
    'annual_budget_inr',    crm_num(w2_pv(pr, 'annual_budget')),
    'enrollment_timeline',  w2_pv(pr, 'enrollment_timeline'),
    'primary_motivation',   w2_pv(pr, 'primary_motivation'),
    'location_raw',         w2_pv(pr, 'current_city_country')
  )) || jsonb_strip_nulls(jsonb_build_object(   -- two objects: jsonb_build_object takes at most 100 arguments
    'preferred_language',   s->>'language',
    'enquirer_relation',    s->'enquirer'->>'relation',
    'guardian_name',        case when s->'enquirer'->>'relation' in ('father', 'mother', 'parent') then s->'enquirer'->>'name' end,
    'classification',       c.classification,
    'classification_ai',    c.classification,
    'readiness',            c.readiness,
    'eligibility',          c.eligibility,
    'conversation_phase',   s->>'phase',
    'last_intent',          (select string_agg(x, ',') from jsonb_array_elements_text(coalesce(p->'event'->'payload'->'intents', '[]'::jsonb)) x),
    'source',               c.lead_source,
    'channel',              'whatsapp',
    'source_detail',        a->>'kind',
    'campaign',             coalesce(a->>'campaign', a->>'utm_campaign', a->>'parent_campaign'),
    'utm_source',           a->>'utm_source',
    'utm_medium',           a->>'utm_medium',
    'utm_campaign',         a->>'utm_campaign',
    'utm_content',          a->>'utm_content',
    'utm_term',             a->>'utm_term',
    'click_ids',            a->'click_ids',
    'landing_url',          a->>'landing_url',
    'referrer_url',         a->>'referrer',
    'referred_by_code',     a->>'via',
    'access_code',          case when c.access_code in ('LEGACY', 'DIRECT') then null else c.access_code end,
    'ip_address',           a->>'ip',
    'device_type',          a->>'device_type',
    'device_fingerprint',   a->>'fingerprint',
    'consent_sales_at',     c.consent_at,
    -- Addendum 3 PART 7.1: set by Witty when the consent line naming admission partners is shown
    'consent_partner_share_at', case when s->>'consent_partner_share_at' ~ '^\d{4}-\d{2}-\d{2}' then (s->>'consent_partner_share_at')::timestamptz end,
    -- W2.3 (B2C CRM): set by Witty when the consent line covering marketing is shown (version witty-notice-2026-10-v3)
    'consent_marketing_at', case when s->>'consent_marketing_at' ~ '^\d{4}-\d{2}-\d{2}' then (s->>'consent_marketing_at')::timestamptz end,
    'consent_text_version', s->>'consent_text_version',
    -- W3: a student who volunteers "don't share my details" (never asked; recorded so the B2B CRM can keep the lead in-house, rule R8)
    'consent_partner_share_declined_at', case when s->>'consent_partner_share_declined_at' ~ '^\d{4}-\d{2}-\d{2}' then (s->>'consent_partner_share_declined_at')::timestamptz end,
    'is_opted_out',         c.opted_out,
    'first_agent_channel',  'whatsapp',
    'chatwoot_conversation_id', c.conversation_id,
    'is_bot_paused',        c.bot_paused,
    'last_agent_message_at', case when coalesce(p->'log'->>'content', '') <> '' then now() end
  ));
  return jsonb_build_object('source_system', 'witty', 'event_type', p_event, 'idempotency_key', p_key, 'phone', p_phone,
                            'lead', v_lead, 'attribution', a, 'occurred_at', coalesce((a->>'first_click_at')::timestamptz, (a->>'first_message_at')::timestamptz, c.created_at),
                            'is_test', w2_is_test(p_phone));
end $function$;

create or replace function public.w2_blocks_sweep() returns integer language plpgsql as $function$
declare n integer;
begin
  update w2_blocks set unblocked_at = blocked_until, unblocked_by = 'expired'
   where unblocked_at is null and blocked_until is not null and blocked_until < now();
  get diagnostics n = row_count;
  return n;
end $function$;
select w2_blocks_sweep();

-- @section w3_witty_soft_gate_d_referred_by_fix
-- W3 part D: 'direct' and 'ctwa' are binding kinds, not referral codes.
create or replace function public.w2_crm_payload(p_phone text, p_event text, p_key text, p jsonb) returns jsonb language plpgsql stable as $function$
declare
  c  w2_conversations;
  s  jsonb;
  pr jsonb;
  a  jsonb;
  v_lead jsonb;
begin
  select * into c from w2_conversations where phone = p_phone;
  s  := coalesce(c.state, '{}'::jsonb);
  pr := coalesce(s->'profile', '{}'::jsonb);
  a  := coalesce(c.attribution, '{}'::jsonb);
  v_lead := jsonb_strip_nulls(jsonb_build_object(
    'full_name',            w2_pv(pr, 'student_name'),
    'is_name_confirmed',    pr->'student_name'->>'status' = 'confirmed',
    'email',                w2_pv(pr, 'email_id'),
    'is_email_confirmed',   pr->'email_id'->>'status' = 'confirmed',
    'interested_course',    w2_pv(pr, 'interested_course'),
    'interested_specialization', w2_pv(pr, 'specialization'),
    'field_of_interest',    w2_pv(pr, 'field_of_interest'),
    'university_preference', w2_pv(pr, 'university_preference'),
    'interested_university', case when pr->'final_program'->>'status' = 'confirmed' then pr->'final_program'->>'university' end,
    'final_program_id',     case when pr->'final_program'->>'status' = 'confirmed' then pr->'final_program'->>'id' end,
    'final_program_name',   case when pr->'final_program'->>'status' = 'confirmed' then pr->'final_program'->>'program_name' end,
    'final_program_confirmed_at', case when pr->'final_program'->>'status' = 'confirmed' and pr->'final_program'->>'at' ~ '^\d{4}-\d{2}-\d{2}' then (pr->'final_program'->>'at')::timestamptz end,
    'programs_shown',       case when jsonb_typeof(s->'flags'->'shown_rows') = 'array' then s->'flags'->'shown_rows' end,
    'programme_level',      w2_pv(pr, 'program_level'),
    'study_mode_preference', w2_pv(pr, 'study_mode_preference'),
    'highest_qualification', w2_pv(pr, 'highest_qualification'),
    'current_study',        w2_pv(pr, 'current_study'),
    'academic_score_raw',   w2_pv(pr, 'academic_score'),
    'academic_score_pct',   crm_num(w2_pv(pr, 'academic_score')),
    'work_experience_raw',  w2_pv(pr, 'work_experience_years'),
    'work_experience_years_num', crm_num(w2_pv(pr, 'work_experience_years')),
    'current_job_role',     w2_pv(pr, 'current_job_role'),
    'annual_budget_raw',    w2_pv(pr, 'annual_budget'),
    'annual_budget_inr',    crm_num(w2_pv(pr, 'annual_budget')),
    'enrollment_timeline',  w2_pv(pr, 'enrollment_timeline'),
    'primary_motivation',   w2_pv(pr, 'primary_motivation'),
    'location_raw',         w2_pv(pr, 'current_city_country')
  )) || jsonb_strip_nulls(jsonb_build_object(   -- two objects: jsonb_build_object takes at most 100 arguments
    'preferred_language',   s->>'language',
    'enquirer_relation',    s->'enquirer'->>'relation',
    'guardian_name',        case when s->'enquirer'->>'relation' in ('father', 'mother', 'parent') then s->'enquirer'->>'name' end,
    'classification',       c.classification,
    'classification_ai',    c.classification,
    'readiness',            c.readiness,
    'eligibility',          c.eligibility,
    'conversation_phase',   s->>'phase',
    'last_intent',          (select string_agg(x, ',') from jsonb_array_elements_text(coalesce(p->'event'->'payload'->'intents', '[]'::jsonb)) x),
    'source',               c.lead_source,
    'channel',              'whatsapp',
    'source_detail',        a->>'kind',
    'campaign',             coalesce(a->>'campaign', a->>'utm_campaign', a->>'parent_campaign'),
    'utm_source',           a->>'utm_source',
    'utm_medium',           a->>'utm_medium',
    'utm_campaign',         a->>'utm_campaign',
    'utm_content',          a->>'utm_content',
    'utm_term',             a->>'utm_term',
    'click_ids',            a->'click_ids',
    'landing_url',          a->>'landing_url',
    'referrer_url',         a->>'referrer',
    'referred_by_code',     case when a->>'via' in ('direct', 'ctwa') then null else a->>'via' end,
    'access_code',          case when c.access_code in ('LEGACY', 'DIRECT') then null else c.access_code end,
    'ip_address',           a->>'ip',
    'device_type',          a->>'device_type',
    'device_fingerprint',   a->>'fingerprint',
    'consent_sales_at',     c.consent_at,
    'consent_partner_share_at', case when s->>'consent_partner_share_at' ~ '^\d{4}-\d{2}-\d{2}' then (s->>'consent_partner_share_at')::timestamptz end,
    'consent_marketing_at', case when s->>'consent_marketing_at' ~ '^\d{4}-\d{2}-\d{2}' then (s->>'consent_marketing_at')::timestamptz end,
    'consent_text_version', s->>'consent_text_version',
    'consent_partner_share_declined_at', case when s->>'consent_partner_share_declined_at' ~ '^\d{4}-\d{2}-\d{2}' then (s->>'consent_partner_share_declined_at')::timestamptz end,
    'is_opted_out',         c.opted_out,
    'first_agent_channel',  'whatsapp',
    'chatwoot_conversation_id', c.conversation_id,
    'is_bot_paused',        c.bot_paused,
    'last_agent_message_at', case when coalesce(p->'log'->>'content', '') <> '' then now() end
  ));
  return jsonb_build_object('source_system', 'witty', 'event_type', p_event, 'idempotency_key', p_key, 'phone', p_phone,
                            'lead', v_lead, 'attribution', a, 'occurred_at', coalesce((a->>'first_click_at')::timestamptz, (a->>'first_message_at')::timestamptz, c.created_at),
                            'is_test', w2_is_test(p_phone));
end $function$;

-- @section w3_witty_soft_gate_e_ctwa_is_influencer
-- W3 part E (Vikas, 16 Oct): click-to-WhatsApp referrals are influencer leads, not paid Meta leads. Only the referral branch of step 3 changes.
create or replace function public.w2_try_claim(p_phone text, p_run text, p_lease_seconds integer default 45) returns jsonb language plpgsql as $function$
declare
  v_conv   w2_conversations;
  v_msgs   jsonb;
  v_text   text;
  v_access jsonb;
  v_up     jsonb;
  v_bot    jsonb;
  v_rating smallint;
  v_ids    text[];
  v_ref    jsonb;
  v_src    text;
  v_attr   jsonb;
  v_utm    jsonb;
begin
  insert into w2_conversations (phone) values (p_phone) on conflict (phone) do nothing;
  update w2_conversations
     set lock_id = p_run, lock_until = now() + make_interval(secs => p_lease_seconds)
   where phone = p_phone and (lock_until is null or lock_until < now() or lock_id = p_run)
  returning * into v_conv;
  if not found then
    return jsonb_build_object('acquired', false);
  end if;

  with c as (
    update w2_inbox set claimed_by = p_run
     where phone = p_phone and processed_at is null
    returning *
  )
  select coalesce(jsonb_agg(to_jsonb(c) order by c.received_at), '[]'::jsonb) into v_msgs from c;
  select coalesce(array_agg(m->>'message_id'), '{}') into v_ids from jsonb_array_elements(v_msgs) m;
  select string_agg(coalesce(m->>'content', ''), E'\n' order by m->>'received_at') into v_text from jsonb_array_elements(v_msgs) m;

  -- 1. Bots: a blocked number gets no reply at all; its messages are kept for review.
  if cardinality(v_ids) > 0 then
    if w2_is_blocked(p_phone) then
      v_bot := jsonb_build_object('blocked', true, 'reason', 'already blocked');
    else
      v_bot := w2_bot_check(p_phone);
    end if;
    if (v_bot->>'blocked')::boolean then
      update w2_inbox set processed_at = now() where message_id = any(v_ids);
      update w2_messages set kind = 'blocked' where direction = 'in' and message_id = any(v_ids);
      return jsonb_build_object('acquired', true, 'blocked', true, 'bot', v_bot, 'conversation', to_jsonb(v_conv), 'messages', '[]'::jsonb);
    end if;
  end if;

  -- 1b. CRM owns the lead (assigned in-house or sent to a partner): Witty stays silent, the message is logged for the timeline.
  if cardinality(v_ids) > 0 and w2_crm_owned(p_phone) then
    update w2_inbox set processed_at = now() where message_id = any(v_ids);
    update w2_messages set kind = 'crm_paused' where direction = 'in' and message_id = any(v_ids);
    -- W2.2 (B2C CRM): record the unanswered message on the lead, one touchpoint per lead per day; never block Witty.
    begin
      perform lead_intake(jsonb_build_object(
        'source_system', 'witty', 'event_type', 'chat.reenquiry',
        'idempotency_key', p_phone || ':paused:' || to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD'),
        'phone', p_phone, 'lead', '{}'::jsonb));
    exception when others then null;
    end;
    return jsonb_build_object('acquired', true, 'crm_paused', true, 'conversation', to_jsonb(v_conv), 'messages', '[]'::jsonb);
  end if;

  -- 1c. W2.1 (B2C CRM): a chat Witty paused at escalation, whose lead now sits in B2C (allocation in_house, handed_off)
  --     with no counsellor, gets Witty back. escalated_at stays, so Witty never promises a counsellor twice.
  if cardinality(v_ids) > 0 and v_conv.bot_paused and coalesce(v_conv.state->>'paused_by', '') <> 'agent' and exists (
       select 1 from crm_find_lead(p_phone) l
         join b2b.allocations a on a.id = l.allocation_id and a.lead_id = l.id
        where l.id is not null and l.owner_user_id is null
          and a.destination_type = 'in_house' and a.status = 'handed_off') then
    update w2_conversations
       set bot_paused = false, state = coalesce(state, '{}'::jsonb) || jsonb_build_object('bot_paused', false)
     where phone = p_phone
    returning * into v_conv;
  end if;

  -- 1d. W3: a human agent replied in Chatwoot (w2_agent_pause). Witty stays quiet for 4 hours after the pause, then answers again.
  if cardinality(v_ids) > 0 and coalesce(v_conv.state->>'paused_by', '') = 'agent' then
    if coalesce((v_conv.state->>'paused_at')::timestamptz, now()) > now() - interval '4 hours' then
      update w2_inbox set processed_at = now() where message_id = any(v_ids);
      update w2_messages set kind = 'agent_paused' where direction = 'in' and message_id = any(v_ids);
      return jsonb_build_object('acquired', true, 'agent_paused', true, 'conversation', to_jsonb(v_conv), 'messages', '[]'::jsonb);
    end if;
    update w2_conversations
       set bot_paused = false, state = (coalesce(state, '{}'::jsonb) - 'paused_by' - 'paused_at' - 'paused_agent') || jsonb_build_object('bot_paused', false)
     where phone = p_phone
    returning * into v_conv;
  end if;

  -- 2. A one-tap answer to "Was this chat helpful?" is recorded, not answered.
  if cardinality(v_ids) > 0 and v_conv.state ? 'feedback_asked_at' and not coalesce((v_conv.state->>'feedback_done')::boolean, false)
     and (v_conv.state->>'feedback_asked_at')::timestamptz > now() - interval '48 hours' then
    v_rating := w2_parse_rating(v_text);
    if v_rating is not null then
      insert into w2_feedback (phone, source, rating, label, comment, meta)
      values (p_phone, 'student', v_rating, case v_rating when 1 then 'helpful' when -1 then 'not helpful' else 'neutral' end, left(v_text, 500),
              jsonb_build_object('asked_after', v_conv.state->>'feedback_asked_mode'));
      update w2_conversations set state = state || jsonb_build_object('feedback_done', true, 'feedback_rating', v_rating)
       where phone = p_phone returning * into v_conv;
      update w2_inbox set processed_at = now() where message_id = any(v_ids);
      update w2_messages set kind = 'feedback' where direction = 'in' and message_id = any(v_ids);
      return jsonb_build_object('acquired', true, 'feedback', v_rating, 'conversation', to_jsonb(v_conv), 'messages', '[]'::jsonb);
    end if;
  end if;

  -- 3. Access code: attribution only (W3 soft gate, 16 Oct 2026). Every chat becomes a lead on its first message.
  if v_conv.access_code is not null then
    v_access := jsonb_build_object('status', 'verified', 'code', v_conv.access_code, 'source', v_conv.lead_source, 'attribution', v_conv.attribution);
    -- A direct lead that later types a real code is upgraded once, so ad attribution is not lost.
    if v_conv.access_code = 'DIRECT' and cardinality(v_ids) > 0 and v_text ~* '(access|activation)\s*code' then
      v_up := w2_redeem_code(p_phone, v_text);
      if v_up->>'status' = 'ok' and v_up->>'via' in ('code', 'legacy_code') then
        update w2_conversations
           set access_code = v_up->>'code', access_at = now(), lead_source = v_up->>'source',
               attribution = coalesce(attribution, '{}'::jsonb) || coalesce(v_up->'attribution', '{}'::jsonb) || jsonb_build_object('upgraded_from', 'DIRECT')
         where phone = p_phone
        returning * into v_conv;
        v_access := jsonb_build_object('status', 'verified', 'code', v_conv.access_code, 'source', v_conv.lead_source, 'attribution', v_conv.attribution, 'upgraded', true);
      end if;
    end if;
  else
    v_access := w2_redeem_code(p_phone, v_text);
    if v_access->>'status' = 'ok' then
      update w2_conversations
         set access_code = coalesce(v_access->>'code', 'LEGACY'), access_at = now(), lead_source = v_access->>'source',
             attribution = v_access->'attribution'
       where phone = p_phone
      returning * into v_conv;
    else
      if v_access->>'status' in ('invalid', 'taken', 'expired') then
        insert into w2_security_log (phone, kind, detail) values (p_phone, 'bad_code', jsonb_build_object('status', v_access->>'status', 'code', v_access->>'code'));
      end if;
      if cardinality(v_ids) > 0 then
        -- Bind the conversation now: a click-to-WhatsApp referral makes it an influencer lead, otherwise an organic direct lead.
        select referral into v_ref from w2_inbox where phone = p_phone and referral is not null order by received_at limit 1;
        if v_ref is not null then
          v_utm := '{}'::jsonb;
          if coalesce(v_ref->>'source_url', '') ~ 'utm_' then
            select coalesce(jsonb_object_agg(m[1], m[2]), '{}'::jsonb) into v_utm
              from regexp_matches(v_ref->>'source_url', '(utm_[a-z]+)=([^&#]+)', 'g') m;
          end if;
          -- Vikas, 16 Oct: click-to-WhatsApp entries are influencer leads, not paid Meta leads.
          v_src := 'influencer';
          v_attr := jsonb_strip_nulls(jsonb_build_object('kind', 'influencer', 'source', 'influencer', 'via', 'ctwa',
                      'campaign', coalesce(v_utm->>'utm_campaign', v_ref->>'headline', v_ref->>'source_id'), 'landing_url', v_ref->>'source_url',
                      'click_ids', jsonb_strip_nulls(jsonb_build_object('ctwa_clid', v_ref->>'ctwa_clid', 'source_id', v_ref->>'source_id')),
                      'utm_source', coalesce(v_utm->>'utm_source', 'influencer'), 'utm_medium', coalesce(v_utm->>'utm_medium', 'influencer'),
                      'utm_campaign', v_utm->>'utm_campaign', 'utm_content', v_utm->>'utm_content', 'utm_term', v_utm->>'utm_term',
                      'referral', v_ref, 'first_message_at', now()));
        else
          v_src := 'whatsapp_direct';
          v_attr := jsonb_build_object('kind', 'organic', 'source', 'whatsapp_direct', 'via', 'direct', 'first_message_at', now());
        end if;
        update w2_conversations
           set access_code = 'DIRECT', access_at = now(), lead_source = v_src, attribution = v_attr
         where phone = p_phone
        returning * into v_conv;
        if v_access->>'status' in ('invalid', 'taken', 'expired') and coalesce((v_access->>'attempted')::boolean, false) then
          -- the student typed a code that failed: the gateway shows one correction line, and the chat goes on as a direct lead
          v_access := v_access || jsonb_build_object('bound', true, 'source', v_src, 'attribution', v_attr);
        else
          v_access := jsonb_build_object('status', 'ok', 'via', 'direct', 'code', 'DIRECT', 'source', v_src, 'attribution', v_attr);
        end if;
      end if;
    end if;
  end if;

  return jsonb_build_object('acquired', true, 'conversation', to_jsonb(v_conv), 'messages', v_msgs, 'access', v_access,
                            'activation_code', v_access->>'code', 'lead_source', v_conv.lead_source, 'prompts', w2_turn_prompts(),
                            'kb_ready', exists (select 1 from w2_kb_docs d where d.active and d.chunks > 0),
                            'kb_chunks', (select coalesce(sum(d.chunks), 0) from w2_kb_docs d where d.active));
end $function$;

-- @section w3_witty_extractor_prompt_v6
-- @skip data-only: production's statement rewrites the row w2_prompts(name = 'extractor', version 5) into version 6 and
-- copies the old prompt into b2b.witty_backup_20261016. It changes no schema, and it raises "extractor v5 not found" on
-- an empty database, so the replica records the migration without running it.


-- @section w3_witty_health_digest
-- W3: health digest and hourly checks for the Witty Alerts workflow (read-only aggregations; test numbers excluded).
create or replace function public.w2_health_digest(p_hours integer default 24) returns jsonb language sql stable as $function$
with m as (select * from w2_messages where created_at > now() - make_interval(hours => p_hours) and not w2_is_test(phone)),
     o as (select * from m where direction = 'out'),
     c as (select * from w2_conversations where not w2_is_test(phone))
select jsonb_build_object(
  'window_hours', p_hours,
  'turns', (select count(*) from o where kind = 'reply'),
  'inbound', (select count(*) from m where direction = 'in'),
  'numbers', (select count(distinct phone) from m),
  'new_conversations', (select count(*) from c where created_at > now() - make_interval(hours => p_hours)),
  'new_leads_by_source', (select coalesce(jsonb_object_agg(coalesce(lead_source, 'unknown'), n), '{}'::jsonb) from (select lead_source, count(*) n from student_leads where created_at > now() - make_interval(hours => p_hours) and coalesce(is_test, false) = false group by 1) x),
  'direct_chats', (select count(*) from c where access_code = 'DIRECT' and access_at > now() - make_interval(hours => p_hours)),
  'fallback_share', (select round(100.0 * count(*) filter (where reply_source = 'fallback') / greatest(count(*), 1), 1) from o where kind = 'reply'),
  'verify_error_share', (select round(100.0 * count(*) filter (where jsonb_array_length(coalesce(verify_errors, '[]'::jsonb)) > 0) / greatest(count(*), 1), 1) from o where kind = 'reply'),
  'p50_ms', (select percentile_cont(0.5) within group (order by latency_ms) from o where latency_ms is not null),
  'p95_ms', (select percentile_cont(0.95) within group (order by latency_ms) from o where latency_ms is not null),
  'extractor_errors', (select count(*) from w2_events where type = 'turn' and created_at > now() - make_interval(hours => p_hours) and coalesce(payload->>'extractor_error', '') <> ''),
  'escalations', (select count(*) from w2_events where type in ('handoff') and created_at > now() - make_interval(hours => p_hours)),
  'classification_mix', (select coalesce(jsonb_object_agg(coalesce(classification, 'null'), n), '{}'::jsonb) from (select classification, count(*) n from c group by 1) x),
  'consent', jsonb_build_object('sales', (select count(*) from c where consent_at is not null), 'partner', (select count(*) from c where state->>'consent_partner_share_at' is not null), 'marketing', (select count(*) from c where state->>'consent_marketing_at' is not null), 'declined', (select count(*) from c where state->>'consent_partner_share_declined_at' is not null)),
  'agent_takeovers', (select count(*) from w2_events where type = 'agent_takeover' and created_at > now() - make_interval(hours => p_hours)),
  'send_failed', (select count(*) from w2_events where type = 'send_failed' and created_at > now() - make_interval(hours => p_hours)),
  'outbox', jsonb_build_object('pending', (select count(*) from w2_outbox where status = 'pending'), 'failed', (select count(*) from w2_outbox where status = 'failed'), 'sent', (select count(*) from w2_outbox where status = 'sent' and sent_at > now() - make_interval(hours => p_hours))),
  'stale_inbox', (select count(*) from w2_stale_inbox(300)),
  'blocks_open', (select count(*) from w2_blocks where unblocked_at is null),
  'nurture_sent', (select count(*) from w2_nurture_log where status = 'sent' and created_at > now() - make_interval(hours => p_hours)),
  'prompt_source', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select coalesce(meta->'prompt_source'->>'counselor', 'n/a') k, count(*) n from o where kind = 'reply' group by 1) x),
  'caches_valid', (select bool_and(expire_at > now()) from w2_gemini_caches),
  'kb_chunks', (select coalesce(sum(chunks), 0) from w2_kb_docs where active),
  'generated_at', now()
);
$function$;

create or replace function public.w2_health_alerts() returns jsonb language sql stable as $function$
select coalesce(jsonb_agg(x), '[]'::jsonb) from (
  select 'outbox_failed' as alert, count(*)::text as detail from w2_outbox where status = 'failed' having count(*) > 0
  union all
  select 'stale_inbox', count(*)::text from w2_stale_inbox(300) having count(*) > 0
  union all
  select 'send_failed_last_hour', count(*)::text from w2_events where type = 'send_failed' and created_at > now() - interval '1 hour' having count(*) > 0
  union all
  select 'extractor_error_rate', round(100.0 * count(*) filter (where coalesce(payload->>'extractor_error', '') <> '') / greatest(count(*), 1), 0)::text || '%'
    from w2_events where type = 'turn' and created_at > now() - interval '1 hour'
   having count(*) >= 5 and count(*) filter (where coalesce(payload->>'extractor_error', '') <> '') * 5 > count(*)
  union all
  select 'cache_expired', name from w2_gemini_caches where expire_at < now()
  union all
  select 'fallback_rate_last_hour', round(100.0 * count(*) filter (where reply_source = 'fallback') / greatest(count(*), 1), 0)::text || '%'
    from w2_messages where direction = 'out' and kind = 'reply' and created_at > now() - interval '1 hour' and not w2_is_test(phone)
   having count(*) >= 5 and count(*) filter (where reply_source = 'fallback') * 4 > count(*)
) x;
$function$;
select w2_health_digest(24) as digest, w2_health_alerts() as alerts;

-- @section w3_witty_send_failed
-- W3: a reply Chatwoot could not send. The log row is marked unsent, the consent stamped on that reply is withdrawn, and an event is kept for the alerts.
create or replace function public.w2_send_failed(p_phone text, p_run text, p_error text) returns jsonb language plpgsql as $function$
declare n int; v_withdrawn boolean := false;
begin
  update w2_messages set sent = false, meta = coalesce(meta, '{}'::jsonb) || jsonb_build_object('send_error', left(coalesce(p_error, ''), 500))
   where phone = p_phone and run_id = p_run and direction = 'out';
  get diagnostics n = row_count;
  update w2_conversations
     set consent_at = null,
         state = (state - 'consent_at' - 'consent_partner_share_at' - 'consent_marketing_at' - 'consent_text_version')
   where phone = p_phone and state->'flags'->>'consent_set_run' = p_run;
  if found then v_withdrawn := true; end if;
  insert into w2_events (phone, type, run_id, payload) values (p_phone, 'send_failed', p_run, jsonb_build_object('error', left(coalesce(p_error, ''), 500), 'consent_withdrawn', v_withdrawn));
  return jsonb_build_object('messages_marked', n, 'consent_withdrawn', v_withdrawn);
end $function$;

-- @section w3b_search_programs_emi_fields
-- W3b: programme rows carry EMI, pay-after-placement and loan hints so Witty can present them (Vikas, 16 Oct). Backup first.
insert into b2b.witty_backup_20261016 (kind, name, def, saved_at)
select 'function', 'w2_search_programs', pg_get_functiondef('public.w2_search_programs(jsonb)'::regprocedure), now();

do $$
declare d text; n int;
  old_cols constant text := 'p.min_qualification, p.min_pct_general, p.min_pct_reserved, p.brochure_url, p.dual,';
  new_cols constant text := 'p.min_qualification, p.min_pct_general, p.min_pct_reserved, p.brochure_url, p.dual,
             nullif(regexp_replace(coalesce(p.fee_other->>''Emi'', ''''), ''[^0-9.]'', '''', ''g''), '''')::numeric as fee_emi,
             (p.fee_other ?| array[''Pay After Placement Fees'', ''Fees After Placement Fees'', ''Program Fees (after Placement Fees)'', ''Pay After Placemnet Fees'']) as pay_after_placement,
             (coalesce(p.eligibility_text, '''') ~* ''loan'') as loan_available,';
begin
  d := pg_get_functiondef('public.w2_search_programs(jsonb)'::regprocedure);
  n := (length(d) - length(replace(d, old_cols, ''))) / length(old_cols);
  if n <> 2 then raise exception 'expected 2 column lists, found %', n; end if;
  d := replace(d, old_cols, new_cols);
  execute d;
end $$;

insert into w2_meta (key, value) values ('catalog_version', '2'::jsonb)
on conflict (key) do update set value = to_jsonb(coalesce((w2_meta.value #>> '{}')::int, 1) + 1);

select (w2_search_programs('{"course":"mba"}'::jsonb)->'rows'->0) - 'university' - 'program_name' as sample_row;

-- @section w3b_nurture_due_context
-- W3b (Vikas, 16 Oct): the 3-hour re-engagement message is written for where the student left off. w2_nurture_due now returns that context.
insert into b2b.witty_backup_20261016 (kind, name, def, saved_at)
select 'function', 'w2_nurture_due', pg_get_functiondef('public.w2_nurture_due(integer)'::regprocedure), now();

create or replace function public.w2_nurture_due(p_limit integer default 100) returns jsonb language plpgsql as $function$
declare
  v jsonb;
  v_hour int := extract(hour from now() at time zone 'Asia/Kolkata');
begin
  if v_hour < 9 or v_hour >= 20 then
    return '[]'::jsonb;
  end if;
  with due as (
    select phone from w2_conversations
     where nurture_next_at <= now() and not opted_out and not bot_paused and access_code is not null
       and classification in ('UNQUALIFIED', 'PROGRAM_MISMATCH') and not w2_is_test(phone)
       -- routed by the B2B CRM (partner or B2C): the B2C CRM owns outbound nurture from here (Addendum 3, Amendment 1)
       and not exists (select 1 from crm_find_lead(phone) l where l.id is not null and l.destination_type is not null)
     order by nurture_next_at
     limit p_limit
     for update skip locked
  ), upd as (
    update w2_conversations c set nurture_next_at = now() + interval '30 minutes'   -- lease while the worker sends
      from due where c.phone = due.phone
    returning c.phone, c.conversation_id, c.account_id, c.nurture_step + 1 as step, c.last_student_at, c.state, c.lead_source, c.classification, c.eligibility, c.pending_question
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'phone', phone, 'conversation_id', conversation_id, 'account_id', account_id, 'step', step, 'lead_source', lead_source,
           'within_24h', last_student_at > now() - interval '23 hours 30 minutes',
           'idle_minutes', floor(extract(epoch from (now() - coalesce(last_student_at, now()))) / 60),
           'name', split_part(coalesce(state->'profile'->'student_name'->>'value', ''), ' ', 1),
           'course', state->'profile'->'interested_course'->>'value',
           'specialization', state->'profile'->'specialization'->>'value',
           'final_program', case when state->'profile'->'final_program'->>'status' = 'confirmed' then state->'profile'->'final_program' end,
           'language', coalesce(state->>'language', 'english'),
           'ask', coalesce(pending_question, state->>'pending_question', 'NONE'),
           'ask_text', state->>'last_ask_text',
           'enquirer', state->'enquirer',
           'classification', classification, 'eligibility', eligibility,
           'programs_shown', coalesce(state->'flags'->>'programs_shown_key', '') <> '',
           'program_count', coalesce((state->'flags'->>'last_program_count')::int, 0),
           'has_email', state->'profile'->'email_id'->>'status' = 'confirmed',
           'has_name', state->'profile'->'student_name'->>'status' = 'confirmed',
           'turns', coalesce((state->>'turn_count')::int, 0),
           'sent_30d', (select count(*) from w2_nurture_log l where l.phone = upd.phone and l.status = 'sent' and l.created_at > now() - interval '30 days')
         )), '[]'::jsonb) into v from upd;
  return v;
end $function$;

-- @section spark_b46_health_timer_calls
-- B2C CRM b46: the health check's "app answering the timers" row counts only Spark's own timer calls.
create table if not exists b2c.job_calls (one boolean primary key default true check (one), calls jsonb not null default '[]'::jsonb);
alter table b2c.job_calls enable row level security;
insert into b2c.job_calls (one) values (true) on conflict do nothing;

create or replace function b2c.job_call(p_path text) returns bigint language plpgsql security definer set search_path = '' as $f$
declare v_base text := b2c.setting('app') ->> 'base_url'; v_key text; v_id bigint; v_calls jsonb;
begin
  if v_base is null then return null; end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'b2c_internal_key';
  if v_key is null then return null; end if;
  v_id := net.http_post(url := rtrim(v_base, '/') || p_path, body := '{}'::jsonb,
                        headers := jsonb_build_object('content-type', 'application/json', 'x-internal-key', v_key), timeout_milliseconds := 55000);
  select coalesce(c.calls, '[]'::jsonb) || jsonb_build_array(jsonb_build_object('id', v_id, 'path', p_path, 'at', now())) into v_calls from b2c.job_calls c;
  if v_calls is null then v_calls := jsonb_build_array(jsonb_build_object('id', v_id, 'path', p_path, 'at', now())); end if;
  if jsonb_array_length(v_calls) > 600 then
    select jsonb_agg(e order by n) into v_calls from jsonb_array_elements(v_calls) with ordinality as t(e, n) where n > jsonb_array_length(v_calls) - 600;
  end if;
  insert into b2c.job_calls (one, calls) values (true, v_calls) on conflict (one) do update set calls = excluded.calls;
  return v_id;
end $f$;
revoke execute on function b2c.job_call(text) from public, authenticated;

create or replace function b2c.system_health() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_jobs jsonb := '[]'::jsonb; v_calls jsonb := null; v_ai jsonb; v_checks jsonb := '[]'::jsonb; v_live boolean;
        n_out_q int; n_out_bad int; t_out_old timestamptz; n_sq_q int; n_sq_held int; n_sq_bad int; t_sq_old timestamptz;
        n_in_err int; n_in_stale int; n_unassigned int; n_replies int; n_unlogged int; n_wa_fail int; t_batch timestamptz; t_event timestamptz;
        v_base text := b2c.setting('app') ->> 'base_url'; v_keyed boolean; v_app_level text; v_app_detail text;
begin
  if b2c.my_role() is distinct from 'admin' then raise exception 'not allowed' using errcode = '42501'; end if;
  -- timers
  if to_regclass('cron.job') is not null then
    if to_regclass('cron.job_run_details') is not null then
      -- cron.job_run_details has no index but its primary key and can hold hundreds of thousands of rows: read only the newest 20,000 runs, once.
      execute $q$with recent as materialized (
                   select distinct on (r.jobid) r.jobid, r.status, r.start_time, r.end_time, r.return_message from cron.job_run_details r
                    where r.runid > coalesce((select max(x.runid) from cron.job_run_details x), 0) - 20000 order by r.jobid, r.start_time desc)
                 select coalesce(jsonb_agg(jsonb_build_object('name', j.jobname, 'schedule', j.schedule, 'last_status', d.status, 'last_start', d.start_time,
                                                              'last_end', d.end_time, 'message', left(d.return_message, 200)) order by j.jobname), '[]'::jsonb)
                   from cron.job j left join recent d on d.jobid = j.jobid
                  where j.jobname like 'b2c-%'$q$ into v_jobs;
    else
      execute $q$select coalesce(jsonb_agg(jsonb_build_object('name', j.jobname, 'schedule', j.schedule) order by j.jobname), '[]'::jsonb) from cron.job j where j.jobname like 'b2c-%'$q$ into v_jobs;
    end if;
  end if;
  -- the app's answers to the timers: only the calls b2c.job_call made (the database is shared, so net._http_response also holds
  -- other apps' calls); pg_net keeps responses for a few hours and b2c.job_calls the last 600 request ids.
  select exists (select 1 from vault.decrypted_secrets where name = 'b2c_internal_key') into v_keyed;
  if v_base is null or not v_keyed then
    v_app_level := 'warn'; v_app_detail := 'the timers are not pointed at the site yet: run the deploy script (developer handover, step 5.2)';
  elsif to_regclass('net._http_response') is null then
    v_app_level := 'warn'; v_app_detail := 'no record of calls (pg_net is not installed)';
  else
    execute $q$with ids as (select (e ->> 'id')::bigint as id, (e ->> 'at')::timestamptz as at from b2c.job_calls c, jsonb_array_elements(c.calls) e)
                 select jsonb_build_object('last_at', max(r.created),
                          'failed_last_hour', count(r.id) filter (where r.created > now() - interval '1 hour' and (r.status_code is null or r.status_code >= 400)),
                          'ok_last_hour', count(r.id) filter (where r.created > now() - interval '1 hour' and r.status_code < 400),
                          'unanswered_last_hour', count(*) filter (where r.id is null and ids.at > now() - interval '1 hour' and ids.at < now() - interval '3 minutes'),
                          'calls_last_hour', count(*) filter (where ids.at > now() - interval '1 hour'))
                   from ids left join net._http_response r on r.id = ids.id$q$ into v_calls;
    v_app_level := case when (v_calls ->> 'failed_last_hour')::int > 0 then 'bad'
                        when (v_calls ->> 'unanswered_last_hour')::int > 0 then 'warn'
                        when v_calls ->> 'last_at' is null then 'warn' else 'ok' end;
    v_app_detail := coalesce(v_calls ->> 'ok_last_hour', '0') || ' ok, ' || coalesce(v_calls ->> 'failed_last_hour', '0') || ' failed and '
                    || coalesce(v_calls ->> 'unanswered_last_hour', '0') || ' unanswered in the last hour'
                    || case when v_calls ->> 'last_at' is null then ' (no answer recorded yet)' else '' end;
  end if;
  -- queues and feeds
  select count(*) filter (where status = 'queued'), count(*) filter (where status in ('failed', 'refused', 'conflict') and created_at > now() - interval '7 days'),
         min(created_at) filter (where status = 'queued') into n_out_q, n_out_bad, t_out_old from b2c.outbox;
  select count(*) filter (where status = 'queued'), count(*) filter (where status = 'held'), count(*) filter (where status = 'failed' and created_at > now() - interval '24 hours'),
         min(not_before) filter (where status = 'queued') into n_sq_q, n_sq_held, n_sq_bad, t_sq_old from b2c.send_queue;
  select count(*) filter (where status = 'error'), count(*) filter (where status = 'stored' and received_at < now() - interval '10 minutes') into n_in_err, n_in_stale from b2c.inbox;
  select max(sent_at) into t_batch from b2c.outbox where status = 'applied';
  select max(received_at) into t_event from b2c.inbox;
  select count(*) into n_wa_fail from b2c.wa_messages where direction = 'out' and status = 'failed' and created_at > now() - interval '24 hours';
  -- waiting for a person
  select count(*) into n_unassigned from b2c.leads_state where status = 'active' and owner_id is null and lane = 'sales' and deleted_at is null and not is_test;
  select count(*) into n_replies from b2c.replies where status = 'inbox';
  select count(*) into n_unlogged from b2c.calls where logged_at is null and unlogged_flagged_at is not null and tapped_at > now() - interval '24 hours';
  v_ai := jsonb_build_object('spent_today', b2c.ai_spent_today(), 'cap', (b2c.setting('ai') ->> 'daily_cap_inr')::numeric,
                             'failed_today', (select count(*) from b2c.ai_calls where not ok and at > now() - interval '24 hours'));
  v_live := coalesce((b2c.setting('live_mode') ->> 'whatsapp')::boolean, false) or coalesce((b2c.setting('live_mode') ->> 'email')::boolean, false);
  -- the checks, each with a level
  v_checks := v_checks
    || jsonb_build_object('key', 'timers', 'label', 'Database timers', 'level', case when jsonb_array_length(v_jobs) = 0 then 'bad'
                            when exists (select 1 from jsonb_array_elements(v_jobs) j where j ->> 'last_status' = 'failed') then 'bad'
                            when exists (select 1 from jsonb_array_elements(v_jobs) j where j ->> 'name' = 'b2c-minute' and coalesce((j ->> 'last_start')::timestamptz, now() - interval '1 day') < now() - interval '10 minutes') then 'warn'
                            else 'ok' end,
                          'detail', jsonb_array_length(v_jobs) || ' timers' || coalesce('; last minute tick ' || (select j ->> 'last_start' from jsonb_array_elements(v_jobs) j where j ->> 'name' = 'b2c-minute'), ''))
    || jsonb_build_object('key', 'app', 'label', 'The app answering the timers', 'level', v_app_level, 'detail', v_app_detail)
    || jsonb_build_object('key', 'outbox', 'label', 'Changes to the master lead table', 'level', case when n_out_bad > 0 then 'bad' when t_out_old < now() - interval '30 minutes' then 'warn' else 'ok' end,
                          'detail', n_out_q || ' waiting, ' || n_out_bad || ' failed or refused this week' || coalesce(', last batch ' || t_batch::text, ''))
    || jsonb_build_object('key', 'inbox', 'label', 'Events from the master lead table', 'level', case when n_in_err > 0 then 'bad' when n_in_stale > 0 then 'warn' else 'ok' end,
                          'detail', n_in_err || ' with errors, ' || n_in_stale || ' not yet applied' || coalesce(', last event ' || t_event::text, ''))
    || jsonb_build_object('key', 'sending', 'label', 'WhatsApp and email sending', 'level', case when n_sq_bad > 0 or n_wa_fail > 0 then 'bad' when t_sq_old < now() - interval '15 minutes' then 'warn' else 'ok' end,
                          'detail', n_sq_q || ' queued, ' || n_sq_held || ' held, ' || n_sq_bad || ' failed in 24 h; live mode ' || case when v_live then 'on' else 'off' end)
    || jsonb_build_object('key', 'ai', 'label', 'Claude', 'level', case when (v_ai ->> 'failed_today')::int > 0 then 'warn' when (v_ai ->> 'spent_today')::numeric >= coalesce((v_ai ->> 'cap')::numeric, 0) and coalesce((v_ai ->> 'cap')::numeric, 0) > 0 then 'warn' else 'ok' end,
                          'detail', '₹' || round((v_ai ->> 'spent_today')::numeric) || ' of ₹' || coalesce(v_ai ->> 'cap', '0') || ' today, ' || (v_ai ->> 'failed_today') || ' failed calls')
    || jsonb_build_object('key', 'people', 'label', 'Waiting for a person', 'level', case when n_unassigned > 0 then 'bad' when n_replies > 0 or n_unlogged > 0 then 'warn' else 'ok' end,
                          'detail', n_unassigned || ' unassigned sales leads, ' || n_replies || ' replies to answer, ' || n_unlogged || ' calls not logged in 24 h');
  return jsonb_build_object('at', now(), 'checks', v_checks, 'jobs', v_jobs, 'calls', v_calls, 'ai', v_ai,
                            'overall', case when exists (select 1 from jsonb_array_elements(v_checks) c where c ->> 'level' = 'bad') then 'bad'
                                            when exists (select 1 from jsonb_array_elements(v_checks) c where c ->> 'level' = 'warn') then 'warn' else 'ok' end);
end $f$;

-- @section b2b_tmp_transfer
-- Reconstructed from production's catalog (created by hand, no migration; b2b-crm/supabase/pending/drop_tmp_transfer.sql
-- would drop it but is not applied). A short-lived hand-over table for a one-off data transfer.
create table if not exists public.b2b_tmp_transfer (
  token text not null,
  payload text not null,
  created_at timestamp with time zone default now(),
  constraint b2b_tmp_transfer_pkey PRIMARY KEY (token)
);
alter table public.b2b_tmp_transfer enable row level security;
revoke all on table public.b2b_tmp_transfer from anon, authenticated;

CREATE OR REPLACE FUNCTION public.b2b_tmp_transfer_get(p_token text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select payload from public.b2b_tmp_transfer where token = p_token and created_at > now() - interval '2 hours';
$function$;
revoke all on function public.b2b_tmp_transfer_get(text) from public, anon, authenticated;
grant execute on function public.b2b_tmp_transfer_get(text) to service_role;


-- @section backup_tables
-- The *_backup_YYYYMMDD tables in public (copies made by hand before risky changes, 1 to 5 Oct 2026), reconstructed from
-- production's catalog: each is an ordered subset of today's source table (verified on production: same names, types and
-- order), so it is rebuilt empty with CREATE TABLE AS ... WITH NO DATA from the source minus the columns added after the copy.
-- Run at the end of the build, when the source tables have their final columns. No rows.
do $bk$
declare r record; v_cols text;
begin
  for r in select * from (values
    ('engine_decisions_backup_20261004', ''),
    ('student_leads_backup_20261001', 'alternate_phone,phone_verified_at,phone_verification_method,email_verified_at,preferred_language,city,state,country,enquirer_relation,guardian_name,guardian_phone,interested_specialization,field_of_interest,interested_university,current_study,academic_score_pct,annual_budget_inr,work_experience_years_num,programme_segment,channel,source_detail,campaign,utm_source,utm_medium,utm_campaign,utm_content,utm_term,click_ids,landing_url,referrer_url,referred_by_code,publisher_id,first_touch_at,last_touch_at,last_touch_source,consent_sales_at,consent_marketing_at,consent_partner_share_at,consent_text_version,is_opted_out,opted_out_at,opted_out_channels,email_bounced_at,stage,sub_stage,stage_changed_at,temperature,lead_score,is_sales_ready,sales_ready_at,owner_user_id,team_id,assigned_at,first_contacted_at,last_contacted_at,last_activity_at,contact_attempts,next_task_due_at,lost_reason,lost_at,cycle_no,reopened_at,is_duplicate_suspect,merged_into_id,destination_type,partner_id,allocation_id,allocated_at,allocation_reason,partner_record_id,partner_stage_raw,partner_sub_stage_raw,partner_synced_at,duplicate_claim_count,application_id,application_status,applied_at,fee_amount_inr,fee_paid_inr,enrollment_status,enrollment_verified_at,expected_net_revenue_inr,realised_net_revenue_inr,active_journey_id,last_campaign_id,last_marketing_message_at,first_agent_channel,chatwoot_conversation_id,web_session_id,is_bot_paused,last_agent_message_at,portal_user_id,open_ticket_count,custom_fields,zoho_lead_id,is_test,updated_at,updated_by,deleted_at,anonymised_at,sla_alerted_at,score_updated_at,partner_stale_at'),
    ('student_leads_backup_20261002', 'partner_stale_at'),
    ('student_leads_backup_20261004', 'partner_stale_at'),
    ('student_leads_backup_20261005', 'partner_stale_at'),
    ('touchpoints_backup_20261004', ''),
    ('touchpoints_backup_20261005', ''),
    ('w2_conversations_backup_20261004', ''),
    ('w2_conversations_backup_20261005', ''),
    ('w2_events_backup_20261004', ''),
    ('w2_events_backup_20261005', ''),
    ('w2_fact_log_backup_20261004', ''),
    ('w2_fact_log_backup_20261005', ''),
    ('w2_inbox_backup_20261004', 'referral'),
    ('w2_inbox_backup_20261005', 'referral'),
    ('w2_messages_backup_20261004', ''),
    ('w2_messages_backup_20261005', ''),
    ('w2_nurture_log_backup_20261004', ''),
    ('w2_outbox_backup_20261004', '')) as b(backup_name, missing) loop
    select string_agg(format('%I', a.attname), ', ' order by a.attnum) into v_cols
      from pg_attribute a
     where a.attrelid = ('public.' || regexp_replace(r.backup_name, '_backup_[0-9]+$', ''))::regclass and a.attnum > 0 and not a.attisdropped
       and a.attname <> all (string_to_array(r.missing, ','));
    execute format('create table if not exists public.%I as select %s from public.%I with no data', r.backup_name, v_cols,
                   regexp_replace(r.backup_name, '_backup_[0-9]+$', ''));
    execute format('alter table public.%I enable row level security', r.backup_name);
  end loop;
end $bk$;


-- @section catalog_drift
-- public.match_documents(vector,integer,jsonb): production body md5 43b8cfa7cf518cc17b6d745d4b3c4a6b
CREATE OR REPLACE FUNCTION public.match_documents(query_embedding vector, match_count integer DEFAULT NULL::integer, filter jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(id bigint, content text, metadata jsonb, similarity double precision)
 LANGUAGE plpgsql
AS $function$
begin
  return query
  select
    course_directory.id,
    course_directory.content,
    course_directory.metadata,
    1 - (course_directory.embedding <=> query_embedding) as similarity
  from course_directory
  where course_directory.metadata @> filter
  order by course_directory.embedding <=> query_embedding
  limit match_count;
end;
$function$;

-- public.current_referral_code(): production body md5 4a80a3c0829361751a63484186aac42e
CREATE OR REPLACE FUNCTION public.current_referral_code()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select referral_code
  from public.influencers
  where auth_uid = auth.uid() and status = 'active'
$function$;

-- public.is_admin(): production body md5 ea346f4d3c95199f46f9927c4f028d05
CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(auth.jwt() ->> 'email', '') = 'connect@eduwit.in'
$function$;

-- public.match_eduwit_knowledge_base(vector,integer,jsonb): production body md5 530d5981e056871f8da60568d67805a3
CREATE OR REPLACE FUNCTION public.match_eduwit_knowledge_base(query_embedding vector, match_count integer DEFAULT NULL::integer, filter jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(id bigint, content text, metadata jsonb, similarity double precision)
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
begin
  return query
  select
    id,
    content,
    metadata,
    1 - (eduwit_knowledge_base.embedding <=> query_embedding) as similarity
  from eduwit_knowledge_base
  where metadata @> filter
  order by eduwit_knowledge_base.embedding <=> query_embedding
  limit match_count;
end;
$function$;

-- public.influencer_dashboard_leads(text,text): production body md5 cd7ca2e9f14eb66a3cf29ef900bf64a0
CREATE OR REPLACE FUNCTION public.influencer_dashboard_leads(p_referral_code text, p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_code  text := trim(coalesce(p_referral_code, ''));
  v_fails int;
  v_ok    boolean;
begin
  if v_code = '' or coalesce(p_password, '') = '' or length(v_code) > 64 or length(p_password) > 128 then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;

  select count(*) into v_fails
    from influencer_login_attempts
   where referral_code = v_code and not ok and at > now() - interval '15 minutes';
  if v_fails >= 5 then
    return jsonb_build_object('ok', false, 'error', 'too_many_attempts');
  end if;

  select exists (select 1 from influencer_auth a
                  where a.referral_code = v_code and a.secret_password = p_password)
    into v_ok;
  insert into influencer_login_attempts (referral_code, ok) values (v_code, v_ok);
  if not v_ok then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;

  return jsonb_build_object('ok', true, 'leads', coalesce((
    select jsonb_agg(jsonb_build_object(
             'student_name',        l.student_name,
             'phone_masked',        case when l.whatsapp_number is null then null
                                         else '••••••' || right(regexp_replace(l.whatsapp_number, '\D', '', 'g'), 4) end,
             'email_masked',        case when l.email_id is null or position('@' in l.email_id) = 0 then null
                                         else left(l.email_id, 1) || '•••@' || split_part(l.email_id, '@', 2) end,
             'lead_status',         l.lead_status,
             'interested_course',   l.interested_course,
             'lead_stage',          l.lead_stage,
             'enrolled_program',    l.enrolled_program,
             'enrolled_university', l.enrolled_university,
             'enrollment_date',     l.enrollment_date,
             'created_at',          l.created_at)
           order by l.created_at desc)
      from student_leads l
     where l.referral_code = v_code
       and l.deleted_at is null and l.merged_into_id is null
       and not coalesce(l.is_test, false)), '[]'::jsonb));
end $function$;

-- b2b.set_setting(text,jsonb,text): production body md5 c2aaae65d4bfed9538df288e9d83b909
CREATE OR REPLACE FUNCTION b2b.set_setting(p_key text, p_value jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  a jsonb := b2b.actor();
  v int;
begin
  if a ->> 'type' = 'admin' and not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required for every settings change'; end if;
  if p_value is null or jsonb_typeof(p_value) not in ('object', 'array') then
    raise exception 'setting % must be a JSON object or array', p_key;
  end if;
  if a ->> 'type' <> 'system' and not exists (select 1 from b2b.settings s where s.key = p_key) then
    raise exception 'unknown setting %', p_key;
  end if;
  insert into b2b.settings (key, value, actor_type, actor_id) values (p_key, p_value, a ->> 'type', a ->> 'id')
  on conflict (key) do update set value = excluded.value, version = b2b.settings.version + 1, updated_at = now(),
                                  actor_type = excluded.actor_type, actor_id = excluded.actor_id
  returning version into v;
  insert into b2b.settings_versions (key, version, value, reason, actor_type, actor_id)
  values (p_key, v, p_value, p_reason, a ->> 'type', a ->> 'id');
  perform b2b.log_event('settings.changed', null, null, null, jsonb_build_object('key', p_key, 'version', v, 'reason', p_reason));
  return jsonb_build_object('key', p_key, 'version', v);
end $function$;

-- b2b.create_api_key(text,text[]): production body md5 ed36f0ea730f25af3f2c16d809e53ff7
CREATE OR REPLACE FUNCTION b2b.create_api_key(p_name text, p_scopes text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_key text := 'eb2b_' || encode(extensions.gen_random_bytes(24), 'hex');
  v_id  bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into b2b.api_keys (name, scopes, key_prefix, key_hash, created_by)
  values (p_name, p_scopes, left(v_key, 12), encode(extensions.digest(v_key, 'sha256'), 'hex'), auth.uid())
  returning id into v_id;
  perform b2b.log_event('api_key.created', null, null, null, jsonb_build_object('api_key_id', v_id, 'name', p_name, 'scopes', p_scopes));
  return jsonb_build_object('id', v_id, 'key', v_key);
end $function$;

-- b2b.leads_restore(bigint[]): production body md5 738e886b6279362ba7f7ad5713577ba6
CREATE OR REPLACE FUNCTION b2b.leads_restore(p_ids bigint[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_batch   uuid := gen_random_uuid();
  v_a       jsonb := b2b.actor();
  v_blocked jsonb;
  v_done    bigint[];
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if cardinality(p_ids) is null or cardinality(p_ids) = 0 then return jsonb_build_object('restored', '[]'::jsonb, 'blocked', '[]'::jsonb); end if;
  if cardinality(p_ids) > 500 then raise exception 'at most 500 leads per restore'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'why', 'a newer lead with this phone exists')), '[]')
    into v_blocked
    from public.student_leads l
   where l.id = any (p_ids) and l.deleted_at is not null
     and exists (select 1 from public.student_leads o
                  where o.id <> l.id and o.deleted_at is null and o.merged_into_id is null
                    and regexp_replace(coalesce(o.whatsapp_number, ''), '\D', '', 'g') = regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g'));

  with upd as (
    update public.student_leads l
       set deleted_at = null, updated_by = 'b2b'
     where l.id = any (p_ids) and l.deleted_at is not null
       and not exists (select 1 from public.student_leads o
                        where o.id <> l.id and o.deleted_at is null and o.merged_into_id is null
                          and regexp_replace(coalesce(o.whatsapp_number, ''), '\D', '', 'g') = regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g'))
    returning l.id
  )
  select coalesce(array_agg(id), '{}') into v_done from upd;

  insert into b2b.lead_deletions (lead_id, action, reason, batch_id, actor_type, actor_id)
  select id, 'restore', null, v_batch, v_a ->> 'type', v_a ->> 'id' from unnest(v_done) id;
  insert into b2b.events (type, lead_id, actor_type, actor_id, payload)
  select 'lead.restored', id, v_a ->> 'type', v_a ->> 'id', jsonb_build_object('batch_id', v_batch) from unnest(v_done) id;

  return jsonb_build_object('restored', to_jsonb(v_done), 'blocked', v_blocked);
end $function$;

-- b2b.programme_match_version(bigint): production body md5 c1e46073ead3ba006735ab7036e9fff4
CREATE OR REPLACE FUNCTION b2b.programme_match_version(p_version_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_partner bigint;
  r record;
  v_uni bigint;
  v_ck text;
  v_spec text;
  v_ids bigint[];
  v_prev bigint;
  v_cands jsonb;
  v_best numeric;
begin
  select partner_id into v_partner from b2b.partner_programme_versions where id = p_version_id;

  for r in select * from b2b.partner_programme_rows where version_id = p_version_id and review_status not in ('approved', 'ignored') loop
    v_uni := b2b.match_university(r.norm ->> 'university');
    v_ck := b2b.match_course_key(r.norm ->> 'course');
    v_spec := b2b.norm_key(coalesce(nullif(r.norm ->> 'specialization', ''), 'General'));

    if jsonb_array_length(coalesce(r.norm -> 'errors', '[]')) > 0 then
      update b2b.partner_programme_rows set programme_id = null, match_method = null, confidence = null, candidates = '[]', review_status = 'no_match'
       where id = r.id;
      continue;
    end if;

    select pr.programme_id into v_prev
      from b2b.partner_programme_rows pr join b2b.partner_programme_versions pv on pv.id = pr.version_id
     where pv.partner_id = v_partner and pv.id <> p_version_id and pr.match_sig = r.match_sig
       and pr.review_status in ('auto', 'approved') and pr.programme_id is not null
       and exists (select 1 from public.catalog_programs c where c.id = pr.programme_id and c.active)
     order by pv.version_no desc, pr.id desc limit 1;
    if v_prev is not null then
      update b2b.partner_programme_rows set programme_id = v_prev, match_method = 'previous', confidence = 1, candidates = '[]', review_status = 'auto'
       where id = r.id;
      continue;
    end if;

    select array_agg(c.id order by c.id) into v_ids
      from public.catalog_programs c
     where c.active and c.university_id = v_uni and c.course_key = v_ck
       and lower(c.mode) = lower(r.norm ->> 'mode')
       and (r.norm ->> 'level' is null or c.level = r.norm ->> 'level')
       and b2b.norm_key(coalesce(nullif(c.specialization, ''), 'General')) = v_spec;
    if cardinality(v_ids) = 1 then
      update b2b.partner_programme_rows set programme_id = v_ids[1], match_method = 'exact', confidence = 1, candidates = '[]', review_status = 'auto'
       where id = r.id;
      continue;
    end if;

    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'score', round(x.score::numeric, 3)) order by x.score desc), '[]'), max(x.score)
      into v_cands, v_best
      from (
        select c.id,
               greatest(public.similarity(lower(c.specialization), lower(coalesce(nullif(r.norm ->> 'specialization', ''), 'general'))),
                        public.similarity(lower(c.program_name), lower(coalesce(r.norm ->> 'programme_name', concat_ws(' ', r.norm ->> 'course', r.norm ->> 'specialization')))))
               + case when lower(c.mode) = lower(r.norm ->> 'mode') then 0.1 else 0 end
               + case when cardinality(v_ids) > 1 and c.id = any (v_ids) then 0.5 else 0 end as score
          from public.catalog_programs c
         where c.active and c.university_id = v_uni and (v_ck is null or c.course_key = v_ck)
         order by score desc limit 5
      ) x;

    update b2b.partner_programme_rows
       set programme_id = case when v_best >= 0.45 then (v_cands -> 0 ->> 'id')::bigint end,
           match_method = case when v_best >= 0.45 then 'fuzzy' end,
           confidence = case when v_best is not null then least(v_best, 0.999) end,
           candidates = v_cands,
           review_status = case when v_best >= 0.45 then 'needs_review' else 'no_match' end
     where id = r.id;
  end loop;
end $function$;

-- b2b.b2c_sync_lead(bigint,boolean,text): production body md5 517e90c176b299bd8a0b2666947bb780
CREATE OR REPLACE FUNCTION b2b.b2c_sync_lead(p_lead_id bigint, p_force boolean DEFAULT false, p_origin text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cfg jsonb := b2b.b2c_link_cfg();
  l public.student_leads;
  prev b2b.b2c_sync;
  v_scope boolean;
  rec jsonb;
  v_hash text;
  v_seq bigint;
  v_ver int;
  v_type text;
  env jsonb;
  w b2b.webhook_endpoints;
begin
  if not coalesce((cfg ->> 'enabled')::boolean, true) then return jsonb_build_object('changed', false, 'why', 'link off'); end if;
  select * into l from public.student_leads where id = p_lead_id;
  select * into prev from b2b.b2c_sync where lead_id = p_lead_id for update;
  if l.id is null then
    if prev.lead_id is null or not prev.in_scope then return jsonb_build_object('changed', false); end if;
    v_scope := false;
    rec := jsonb_build_object('id', p_lead_id, 'deleted', true, 'held_by_b2c', false);
  else
    -- Addendum 3 (D45): held leads; under scope 'all' every live lead except Not passed and test leads without a test hand-off
    v_scope := b2b.b2c_in_scope(l);
    if not v_scope and (prev.lead_id is null or (not prev.in_scope and not p_force)) then return jsonb_build_object('changed', false); end if;
    rec := case when v_scope then b2b.b2c_record(l)
                else jsonb_build_object('id', l.id, 'held_by_b2c', false, 'deleted', l.deleted_at is not null or l.anonymised_at is not null,
                                        'merged_into_id', l.merged_into_id,
                                        'allocation', jsonb_build_object('destination', l.destination_type, 'reason', l.allocation_reason,
                                                                         'allocated_at', l.allocated_at)) end;
  end if;
  v_hash := md5((rec - 'updated_at')::text);
  if prev.lead_id is not null and prev.hash = v_hash and prev.in_scope = v_scope and not p_force then
    return jsonb_build_object('changed', false, 'version', prev.version);
  end if;
  v_seq := nextval('b2b.b2c_sync_seq');
  v_ver := coalesce(prev.version, 0) + 1;
  insert into b2b.b2c_sync (lead_id, seq, version, hash, in_scope, origin, changed_at)
  values (p_lead_id, v_seq, v_ver, v_hash, v_scope, p_origin, now())
  on conflict (lead_id) do update set seq = excluded.seq, version = excluded.version, hash = excluded.hash, in_scope = excluded.in_scope,
                                      origin = excluded.origin, changed_at = excluded.changed_at;
  v_type := case when v_scope then 'b2c.lead_upserted' else 'b2c.lead_released' end;
  env := jsonb_build_object('id', 'lead_' || p_lead_id || '_v' || v_ver, 'type', v_type, 'occurred_at', now(), 'lead_id', p_lead_id,
                            'test', coalesce((rec ->> 'is_test')::boolean, false), 'contract_version', 4,
                            'data', jsonb_build_object('version', v_ver, 'seq', v_seq, 'origin', p_origin, 'record', rec));
  -- Addendum 4 §1: always real time. Echo suppression: a version whose only origin is the B2C CRM's own write is not sent
  -- back (it learns the version from its answer), unless an older version is still on its way to that endpoint (then the
  -- newest record must follow, or the B2C CRM would treat the older one as stale and lose someone else's change).
  for w in select * from b2b.webhook_endpoints where consumer = 'b2c_crm' and active and b2b.event_subscribed(events, v_type) loop
    if v_scope and coalesce(p_origin, '') like 'b2c:%' and not exists (
         select 1 from b2b.integration_outbox o
          where o.endpoint_id = w.id and o.status in ('pending', 'failed', 'sending')
            and o.event_type in ('b2c.lead_upserted', 'b2c.lead_released') and (o.payload ->> 'lead_id')::bigint = p_lead_id) then
      continue;
    end if;
    update b2b.integration_outbox set status = 'cancelled', last_error = 'superseded by version ' || v_ver
     where endpoint_id = w.id and status in ('pending', 'failed') and event_type in ('b2c.lead_upserted', 'b2c.lead_released')
       and (payload ->> 'lead_id')::bigint = p_lead_id;
    insert into b2b.integration_outbox (event_type, target, payload, idempotency_key, endpoint_id)
    values (v_type, w.consumer, env, w.id || ':' || (env ->> 'id'), w.id)
    on conflict (idempotency_key) do nothing;
  end loop;
  return jsonb_build_object('changed', true, 'version', v_ver, 'seq', v_seq, 'type', v_type);
end $function$;

-- b2b.api_b2c_schema(text): production body md5 b8d5b311ba1a4e7472c7082f813bbea3
CREATE OR REPLACE FUNCTION b2b.api_b2c_schema(p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cfg jsonb := b2b.b2c_link_cfg();
begin
  if not (b2b.b2c_key(p_key) ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object(
    'contract_version', 4,
    'scope', cfg ->> 'scope', 'enabled', coalesce((cfg ->> 'enabled')::boolean, true),
    'delivery', 'realtime', 'interval_minutes', b2b.sync_minutes(),
    'batch', jsonb_build_object('every_minutes', 15, 'max_items', 200, 'max_bytes', 1048576, 'min_calls_per_minute', 20,
                                'item_fields', jsonb_build_array('op', 'lead_id', 'request_id', 'occurred_at', 'if_version', 'actor', 'set'),
                                'immediate', jsonb_build_array('b2ccrm.consent_request_sent', 'b2ccrm.partner_consent', 'b2ccrm.opted_out',
                                                               'b2ccrm.erasure_requested', 'POST /v1/leads/{id}/route-to-partners', 'POST /v1/leads')),
    'groups', (select jsonb_agg(distinct f ->> 'group') from jsonb_array_elements(b2b.b2c_fields()) f),
    'consent_texts', coalesce((select jsonb_agg(jsonb_build_object('text_version', t.version, 'text', t.body, 'channel', t.channel, 'purposes', to_jsonb(t.purposes),
                                                                   'covers_admission_partners', t.covers_admission_partners,
                                                                   'lawyer_approved', t.lawyer_approved_at is not null) order by t.version)
                                 from b2b.consent_texts t where t.active), '[]'::jsonb),
    'contact_labels', jsonb_build_array('alternate', 'parent', 'office', 'whatsapp_only'),
    'fields', (select jsonb_agg(jsonb_build_object('field', f ->> 'field', 'group', f ->> 'group', 'kind', f ->> 'kind', 'max', f -> 'max',
                                                   'writable', f ->> 'write' = 'b2c' and (cfg -> 'writable') ? (f ->> 'field')))
                 from jsonb_array_elements(b2b.b2c_fields()) f)
              || jsonb_build_array(jsonb_build_object('field', 'other_courses', 'group', 'interest', 'kind', 'list', 'max', 9::int, 'writable', true)),
    'stages', (select jsonb_agg(jsonb_build_object('key', e ->> 'key', 'rank', e -> 'rank', 'group', e ->> 'group'))
                 from b2b.settings s, jsonb_array_elements(s.value) e where s.key = 'stages' and e ->> 'key' is not null),
    'activity_kinds', jsonb_build_array('call', 'whatsapp', 'sms', 'email', 'meeting', 'note'),
    'reasons', jsonb_build_object(
      'sales', jsonb_build_array('b2c_created', 'import_choice', 'rule', 'manual', 'manual_route_failed', 'no_partner_offers_programme', 'no_capacity',
                                 'partners_unreachable', 'partner_attempts_exhausted', 'duplicate_cascade', 'no_partner_consent', 'partner_barred', 'b2c_held'),
      'nurture', jsonb_build_array('not_qualified', 'consent_no_answer', 'partner_lost'),
      'test', jsonb_build_array('test_handoff'),
      'retired', jsonb_build_array('paid_campaign')),
    'causes', jsonb_build_array('caps', 'paused', 'criteria', 'rule', 'duplicate_history', 'tried', 'duplicate_cascade', 'partner_attempts_exhausted',
                                'partners_unreachable', 'no_partner_offers_programme', 'no_capacity', 'no_partner_consent'),
    'handling', jsonb_build_object(
      'job', jsonb_build_array('sell', 'qualify', 'nurture'),
      'assignment', jsonb_build_array('round_robin_now', 'unassigned_until_interest', 'previous_counsellor', 'counsellor_choice', 'unassigned'),
      'first_contact_script', jsonb_build_array('neutral_adviser', 'standard')),
    'hold_kinds', jsonb_build_array('barred', 'qualification_nurture', 'selling'),
    'partner_bar_reasons', jsonb_build_array('duplicate', 'lost'),
    'consent_states', jsonb_build_array('given', 'refused', 'withdrawn', 'requested', 'queued', 'expired', 'stamp_uncovered', 'none'),
    'b2c_actions', jsonb_build_array('welcome_explore_programmes'),
    'events', jsonb_build_array('b2c.lead_upserted', 'b2c.lead_released', 'b2c.lead_handed_off', 'b2c.lead_reenquired',
                                'b2c.lead_flagged', 'b2c.lead_close_agreed', 'b2c.lead_requalified', 'b2c.lead_reengaged',
                                'b2c.consent_requested', 'b2c.consent_closed', 'b2b.lead_routed_to_partner', 'ping'),
    'inbound', jsonb_build_array('b2ccrm.lead_assigned', 'b2ccrm.stage_changed', 'b2ccrm.enrolled', 'b2ccrm.opted_out', 'b2ccrm.erasure_requested',
                                 'b2ccrm.partner_consent', 'b2ccrm.consent_request_sent', 'b2ccrm.marketing_consent', 'b2ccrm.contact_added',
                                 'b2ccrm.lead_updated', 'b2ccrm.commission_booked'),
    'route_to_partners_error_codes', jsonb_build_array('partner_barred', 'no_consent', 'not_held', 'invalid')));
end $function$;

-- b2b.b2c_link_overview(): production body md5 20b972ccefb5000946f8b2cd172afba4
CREATE OR REPLACE FUNCTION b2b.b2c_link_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cfg jsonb := b2b.b2c_link_cfg();
  w b2b.webhook_endpoints;
  v_keys jsonb;
  v_snap text[] := array['b2c.lead_upserted', 'b2c.lead_released'];
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into w from b2b.webhook_endpoints where consumer = 'b2c_crm';
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'prefix', key_prefix, 'scopes', scopes, 'last_used_at', last_used_at) order by id), '[]')
    into v_keys from b2b.api_keys where revoked_at is null and 'b2c' = any (scopes);
  return jsonb_build_object(
    'contract_version', 4,
    'settings', cfg,
    'fields', b2b.b2c_fields(),
    'endpoint', case when w.id is not null then jsonb_build_object('id', w.id, 'name', w.name, 'url', w.url, 'active', w.active, 'events', w.events,
                       'has_secret', w.secret_id is not null, 'last_success_at', w.last_success_at, 'last_failure_at', w.last_failure_at, 'last_error', w.last_error,
                       'subscribed', b2b.event_subscribed(w.events, 'b2c.lead_upserted') and b2b.event_subscribed(w.events, 'b2c.lead_released')) end,
    'keys', v_keys,
    'checks', jsonb_build_object(
      'endpoint', w.id is not null,
      'secret', w.secret_id is not null,
      'subscribed', coalesce(b2b.event_subscribed(w.events, 'b2c.lead_upserted'), false),
      'ping', exists (select 1 from b2b.integration_outbox o where o.endpoint_id = w.id and o.event_type = 'ping' and o.status = 'delivered'),
      'active', coalesce(w.active, false),
      'key', jsonb_array_length(v_keys) > 0,
      'key_used', exists (select 1 from b2b.api_keys where revoked_at is null and 'b2c' = any (scopes) and last_used_at is not null),
      'first_delivery', exists (select 1 from b2b.integration_outbox o where o.endpoint_id = w.id and o.event_type = any (v_snap) and o.status = 'delivered'),
      'first_write', exists (select 1 from b2b.b2c_writes where status in ('applied', 'unchanged'))),
    'sync', jsonb_build_object(
      'in_scope', (select count(*) from b2b.b2c_sync where in_scope),
      'held_now', (select count(*) from public.student_leads l where b2b.b2c_holds(l)),
      'changes_24h', (select count(*) from b2b.b2c_sync where changed_at > now() - interval '24 hours'),
      'last_change_at', (select max(changed_at) from b2b.b2c_sync),
      'last_seq', (select max(seq) from b2b.b2c_sync),
      'tick', (select value from b2b.b2c_link_state where key = 'cursor')),
    'deliveries', jsonb_build_object(
      'by_status', coalesce((select jsonb_object_agg(status, n) from (select o.status, count(*) n from b2b.integration_outbox o
                               where o.endpoint_id = w.id and o.event_type = any (v_snap) and o.created_at > now() - interval '24 hours' group by 1) x), '{}'),
      'waiting', (select count(*) from b2b.integration_outbox o where o.endpoint_id = w.id and o.status in ('pending', 'failed', 'sending')),
      'lag_seconds_avg', (select round(avg(extract(epoch from o.delivered_at - o.created_at))::numeric, 1) from b2b.integration_outbox o
                            where o.endpoint_id = w.id and o.event_type = any (v_snap) and o.delivered_at > now() - interval '1 hour'),
      'lag_seconds_max', (select round(max(extract(epoch from o.delivered_at - o.created_at))::numeric, 1) from b2b.integration_outbox o
                            where o.endpoint_id = w.id and o.event_type = any (v_snap) and o.delivered_at > now() - interval '1 hour'),
      'lag_seconds_p95', (select round((percentile_cont(0.95) within group (order by extract(epoch from o.delivered_at - o.created_at)))::numeric, 1)
                            from b2b.integration_outbox o
                           where o.endpoint_id = w.id and o.event_type = any (v_snap) and o.delivered_at > now() - interval '1 hour'),
      'lag_target_seconds', 5),
    'writes', jsonb_build_object(
      'by_status', coalesce((select jsonb_object_agg(kind || '.' || status, n) from (select kind, status, count(*) n from b2b.b2c_writes
                               where created_at > now() - interval '24 hours' group by 1, 2) x), '{}'),
      'last_at', (select max(created_at) from b2b.b2c_writes)),
    'log', coalesce((select jsonb_agg(x order by x ->> 'at' desc) from (
      (select jsonb_build_object('dir', 'out', 'at', s.changed_at, 'lead_id', s.lead_id, 'name', l.student_name, 'type', case when s.in_scope then 'upserted' else 'released' end,
                                 'version', s.version, 'origin', s.origin,
                                 'delivery', (select jsonb_build_object('status', o.status, 'error', o.last_error, 'attempts', o.attempts) from b2b.integration_outbox o
                                               where o.endpoint_id = w.id and o.idempotency_key = w.id || ':lead_' || s.lead_id || '_v' || s.version)) x
         from b2b.b2c_sync s left join public.student_leads l on l.id = s.lead_id order by s.changed_at desc limit 40)
      union all
      (select jsonb_build_object('dir', 'in', 'at', b.created_at, 'lead_id', b.lead_id, 'name', l.student_name, 'type', b.kind, 'status', b.status,
                                 'http_status', b.http_status, 'error', b.error, 'actor', b.actor, 'changes', b.changes, 'request_id', b.request_id,
                                 'version', b.version_after) x
         from b2b.b2c_writes b left join public.student_leads l on l.id = b.lead_id order by b.created_at desc limit 40)) y), '[]'));
end $function$;

-- b2c.allocate(bigint,text,uuid): production body md5 9e4afcc05d495d36b5aae75c75a434f1
CREATE OR REPLACE FUNCTION b2c.allocate(p_lead bigint, p_trigger text, p_exclude uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s b2c.leads_state; d jsonb; v_id bigint; v_creator uuid;
begin
  select * into s from b2c.leads_state where lead_id = p_lead for update;
  if s.lead_id is null or s.deleted_at is not null or s.status = 'closed' then return jsonb_build_object('outcome', 'skipped'); end if;
  if s.owner_id is not null and p_exclude is null and p_trigger not in ('reassign', 'hand_back')
     and exists (select 1 from b2c.users u where u.user_id = s.owner_id and u.is_active) then
    insert into b2c.allocation_decisions (lead_id, trigger, hot, chosen, outcome, why) values (p_lead, p_trigger, s.hot, s.owner_id, 'kept', 'already with an active counsellor')
    returning id into v_id;
    if p_trigger = 'returned_from_partners' then
      perform b2c.assign(p_lead, s.owner_id, v_id, p_trigger, 'no partner took it');
    else
      perform b2c.notify(s.owner_id, 'reenquiry', 'Your lead came back', p_trigger, '/s/leads/' || p_lead, p_lead, 'kept:' || v_id);
    end if;
    return jsonb_build_object('outcome', 'kept', 'chosen', s.owner_id, 'decision_id', v_id);
  end if;
  if s.handoff_reason = 'b2c_created' and p_exclude is null and p_trigger in ('handoff', 'retry') then
    select c.user_id into v_creator from b2c.created_leads c join b2c.users u on u.user_id = c.user_id and u.is_active
     where c.lead_id = p_lead order by c.created_at desc limit 1;
    if v_creator is not null then
      insert into b2c.allocation_decisions (lead_id, trigger, hot, chosen, outcome, why) values (p_lead, p_trigger, s.hot, v_creator, 'assigned', 'created by this counsellor')
      returning id into v_id;
      perform b2c.assign(p_lead, v_creator, v_id, 'created', 'created by them');
      return jsonb_build_object('outcome', 'assigned', 'chosen', v_creator, 'decision_id', v_id, 'why', 'created by this counsellor');
    elsif s.handed_off_at > now() - interval '2 minutes' then
      return jsonb_build_object('outcome', 'skipped', 'why', 'waiting for the creating counsellor');
    end if;
  end if;
  d := b2c.decide(p_lead, p_trigger, now(), p_exclude, false);
  insert into b2c.allocation_decisions (lead_id, trigger, hot, facts, rule_id, rule_name, logic, pool, eligible, skipped, chosen, turn, outcome, why)
  values (p_lead, p_trigger, coalesce((d ->> 'hot')::boolean, false), coalesce(d -> 'facts', '{}'), (d ->> 'rule_id')::bigint, d ->> 'rule_name', d ->> 'logic',
          d ->> 'pool', coalesce(d -> 'eligible', '[]'), coalesce(d -> 'skipped', '[]'), (d ->> 'chosen')::uuid, (d ->> 'turn')::int, d ->> 'outcome',
          coalesce(d ->> 'why', (select string_agg(t ->> 'rule' || ': ' || coalesce(t ->> 'why', 'nobody eligible'), '; ') from jsonb_array_elements(d -> 'tried') t)))
  returning id into v_id;
  if d ->> 'outcome' = 'assigned' then
    if d ->> 'turn' is not null then update b2c.allocation_rules set turn = (d ->> 'turn')::int where id = (d ->> 'rule_id')::bigint; end if;
    perform b2c.assign(p_lead, (d ->> 'chosen')::uuid, v_id, p_trigger, d ->> 'rule_name');
  else
    update b2c.assignments set ended_at = now(), end_reason = p_trigger where lead_id = p_lead and ended_at is null;
    update b2c.leads_state set owner_id = null, status = 'active', updated_at = now() where lead_id = p_lead and status <> 'closed';
  end if;
  return d - 'facts' || jsonb_build_object('decision_id', v_id);
end $function$;

-- b2c.add_note(bigint,text,boolean): production body md5 43806e507aa41df786fe5ac93fe6c674
CREATE OR REPLACE FUNCTION b2c.add_note(p_lead bigint, p_body text, p_internal boolean DEFAULT false)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me uuid; v bigint;
begin
  if p_internal then me := b2c.require('settings'); else me := b2c.require_lead(p_lead); end if;
  if length(coalesce(trim(p_body), '')) = 0 then raise exception 'write the note'; end if;
  insert into b2c.activities (lead_id, kind, body, internal, actor_id) values (p_lead, case when p_internal then 'coaching' else 'note' end, left(p_body, 4000), p_internal, me)
  returning id into v;
  update b2c.leads_state set last_activity_at = now() where lead_id = p_lead;
  if not p_internal then perform b2c.queue_activity(p_lead, 'note', now(), null, null, p_body); end if;
  return v;
end $function$;

-- b2c.email_template_save(jsonb): production body md5 353b9ac7d0c183e8840ffb5fb54cfc62
CREATE OR REPLACE FUNCTION b2c.email_template_save(p jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me uuid := b2c.require('templates_sales_email'); v bigint := nullif(p ->> 'id', '')::bigint; t b2c.sales_email_templates;
begin
  if coalesce(trim(p ->> 'name'), '') = '' or coalesce(trim(p ->> 'subject'), '') = '' or coalesce(trim(p ->> 'body'), '') = '' then
    raise exception 'a template needs a name, a subject and a body';
  end if;
  if v is not null then select * into t from b2c.sales_email_templates where id = v and deleted_at is null; end if;
  if v is null or t.id is null then
    insert into b2c.sales_email_templates (owner_id, name, category, subject, body, attachments)
    values (me, p ->> 'name', coalesce(p ->> 'category', 'other'), p ->> 'subject', p ->> 'body', coalesce(p -> 'attachments', '[]')) returning id into v;
  elsif t.owner_id = me or b2c.my_role() = 'admin' then
    update b2c.sales_email_templates set name = p ->> 'name', category = coalesce(p ->> 'category', category), subject = p ->> 'subject', body = p ->> 'body',
           attachments = coalesce(p -> 'attachments', attachments), version = version + 1, updated_at = now() where id = t.id;
  else
    insert into b2c.sales_email_templates (owner_id, name, category, subject, body, attachments, parent_id)
    values (me, p ->> 'name', coalesce(p ->> 'category', t.category), p ->> 'subject', p ->> 'body', coalesce(p -> 'attachments', t.attachments), t.id)
    returning id into v;
  end if;
  return v;
end $function$;

-- b2c.application_save(jsonb): production body md5 c653a24fcc84b3fc503a789ef6823c6c
CREATE OR REPLACE FUNCTION b2c.application_save(p jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_lead bigint := (p ->> 'lead_id')::bigint; me uuid := b2c.require_lead(v_lead); v bigint := nullif(p ->> 'id', '')::bigint; s b2c.leads_state; v_first boolean;
        v_list jsonb;
begin
  if coalesce(trim(p ->> 'university'), '') = '' or coalesce(trim(p ->> 'programme'), '') = '' then raise exception 'choose the university and programme'; end if;
  v_first := not exists (select 1 from b2c.applications where lead_id = v_lead);
  select coalesce((select items from b2c.document_checklists where university = p ->> 'university'), (select items from b2c.document_checklists where university = '*')) into v_list;
  if v is null then
    insert into b2c.applications (lead_id, university, programme, application_ref, status, fee_amount, fee_paid, checklist, created_by)
    values (v_lead, p ->> 'university', p ->> 'programme', nullif(trim(p ->> 'application_ref'), ''), coalesce(p ->> 'status', 'started'),
            nullif(p ->> 'fee_amount', '')::numeric, nullif(p ->> 'fee_paid', '')::numeric,
            coalesce(p -> 'checklist', (select jsonb_object_agg(i, 'pending') from jsonb_array_elements_text(v_list) i)), me)
    returning id into v;
  else
    update b2c.applications set university = p ->> 'university', programme = p ->> 'programme', application_ref = nullif(trim(p ->> 'application_ref'), ''),
           status = coalesce(p ->> 'status', status), fee_amount = nullif(p ->> 'fee_amount', '')::numeric, fee_paid = nullif(p ->> 'fee_paid', '')::numeric,
           checklist = coalesce(p -> 'checklist', checklist), updated_at = now()
     where id = v and lead_id = v_lead;
  end if;
  insert into b2c.activities (lead_id, kind, body, meta, actor_id)
  values (v_lead, 'application', 'Application ' || coalesce(p ->> 'status', 'started') || ': ' || (p ->> 'university') || ' · ' || (p ->> 'programme'), jsonb_build_object('application_id', v), me);
  select * into s from b2c.leads_state where lead_id = v_lead;
  if coalesce(s.stage_id, 1) < 7 then
    update b2c.leads_state set stage_id = 7, sub_stage = case coalesce(p ->> 'status', 'started') when 'started' then 'Application started'
                                                                 when 'fee_paid' then 'Application fee paid' else 'Application submitted' end,
           stage_changed_at = now(), last_activity_at = now() where lead_id = v_lead;
  end if;
  perform b2c.queue_update(v_lead, jsonb_strip_nulls(jsonb_build_object('application_id', nullif(trim(p ->> 'application_ref'), ''),
            'application_status', coalesce(p ->> 'status', 'started'), 'applied_at', case when v_first then now() end,
            'fee_amount_inr', nullif(p ->> 'fee_amount', '')::numeric, 'fee_paid_inr', nullif(p ->> 'fee_paid', '')::numeric))
            || case when coalesce(s.stage_id, 1) < 7 then jsonb_build_object('stage', 'applied', 'b2c_stage', 'Applicant', 'stage_changed_at', now(),
                    'b2c_sub_stage', (select sub_stage from b2c.leads_state where lead_id = v_lead), 'sub_stage', (select sub_stage from b2c.leads_state where lead_id = v_lead)) else '{}'::jsonb end, false);
  return v;
end $function$;

-- b2c.new_lead(jsonb,jsonb): production body md5 1a6be2be41b6e2029ddc7e7c89537f77
CREATE OR REPLACE FUNCTION b2c.new_lead(p jsonb, p_existing jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me uuid := b2c.require('work_leads'); v_phone text := b2c.norm_phone(p ->> 'phone'); v_lead bigint := nullif(p_existing ->> 'lead_id', '')::bigint;
        s b2c.leads_state; v_req text;
begin
  if v_phone is null or length(v_phone) not between 11 and 13 then raise exception 'enter a valid phone number'; end if;
  if v_lead is not null then
    select * into s from b2c.leads_state where lead_id = v_lead;
    if s.lead_id is null or not coalesce((p_existing ->> 'held_by_b2c')::boolean, false) then
      return jsonb_build_object('outcome', 'with_partner', 'holder', p_existing -> 'holder');
    elsif s.status = 'pool' then
      update b2c.leads_state set status = 'active', hot = true, reengaged_at = now(), reengage_trigger = 'walk_in', journey = null where lead_id = v_lead;
      perform b2c.assign(v_lead, me, null, 'reengaged', 'came back to ' || coalesce((select full_name from b2c.users where user_id = me), 'a counsellor'));
      return jsonb_build_object('outcome', 'reengaged', 'lead_id', v_lead);
    elsif s.owner_id is not null and s.owner_id <> me then
      return jsonb_build_object('outcome', 'with_counsellor', 'lead_id', v_lead, 'owner', (select full_name from b2c.users where user_id = s.owner_id));
    else
      return jsonb_build_object('outcome', 'yours', 'lead_id', v_lead);
    end if;
  end if;
  v_req := 'b2c-in-' || v_phone || '-' || to_char(now(), 'YYYYMMDDHH24MI');
  insert into b2c.created_leads (request_id, phone_norm, user_id) values (v_req, v_phone, me) on conflict (request_id) do nothing;
  insert into b2c.outbox (kind, lead_id, request_id, body, urgent)
  values ('intake', null, v_req, jsonb_strip_nulls(jsonb_build_object('phone', v_phone, 'lead_source', 'b2c_created', 'name', p ->> 'name', 'email', p ->> 'email',
          'course', p ->> 'course', 'city', p ->> 'city', 'other_courses', p -> 'other_courses', 'notes', p ->> 'notes', 'consent_text_version', p ->> 'consent_text_version')), true)
  on conflict (request_id) do nothing;
  return jsonb_build_object('outcome', 'requested', 'request_id', v_req);
end $function$;

-- b2c.segment_save(jsonb): production body md5 fc9bddec3733b3db113eff34909d84f4
CREATE OR REPLACE FUNCTION b2c.segment_save(p jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me uuid := b2c.require('marketing'); v bigint := nullif(p ->> 'id', '')::bigint;
begin
  if v is null and coalesce(trim(p ->> 'name'), '') = '' then raise exception 'name the segment'; end if;
  if p ? 'filters' then perform b2c.filters_where(p -> 'filters'); end if;
  if v is null then
    insert into b2c.segments (name, description, kind, filters, created_by)
    values (trim(p ->> 'name'), p ->> 'description', coalesce(p ->> 'kind', 'dynamic'), coalesce(p -> 'filters', '{}'), me) returning id into v;
  else
    update b2c.segments set name = coalesce(nullif(trim(p ->> 'name'), ''), name), description = case when p ? 'description' then p ->> 'description' else description end,
           filters = coalesce(p -> 'filters', filters),
           archived_at = case when p ? 'archived' then case when (p ->> 'archived')::boolean then coalesce(archived_at, now()) end else archived_at end,
           updated_at = now()
     where id = v;
    if not found then raise exception 'unknown segment'; end if;
  end if;
  return v;
end $function$;

-- b2c.campaign_tick(): production body md5 7e0b3bd1b95be1adcd5a988aa9819a8b
CREATE OR REPLACE FUNCTION b2c.campaign_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c b2c.campaigns; s record; r jsonb; v_sent int := 0; v_blocked int := 0; v_now time := (now() at time zone 'Asia/Kolkata')::time; v_n int; v_total int;
        v_tpl bigint; v_rate_a numeric; v_rate_b numeric; v_wait int := coalesce((b2c.setting('nurture') ->> 'ab_wait_hours')::int, 4);
begin
  for c in select * from b2c.campaigns where status = 'scheduled' and schedule_at <= now() for update skip locked loop
    update b2c.campaigns set status = 'running', started_at = now(), run_no = run_no + 1, winner = null, updated_at = now() where id = c.id returning * into c;
    insert into b2c.campaign_sends (campaign_id, run_no, lead_id, variant, status)
    select c.id, c.run_no, l, case when c.template_b_id is null or c.ab_pct = 0 then 'a' when rn <= cnt * c.ab_pct / 100.0 then case when rn % 2 = 0 then 'a' else 'b' end end,
           case when c.template_b_id is null or c.ab_pct = 0 or rn <= cnt * c.ab_pct / 100.0 then 'pending' else 'held' end
      from (select l, row_number() over (order by random()) rn, count(*) over () cnt from b2c.segment_leads(c.segment_id, null, c.test_only) l) q
    on conflict do nothing;
  end loop;

  for c in select * from b2c.campaigns where status = 'running' order by id loop
    continue when c.window_start is not null and (v_now < c.window_start or v_now >= coalesce(c.window_end, '20:00'));
    continue when not b2c.in_send_window();
    v_n := 0;
    for s in select * from b2c.campaign_sends where campaign_id = c.id and run_no = c.run_no and status = 'pending' and not_before <= now()
              order by id limit c.throttle_per_min for update skip locked loop
      if c.channel = 'email' and b2c.email_allowance_left() <= 0 then exit; end if;
      v_tpl := case when s.variant = 'b' then c.template_b_id else c.template_id end;
      r := case c.channel when 'whatsapp' then b2c.queue_marketing_wa(s.lead_id, v_tpl, 'campaign', jsonb_build_object('campaign_id', c.id), c.allow_active_sales)
                          else b2c.queue_marketing_email(s.lead_id, v_tpl, 'campaign', jsonb_build_object('campaign_id', c.id), c.allow_active_sales) end;
      if r ? 'blocked' then
        if r ->> 'blocked' = 'wait: in a Witty chat' then
          update b2c.campaign_sends set not_before = now() + interval '30 minutes', reason = r ->> 'blocked' where id = s.id;
        else
          update b2c.campaign_sends set status = case when r ->> 'blocked' like 'wait:%' then 'skipped' else 'blocked' end, reason = r ->> 'blocked', done_at = now() where id = s.id;
          v_blocked := v_blocked + 1;
        end if;
      else
        update b2c.campaign_sends set status = 'queued', wa_message_id = (r ->> 'message_id')::bigint, email_id = (r ->> 'email_id')::bigint, done_at = now() where id = s.id;
        v_sent := v_sent + 1; v_n := v_n + 1;
      end if;
    end loop;

    if c.template_b_id is not null and c.ab_pct > 0 and c.winner is null
       and not exists (select 1 from b2c.campaign_sends where campaign_id = c.id and run_no = c.run_no and status = 'pending')
       and c.started_at <= now() - make_interval(hours => v_wait) then
      if c.channel = 'whatsapp' then
        select avg(case when m.status = 'read' or exists (select 1 from b2c.wa_messages i where i.lead_id = x.lead_id and i.direction = 'in' and i.created_at > m.created_at) then 1 else 0 end) filter (where x.variant = 'a'),
               avg(case when m.status = 'read' or exists (select 1 from b2c.wa_messages i where i.lead_id = x.lead_id and i.direction = 'in' and i.created_at > m.created_at) then 1 else 0 end) filter (where x.variant = 'b')
          into v_rate_a, v_rate_b
          from b2c.campaign_sends x join b2c.wa_messages m on m.id = x.wa_message_id where x.campaign_id = c.id and x.run_no = c.run_no;
      else
        select avg(case when e.opened_at is not null or e.clicked_at is not null then 1 else 0 end) filter (where x.variant = 'a'),
               avg(case when e.opened_at is not null or e.clicked_at is not null then 1 else 0 end) filter (where x.variant = 'b')
          into v_rate_a, v_rate_b
          from b2c.campaign_sends x join b2c.emails e on e.id = x.email_id where x.campaign_id = c.id and x.run_no = c.run_no;
      end if;
      update b2c.campaigns set winner = case when coalesce(v_rate_b, 0) > coalesce(v_rate_a, 0) then 'b' else 'a' end where id = c.id returning * into c;
      update b2c.campaign_sends set variant = c.winner, status = 'pending' where campaign_id = c.id and run_no = c.run_no and status = 'held';
    end if;

    if not exists (select 1 from b2c.campaign_sends where campaign_id = c.id and run_no = c.run_no and status in ('pending', 'held')) then
      if c.recurring is null then
        update b2c.campaigns set status = 'done', finished_at = now(), updated_at = now() where id = c.id;
      else
        update b2c.campaigns set status = 'scheduled', finished_at = now(), updated_at = now(),
               schedule_at = c.schedule_at + case c.recurring when 'daily' then interval '1 day' when 'weekly' then interval '7 days' else interval '1 month' end
         where id = c.id;
      end if;
    end if;
  end loop;
  return jsonb_build_object('sent', v_sent, 'blocked', v_blocked);
end $function$;

-- b2c.score_add(bigint,text,numeric,jsonb): production body md5 282bfec1751ca49b7e82bf1782968beb
CREATE OR REPLACE FUNCTION b2c.score_add(p_lead bigint, p_rule text, p_points numeric DEFAULT NULL::numeric, p_detail jsonb DEFAULT '{}'::jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare rl b2c.score_rules; s b2c.leads_state; v_pts numeric; v_new int; v_line int := coalesce((b2c.setting('scoring') ->> 'reengage_at')::int, 60);
begin
  select * into rl from b2c.score_rules where key = p_rule;
  if rl.key is null or (not rl.active and p_points is null) then return null; end if;
  if not exists (select 1 from b2c.leads_state where lead_id = p_lead) then return null; end if;
  perform b2c.score_recompute(p_lead);
  select * into s from b2c.leads_state where lead_id = p_lead;
  v_pts := coalesce(p_points, rl.points);
  update b2c.leads_state set engagement_points = greatest(0, engagement_points + v_pts), engagement_at = case when v_pts > 0 then now() else engagement_at end
   where lead_id = p_lead;
  v_new := b2c.score_recompute(p_lead);
  insert into b2c.score_events (lead_id, rule_key, points, score_after, detail) values (p_lead, p_rule, v_pts, v_new, coalesce(p_detail, '{}'));
  if s.status = 'pool' and coalesce(s.score, 0) < v_line and v_new >= v_line and v_pts > 0 and rl.kind = 'engagement' and s.pool_entered_at is not null then
    perform b2c.reengage(p_lead, 'score');
  end if;
  return v_new;
end $function$;

-- b2c.reply_receive(bigint,text,text,text,jsonb): production body md5 b82bee690447cc1623fd204dd8587eb1
CREATE OR REPLACE FUNCTION b2c.reply_receive(p_lead bigint, p_channel text, p_text text, p_button text DEFAULT NULL::text, p_ref jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id bigint; v_class text; v_conf numeric; v_method text; v_low text := lower(trim(coalesce(p_button, p_text, ''))); b jsonb := b2c.setting('reply_buttons'); rr record; v_out text;
begin
  if p_button is not null or v_low in (select jsonb_array_elements_text(b -> 'positive') union all select jsonb_array_elements_text(b -> 'negative') union all select jsonb_array_elements_text(b -> 'consent')) then
    if v_low in (select jsonb_array_elements_text(b -> 'consent')) then
      perform b2c.marketing_consent(p_lead, 'whatsapp', true, 'wa_button', 'nurture_consent_repeat');
      perform b2c.marketing_consent(p_lead, 'email', true, 'wa_button', 'nurture_consent_repeat');
      v_class := 'other'; v_conf := 1; v_method := 'button';
    elsif v_low in (select jsonb_array_elements_text(b -> 'positive')) then v_class := 'positive'; v_conf := 1; v_method := 'button';
    elsif v_low in (select jsonb_array_elements_text(b -> 'negative')) then v_class := 'negative'; v_conf := 1; v_method := 'button';
    end if;
  end if;
  if v_class is null then
    for rr in select class, confidence from b2c.reply_rules where active and v_low ~* pattern order by sort, id limit 1 loop
      v_class := rr.class; v_conf := rr.confidence; v_method := 'rule';
    end loop;
  end if;
  insert into b2c.replies (lead_id, channel, wa_message_id, email_id, text, button, class, method, confidence, status)
  values (p_lead, p_channel, (p_ref ->> 'message_id')::bigint, (p_ref ->> 'email_id')::bigint, left(p_text, 4000), p_button, v_class, v_method, v_conf,
          case when v_class is null then 'pending_ai' else 'new' end)
  returning id into v_id;
  if v_class is null then return jsonb_build_object('status', 'classifying', 'reply_id', v_id); end if;
  if v_method = 'button' and v_class = 'other' then
    update b2c.replies set status = 'done', action = 'consent_given', handled_at = now() where id = v_id;
    perform b2c.score_add(p_lead, case when p_channel = 'whatsapp' then 'wa_reply' else 'email_reply' end, null, jsonb_build_object('reply_id', v_id));
    return jsonb_build_object('status', 'consent_given', 'reply_id', v_id);
  end if;
  v_out := b2c.reply_act(v_id);
  if v_class not in ('negative', 'opt_out') then
    perform b2c.score_add(p_lead, case when p_channel = 'whatsapp' then 'wa_reply' else 'email_reply' end, null, jsonb_build_object('reply_id', v_id));
  end if;
  return jsonb_build_object('status', v_out, 'reply_id', v_id, 'class', v_class);
end $function$;

-- b2c.nightly_tick(): production body md5 dad5b5c5294760c4e624d716d8999cbd
CREATE OR REPLACE FUNCTION b2c.nightly_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb := '{}'::jsonb; n int; total int := 0;
begin
  loop
    n := b2c.score_decay_tick(500); total := total + n;
    exit when n < 500 or total >= 20000;
    perform pg_sleep(0.2);
  end loop;
  v := jsonb_build_object('decayed', total, 'dormant', b2c.dormancy_tick(1000));
  return v;
end $function$;

-- b2c.university_rate_save(jsonb): production body md5 a80dbc97ca48a768608dd57c10d68dc0
CREATE OR REPLACE FUNCTION b2c.university_rate_save(p jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me uuid := b2c.require('money'); v bigint; v_from date := coalesce(nullif(p ->> 'valid_from', '')::date, current_date);
        v_uni bigint := (p ->> 'university_id')::bigint; v_prog bigint := nullif(p ->> 'programme_id', '')::bigint; t jsonb;
begin
  if not exists (select 1 from public.catalog_universities where id = v_uni) then raise exception 'pick a university from the catalogue'; end if;
  if p ->> 'rate_type' = 'tiered' then
    if jsonb_typeof(p -> 'tiers') <> 'array' or jsonb_array_length(p -> 'tiers') = 0 then raise exception 'a tiered rate needs its tiers'; end if;
    for t in select * from jsonb_array_elements(p -> 'tiers') loop
      if (t ->> 'value') is null or (t ->> 'value')::numeric < 0 or (t ->> 'value')::numeric > 100 then raise exception 'each tier needs a percent between 0 and 100'; end if;
    end loop;
  elsif p ->> 'rate_type' = 'percent' and ((p ->> 'value')::numeric not between 0 and 100) then raise exception 'a percent is between 0 and 100';
  elsif p ->> 'rate_type' = 'fixed' and ((p ->> 'value')::numeric < 0) then raise exception 'a fixed amount cannot be negative';
  end if;
  if length(coalesce(trim(p ->> 'note'), '')) < 3 then raise exception 'say where the rate comes from (agreement, email, date)'; end if;
  update b2c.university_rates set valid_to = v_from - 1
   where university_id = v_uni and programme_id is not distinct from v_prog and retired_at is null and valid_from < v_from and (valid_to is null or valid_to >= v_from);
  insert into b2c.university_rates (university_id, programme_id, rate_type, fee_base, value, tiers, gst_inclusive, valid_from, valid_to, note, created_by)
  values (v_uni, v_prog, p ->> 'rate_type', coalesce(p ->> 'fee_base', 'first_year'), nullif(p ->> 'value', '')::numeric,
          case when p ->> 'rate_type' = 'tiered' then p -> 'tiers' end, coalesce((p ->> 'gst_inclusive')::boolean, true), v_from,
          nullif(p ->> 'valid_to', '')::date, p ->> 'note', me)
  returning id into v;
  perform b2c.log('money.university_rate_saved', null, jsonb_build_object('rate_id', v, 'university_id', v_uni, 'programme_id', v_prog));
  perform b2c.earning_book(e.id) from b2c.enrollments e
   where e.university_id = v_uni and e.status in ('reported', 'verified') and e.enrolled_on >= v_from
     and not exists (select 1 from b2c.earnings x where x.enrollment_id = e.id);
  return v;
end $function$;

-- b2c.partner_rates_for(bigint): production body md5 ccba4f421daea378e1b4cec6ebd7fb22
CREATE OR REPLACE FUNCTION b2c.partner_rates_for(p_enrollment bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare e b2c.enrollments; v_src text; v_list jsonb := '[]'; p record; r jsonb; a jsonb; v_best jsonb; f b2c.commission_fallbacks; v_err text;
begin
  select * into e from b2c.enrollments where id = p_enrollment;
  begin
    for p in
      select pa.id, coalesce(pa.display_name, pa.name) as name,
             exists (select 1 from b2b.partner_programmes pp where pp.partner_id = pa.id and pp.programme_id = e.programme_id and pp.active
                      and (pp.valid_to is null or pp.valid_to::date >= e.enrolled_on)) as offers_programme,
             exists (select 1 from b2b.partner_programmes pp join public.catalog_programs cp on cp.id = pp.programme_id
                      where pp.partner_id = pa.id and cp.university_id = e.university_id and pp.active and (pp.valid_to is null or pp.valid_to::date >= e.enrolled_on)) as offers_university
        from b2b.partners pa where pa.status in ('active', 'paused')
    loop
      continue when not (p.offers_programme or p.offers_university);
      v_list := v_list || jsonb_build_object('partner_id', p.id, 'name', p.name, 'offers_programme', p.offers_programme);
    end loop;
  exception when undefined_table or undefined_column or invalid_schema_name then
    v_err := 'partner catalogue not readable: ' || sqlerrm;
    v_list := '[]';
  end;
  if e.programme_id is not null and exists (select 1 from jsonb_array_elements(v_list) x where (x ->> 'offers_programme')::boolean) then
    v_src := 'partner';
    v_list := (select jsonb_agg(x) from jsonb_array_elements(v_list) x where (x ->> 'offers_programme')::boolean);
  elsif jsonb_array_length(v_list) > 0 then
    v_src := 'university_highest';
  else
    v_src := 'none';
  end if;
  if v_src <> 'none' then
    v_list := (select jsonb_agg(x || jsonb_build_object('rate', r1.r, 'computed', b2c.rate_amount(e.id, r1.r)))
                 from jsonb_array_elements(v_list) x,
                      lateral (select b2c.partner_rate_pick((x ->> 'partner_id')::bigint, e.programme_id, e.university_id, e.enrolled_on, v_src = 'partner') as r) r1);
    select x into v_best from jsonb_array_elements(v_list) x where x -> 'computed' ->> 'amount' is not null
     order by (x -> 'computed' ->> 'amount')::numeric desc, (x ->> 'partner_id')::bigint limit 1;
  end if;
  if v_best is null then
    select * into f from b2c.commission_fallbacks where university_id = e.university_id;
    if f.university_id is not null then
      r := jsonb_build_object('scope', 'fallback', 'rate_type', f.rate_type, 'value', f.value, 'fee_base', f.fee_base, 'reason', f.reason, 'set_at', f.set_at);
      a := b2c.rate_amount(e.id, r);
      return jsonb_build_object('source', 'fallback', 'partners', v_list, 'used', jsonb_build_object('rate', r, 'computed', a), 'read_at', now(), 'error', v_err,
                                'university_had_partners', v_src <> 'none');
    end if;
    return jsonb_build_object('source', 'none', 'partners', v_list, 'used', null, 'read_at', now(), 'error', v_err);
  end if;
  return jsonb_build_object('source', v_src, 'partners', v_list, 'used', v_best, 'read_at', now(), 'error', v_err);
end $function$;

-- b2c.commission_fallback_save(jsonb): production body md5 a94e07415754d4bbf85a4e2665caf89c
CREATE OR REPLACE FUNCTION b2c.commission_fallback_save(p jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me uuid := b2c.require('money'); v_uni bigint := (p ->> 'university_id')::bigint; l record; n int := 0;
begin
  if length(coalesce(trim(p ->> 'reason'), '')) < 3 then raise exception 'say where the rate comes from'; end if;
  if p ->> 'rate_type' = 'percent' and (p ->> 'value')::numeric > 100 then raise exception 'a percent is between 0 and 100'; end if;
  insert into b2c.commission_fallbacks as f (university_id, rate_type, fee_base, value, reason, set_by)
  values (v_uni, p ->> 'rate_type', coalesce(p ->> 'fee_base', 'first_year'), (p ->> 'value')::numeric, p ->> 'reason', me)
  on conflict (university_id) do update set rate_type = excluded.rate_type, fee_base = excluded.fee_base, value = excluded.value, reason = excluded.reason, set_by = me, set_at = now();
  perform b2c.log('money.commission_fallback_saved', null, p);
  for l in select x.id, x.enrollment_id from b2c.commission_lines x join b2c.enrollments e on e.id = x.enrollment_id
            where x.status = 'needs_rate' and e.university_id = v_uni loop
    update b2c.commission_lines set status = 'void' where id = l.id;
    perform b2c.commission_book(l.enrollment_id, 'rate set by the Admin');
    n := n + 1;
  end loop;
  return n;
end $function$;

-- b2c.analytics_exec(uuid,text,jsonb): production body md5 e51ec8f783a3f18b064857f9bd5d6f40
CREATE OR REPLACE FUNCTION b2c.analytics_exec(p_user uuid, p_role text, spec jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  g text := b2c.an_group(p_role); m b2c.metric_defs; s b2c.an_sources; d b2c.dim_defs; v_metrics text[]; v_dims text[]; k text; i int;
  v_from date := coalesce(nullif(spec ->> 'from', '')::date, (now() at time zone 'Asia/Kolkata')::date - 29);
  v_to date := coalesce(nullif(spec ->> 'to', '')::date, (now() at time zone 'Asia/Kolkata')::date);
  v_test boolean := coalesce((spec ->> 'test')::boolean, false); v_limit int := least(greatest(coalesce((spec ->> 'limit')::int, 500), 1), 5000);
  v_where text; v_scope text; v_sel text; v_grp text; v_sql text; v_rows jsonb; v_out jsonb := '{}'; v_sqls jsonb := '[]'; c jsonb; v_expr text; v_op text; v_cmp jsonb;
  v_team text; v_date text; v_cmp_from date; v_cmp_to date; v_all_rows jsonb;
begin
  if g is null then raise exception 'not allowed' using errcode = '42501'; end if;
  select array_agg(x) into v_metrics from jsonb_array_elements_text(coalesce(spec -> 'metrics', '[]')) x;
  select array_agg(x) into v_dims from jsonb_array_elements_text(coalesce(spec -> 'dims', '[]')) x;
  if coalesce(array_length(v_metrics, 1), 0) = 0 then raise exception 'pick at least one metric'; end if;
  if array_length(v_metrics, 1) > 6 then raise exception 'at most 6 metrics'; end if;
  if coalesce(array_length(v_dims, 1), 0) > 2 then raise exception 'at most 2 dimensions'; end if;
  if v_to < v_from or v_to - v_from > 1100 then raise exception 'the date range must run forwards and cover at most 3 years'; end if;
  select team into v_team from b2c.users where user_id = p_user;
  foreach k in array v_metrics loop
    select * into m from b2c.metric_defs where key = k;
    if m.key is null then raise exception 'unknown metric: %', k; end if;
    if not g = any (m.roles) then raise exception 'metric % is not available to your role', k; end if;
  end loop;
  foreach k in array coalesce(v_dims, '{}') loop
    select * into d from b2c.dim_defs where key = k;
    if d.key is null then raise exception 'unknown dimension: %', k; end if;
  end loop;
  if spec ->> 'compare' = 'previous' then v_cmp_to := v_from - 1; v_cmp_from := v_cmp_to - (v_to - v_from);
  elsif spec ->> 'compare' = 'year' then v_cmp_from := (v_from - interval '1 year')::date; v_cmp_to := (v_to - interval '1 year')::date; end if;

  foreach k in array v_metrics loop
    select * into m from b2c.metric_defs where key = k;
    select * into s from b2c.an_sources where key = m.source;
    v_date := coalesce(m.date_sql, 'now()');
    v_scope := case g
      when 'sales' then case when p_role = 'sales_head'
                             then format('(%1$s in (select w.user_id from b2c.users w where w.role in (''counsellor'', ''sales_head'') and (%2$L is null or w.team = %2$L or w.user_id = %3$L)))', s.actor_sql, v_team, p_user)
                             else format('(%s = %L%s)', s.actor_sql, p_user, case when m.source in ('leads', 'replies', 'journeys', 'commission') then '' else format(' and f.owner_id = %L', p_user) end) end
      else 'true' end;
    v_where := format('%s and (x.lead_id is null or (coalesce(f.is_test, false) = %L and not coalesce(f.deleted, false)))', v_scope, v_test);
    if m.where_sql is not null then v_where := v_where || ' and (' || m.where_sql || ')'; end if;
    for c in select * from jsonb_array_elements(coalesce(spec -> 'filters', '[]')) loop
      select * into d from b2c.dim_defs where key = c ->> 'dim';
      if d.key is null then raise exception 'unknown dimension in a filter: %', c ->> 'dim'; end if;
      if d.sources is not null and not m.source = any (d.sources) then continue; end if;
      if d.money and g = 'sales' and m.source <> 'commission' then raise exception 'that filter is not available to your role'; end if;
      v_expr := '(' || replace(d.expr, ':date', v_date) || ')';
      v_op := coalesce(c ->> 'op', 'eq');
      v_where := v_where || ' and ' || case v_op
        when 'eq' then format('%s::text = %L', v_expr, c ->> 'value')
        when 'neq' then format('%s::text is distinct from %L', v_expr, c ->> 'value')
        when 'in' then format('%s::text = any (%L::text[])', v_expr, (select array_agg(x) from jsonb_array_elements_text(c -> 'value') x))
        when 'not_in' then format('not coalesce(%s::text = any (%L::text[]), false)', v_expr, (select array_agg(x) from jsonb_array_elements_text(c -> 'value') x))
        when 'contains' then format('%s::text ilike %L', v_expr, '%' || (c ->> 'value') || '%')
        when 'is_null' then format('%s is null', v_expr)
        when 'not_null' then format('%s is not null', v_expr)
        else null end;
      if v_where is null then raise exception 'unknown filter operator: %', v_op; end if;
    end loop;
    v_sel := ''; v_grp := '';
    for i in 1 .. coalesce(array_length(v_dims, 1), 0) loop
      select * into d from b2c.dim_defs where key = v_dims[i];
      if d.sources is not null and not m.source = any (d.sources) then
        v_expr := 'null::text';
      elsif d.money and g = 'sales' and m.source <> 'commission' then
        raise exception 'that dimension is not available to your role';
      elsif d.key in ('day', 'week', 'month') and m.date_sql is null then
        v_expr := 'null::text';
      else
        v_expr := '(' || replace(d.expr, ':date', v_date) || ')::text';
      end if;
      v_sel := v_sel || format('%s as d%s, ', v_expr, i);
      v_grp := v_grp || case when v_grp = '' then '' else ', ' end || i;
    end loop;
    v_sql := format('select %s(%s)::numeric as v from %s left join b2c.fact_leads f on f.lead_id = x.lead_id left join b2c.users u on u.user_id = %s where %s%s%s',
                    v_sel, m.agg, s.from_sql, s.actor_sql,
                    v_where,
                    case when m.date_sql is not null then format(' and %1$s >= (%2$L::date::timestamp at time zone ''Asia/Kolkata'') and %1$s < ((%3$L::date + 1)::timestamp at time zone ''Asia/Kolkata'')', m.date_sql, '%FROM%', '%TO%') else '' end,
                    case when v_grp <> '' then ' group by ' || v_grp else '' end);
    v_sqls := v_sqls || jsonb_build_object('metric', k, 'sql', replace(replace(v_sql, '%FROM%', v_from::text), '%TO%', v_to::text));
    execute format('select coalesce(jsonb_agg(jsonb_build_object(''k'', jsonb_build_array(%s), ''v'', q.v)), ''[]'') from (%s) q',
                   coalesce((select string_agg('q.d' || gi, ', ') from generate_series(1, coalesce(array_length(v_dims, 1), 0)) gi), ''),
                   replace(replace(v_sql, '%FROM%', v_from::text), '%TO%', v_to::text)) into v_rows;
    for c in select * from jsonb_array_elements(v_rows) loop
      v_out := jsonb_set(v_out, array[(c -> 'k')::text], coalesce(v_out -> ((c -> 'k')::text), jsonb_build_object('k', c -> 'k')) || jsonb_build_object(k, c -> 'v'));
    end loop;
    if v_cmp_from is not null then
      execute format('select coalesce(jsonb_agg(jsonb_build_object(''k'', jsonb_build_array(%s), ''v'', q.v)), ''[]'') from (%s) q',
                     coalesce((select string_agg('q.d' || gi, ', ') from generate_series(1, coalesce(array_length(v_dims, 1), 0)) gi), ''),
                     replace(replace(v_sql, '%FROM%', v_cmp_from::text), '%TO%', v_cmp_to::text)) into v_rows;
      for c in select * from jsonb_array_elements(v_rows) loop
        v_out := jsonb_set(v_out, array[(c -> 'k')::text], coalesce(v_out -> ((c -> 'k')::text), jsonb_build_object('k', c -> 'k')) || jsonb_build_object(k || '__cmp', c -> 'v'));
      end loop;
    end if;
  end loop;
  select coalesce(jsonb_agg(x order by x -> 'k'), '[]') into v_all_rows from (select value as x from jsonb_each(v_out) limit v_limit) q;
  return jsonb_build_object('rows', v_all_rows, 'metrics', v_metrics, 'dims', coalesce(to_jsonb(v_dims), '[]'), 'from', v_from, 'to', v_to,
                            'compare', case when v_cmp_from is not null then jsonb_build_object('from', v_cmp_from, 'to', v_cmp_to) end,
                            'test', v_test, 'sql', v_sqls, 'scope', case g when 'sales' then case when p_role = 'sales_head' then 'team' else 'own leads' end else 'all' end,
                            'defs', (select jsonb_agg(jsonb_build_object('key', md.key, 'label', md.label, 'fmt', md.fmt, 'higher_is_better', md.higher_is_better, 'counts_leads', md.counts_leads))
                                       from b2c.metric_defs md where md.key = any (v_metrics)));
end $function$;

-- b2c.analytics_drill_ids(uuid,text,jsonb,text,jsonb): production body md5 0be2050eb678ac6c72a0dd17eb43b626
CREATE OR REPLACE FUNCTION b2c.analytics_drill_ids(p_user uuid, p_role text, spec jsonb, p_metric text, p_cell jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r jsonb; v_sql text; v_where text; i int := 0; k text; d b2c.dim_defs; v_ids bigint[]; m b2c.metric_defs; v_date text;
begin
  r := b2c.analytics_exec(p_user, p_role, jsonb_build_object('metrics', jsonb_build_array(p_metric), 'filters', coalesce(spec -> 'filters', '[]'),
                                                             'from', spec -> 'from', 'to', spec -> 'to', 'test', spec -> 'test'));
  select * into m from b2c.metric_defs where key = p_metric;
  v_date := coalesce(m.date_sql, 'now()');
  v_sql := r -> 'sql' -> 0 ->> 'sql';
  v_where := '';
  for k in select jsonb_object_keys(coalesce(p_cell, '{}')) loop
    select * into d from b2c.dim_defs where key = k;
    if d.key is null then raise exception 'unknown dimension: %', k; end if;
    if d.sources is not null and not m.source = any (d.sources) then continue; end if;
    v_where := v_where || case when p_cell ->> k is null then format(' and (%s) is null', replace(d.expr, ':date', v_date))
                               else format(' and (%s)::text = %L', replace(d.expr, ':date', v_date), p_cell ->> k) end;
  end loop;
  v_sql := regexp_replace(v_sql, '^select \(.*?\)::numeric as v from ', 'select distinct x.lead_id from ');
  execute 'select array_agg(lead_id) from (' || v_sql || v_where || ' limit 10000) q' into v_ids;
  return coalesce(v_ids, '{}');
end $function$;

-- b2c.dashboard_save(jsonb): production body md5 de9694ec1a32f39cc5ee27d374991328
CREATE OR REPLACE FUNCTION b2c.dashboard_save(p jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me uuid := b2c.uid(); v bigint := nullif(p ->> 'id', '')::bigint; d b2c.dashboards;
begin
  if b2c.my_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if p ? 'widgets' then perform b2c.dashboard_check(p -> 'widgets'); end if;
  if v is not null then
    select * into d from b2c.dashboards where id = v and archived_at is null;
    if d.id is null then raise exception 'unknown dashboard'; end if;
    if d.owner_id is distinct from me and not (d.owner_id is null and b2c.can('settings')) then
      v := null;
      p := p || jsonb_build_object('name', coalesce(p ->> 'name', d.name), 'widgets', coalesce(p -> 'widgets', d.widgets), 'filters', coalesce(p -> 'filters', d.filters));
    end if;
  end if;
  if v is null then
    if coalesce(trim(p ->> 'name'), '') = '' then raise exception 'name the dashboard'; end if;
    insert into b2c.dashboards (name, description, owner_id, widgets, filters, copied_from, created_by)
    values (left(trim(p ->> 'name'), 120), p ->> 'description', me, coalesce(p -> 'widgets', '[]'), coalesce(p -> 'filters', '{}'), d.id, me)
    returning id into v;
  else
    update b2c.dashboards set name = coalesce(nullif(left(trim(p ->> 'name'), 120), ''), name), description = case when p ? 'description' then p ->> 'description' else description end,
           widgets = coalesce(p -> 'widgets', widgets), filters = coalesce(p -> 'filters', filters), updated_at = now()
     where id = v;
  end if;
  return v;
end $function$;

-- b2c.brief_input(bigint): production body md5 d1ec570e9e2208a4f9ae222211706ad4
CREATE OR REPLACE FUNCTION b2c.brief_input(p_lead bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r b2c.lead_records; s b2c.leads_state; k text[] := b2c.lead_pii(p_lead); v jsonb;
begin
  select * into r from b2c.lead_records where lead_id = p_lead;
  select * into s from b2c.leads_state where lead_id = p_lead;
  if s.lead_id is null then raise exception 'unknown lead'; end if;
  v := jsonb_build_object(
    'lead_id', p_lead,
    'facts', jsonb_strip_nulls(jsonb_build_object(
      'first_name', split_part(trim(coalesce(r.record -> 'student' ->> 'name', '')), ' ', 1),
      'city', r.record -> 'student' ->> 'city', 'state', r.record -> 'student' ->> 'state', 'language', r.record -> 'student' ->> 'preferred_language',
      'interest', r.record -> 'interest', 'education', r.record -> 'education', 'experience', r.record -> 'experience', 'qualification', r.record -> 'qualification',
      'source', r.record -> 'source' ->> 'lead_source', 'handoff_reason', s.handoff_reason, 'lane', s.lane,
      'stage', (select name from b2c.stages where id = s.stage_id), 'sub_stage', s.sub_stage, 'stage_comment', s.stage_comment,
      'temperature', coalesce(s.temperature, case when s.hot then 'hot' end), 'score', s.score, 'contact_attempts', s.contact_attempts,
      'partner_history', case when s.partner_lost is not null or s.lost_by = 'partner' then jsonb_build_object('lost', s.partner_lost, 'providers', s.providers) end,
      'reengaged', case when s.reengaged_at is not null then jsonb_build_object('at', s.reengaged_at, 'trigger', s.reengage_trigger) end)),
    'witty', (select coalesce(jsonb_agg(jsonb_build_object('source', 'witty:' || (x ->> 'id'), 'from', case when x ->> 'direction' in ('in', 'inbound') then 'student' else 'witty' end,
                                                         'text', left(b2c.scrub_pii(x ->> 'content', k), 600))), '[]')
                from jsonb_array_elements(b2c.witty_messages(p_lead, 40)) x),
    'activity', (select coalesce(jsonb_agg(jsonb_build_object('source', 'activity:' || a.id, 'kind', a.kind, 'at', a.at, 'outcome', a.outcome,
                                                            'text', left(b2c.scrub_pii(a.body, k), 400)) order by a.at), '[]')
                   from (select * from b2c.activities a where a.lead_id = p_lead and not a.internal
                           and a.kind in ('call', 'stage', 'note', 'application', 'enrollment', 'correction', 'reenquiry', 'reengaged', 'programme_shared', 'handoff')
                         order by a.at desc limit 20) a));
  v := jsonb_set(v, '{facts}', b2c.scrub_jsonb(v -> 'facts', k));
  return v || jsonb_build_object('facts_hash', b2c.brief_facts_hash(p_lead));
end $function$;

-- b2c.call_record(bigint,text,integer,text,timestamp with time zone,text,text,uuid,boolean,text): production body md5 c8a2f42627a789a0cdc452d2ffe5ceb2
CREATE OR REPLACE FUNCTION b2c.call_record(p_call bigint, p_outcome text, p_duration_s integer, p_note text, p_next_due timestamp with time zone, p_next_kind text, p_next_note text, p_actor uuid, p_suggested boolean, p_how text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c b2c.calls; s b2c.leads_state; v_new_stage smallint; v_new_sub text; v_label text; v_set jsonb := '{}'::jsonb; v_dur int;
begin
  select * into c from b2c.calls where id = p_call;
  v_label := case p_outcome when 'connected' then 'Connected' when 'no_answer' then 'No answer' when 'busy' then 'Busy' when 'switched_off' then 'Switched off'
                            when 'wrong_number' then 'Wrong number' else 'Call back requested' end;
  v_dur := case when p_outcome = 'connected' then greatest(coalesce(p_duration_s, 0), 0) else 0 end;
  update b2c.calls set logged_at = now(), outcome = p_outcome, duration_s = v_dur, note = left(p_note, 2000), auto_logged = p_how <> 'manual' where id = p_call;
  select * into s from b2c.leads_state where lead_id = c.lead_id for update;
  update b2c.leads_state set contact_attempts = contact_attempts + case when c.direction = 'out' then 1 else 0 end,
         first_contacted_at = case when c.direction = 'out' or p_outcome = 'connected' then coalesce(first_contacted_at, c.tapped_at) else first_contacted_at end,
         last_contacted_at = greatest(coalesce(last_contacted_at, c.tapped_at), c.tapped_at),
         last_activity_at = now(), sla_met_at = coalesce(sla_met_at, case when sla_due_at is not null then now() end), updated_at = now()
   where lead_id = c.lead_id;
  if s.stage_id = 1 and p_outcome in ('no_answer', 'busy', 'switched_off', 'wrong_number', 'call_back') then
    v_new_stage := 2; v_new_sub := case p_outcome when 'call_back' then 'Call back requested' else v_label end;
  elsif s.stage_id in (1, 2) and p_outcome = 'connected' then
    v_new_stage := 3; v_new_sub := 'Spoke briefly';
  end if;
  if v_new_stage is not null then
    update b2c.leads_state set stage_id = v_new_stage, sub_stage = v_new_sub, stage_changed_at = now() where lead_id = c.lead_id;
    insert into b2c.activities (lead_id, kind, body, meta, actor_id)
    values (c.lead_id, 'stage', (select name from b2c.stages where id = v_new_stage) || ' · ' || v_new_sub || ' (automatic, from the call)',
            jsonb_build_object('auto', true, 'call_id', p_call), p_actor);
    v_set := jsonb_build_object('stage', (select canon from b2c.stages where id = v_new_stage), 'sub_stage', v_new_sub, 'stage_changed_at', now(),
                                'b2c_stage', (select name from b2c.stages where id = v_new_stage), 'b2c_sub_stage', v_new_sub);
  end if;
  insert into b2c.activities (lead_id, kind, direction, outcome, duration_s, body, meta, actor_id, at)
  values (c.lead_id, 'call', c.direction, p_outcome, v_dur,
          case when c.direction = 'in' then 'Incoming call: ' else 'Call: ' end || v_label
            || case when p_how <> 'manual' and v_dur > 0 then format(' (%s min %s s)', v_dur / 60, v_dur % 60) else '' end
            || coalesce(' · ' || nullif(trim(p_note), ''), ''),
          jsonb_build_object('call_id', p_call, 'provider', c.provider, 'bridged', p_how <> 'manual'), p_actor, c.tapped_at);
  update b2c.tasks set status = 'done', done_at = now(), outcome = v_label
   where id = (select t.id from b2c.tasks t where t.lead_id = c.lead_id and t.status = 'open' and t.kind = 'call' order by t.due_at limit 1);
  perform b2c.add_task(c.lead_id, coalesce(s.owner_id, p_actor), coalesce(p_next_kind, 'call'),
                       coalesce(p_next_note, (b2c.call_suggestion(c.lead_id, p_outcome) ->> 'note')), p_next_due, null, p_suggested, case when p_how = 'manual' then 'call_log' else 'call_auto' end);
  perform b2c.queue_activity(c.lead_id, 'call', c.tapped_at, p_outcome, v_dur, p_note);
  perform b2c.queue_update(c.lead_id, v_set || jsonb_build_object('next_task_due_at', b2c.refresh_next_task(c.lead_id)), false);
  return jsonb_build_object('logged', true, 'moved_to', (select name from b2c.stages where id = v_new_stage), 'sub_stage', v_new_sub,
                            'suggestion', b2c.call_suggestion(c.lead_id, p_outcome));
end $function$;

-- b2c.call_event(jsonb): production body md5 508093ce271ad2fff2e4a4fba24ac01f
CREATE OR REPLACE FUNCTION b2c.call_event(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_provider text := coalesce(p ->> 'provider', 'exotel'); v_status text := p ->> 'status'; v_ref text := nullif(p ->> 'provider_ref', '');
  v_key text; c b2c.calls; v_lead bigint; v_owner uuid; v_user uuid; v_from text := b2c.norm_phone(p ->> 'from'); v_outcome text; v_dur int; v_inserted bigint; r jsonb;
  v_minutes int := coalesce((b2c.setting('telephony') ->> 'missed_call_minutes')::int, 15);
begin
  if v_status not in ('initiated', 'ringing', 'answered', 'completed', 'no_answer', 'busy', 'failed', 'agent_no_answer', 'missed') then
    raise exception 'unknown call status: %', v_status;
  end if;
  v_key := coalesce(nullif(p ->> 'event_key', ''), v_provider || ':' || coalesce(v_ref, p ->> 'call_id', '') || ':' || v_status);
  insert into b2c.call_events (event_key, provider, call_id, status, payload) values (v_key, v_provider, nullif(p ->> 'call_id', '')::bigint, v_status, p)
  on conflict (event_key) do nothing returning id into v_inserted;
  if v_inserted is null then return jsonb_build_object('duplicate', true); end if;

  if nullif(p ->> 'call_id', '') is not null then select * into c from b2c.calls where id = (p ->> 'call_id')::bigint for update; end if;
  if c.id is null and v_ref is not null then select * into c from b2c.calls where provider = v_provider and provider_ref = v_ref for update; end if;

  if c.id is null then
    if coalesce(p ->> 'direction', 'in') <> 'in' then raise exception 'unknown call'; end if;
    select lc.lead_id, s.owner_id into v_lead, v_owner from b2c.lead_contacts lc join b2c.leads_state s on s.lead_id = lc.lead_id and s.deleted_at is null
     where lc.kind = 'phone' and lc.removed_at is null and lc.value_norm = v_from
     order by (s.status = 'active') desc, s.updated_at desc limit 1;
    if v_lead is null then
      insert into b2c.unknown_calls (provider, provider_ref, from_number, status) values (v_provider, v_ref, coalesce(p ->> 'from', ''), v_status);
      if v_status in ('missed', 'no_answer', 'agent_no_answer') then
        perform b2c.notify_admins('missed_call', 'Missed call from an unknown number', p ->> 'from', '/w/connectors', null, 'unknown:' || coalesce(v_ref, v_key), false);
      end if;
      update b2c.call_events set call_id = null where id = v_inserted;
      return jsonb_build_object('unknown_number', true);
    end if;
    select user_id into v_user from b2c.users where is_active and b2c.norm_phone(phone) = b2c.norm_phone(p ->> 'agent') limit 1;
    insert into b2c.calls (lead_id, user_id, number, provider, provider_ref, direction, status, from_number, tapped_at)
    values (v_lead, coalesce(v_user, v_owner), coalesce(p ->> 'from', ''), v_provider, v_ref, 'in', v_status, p ->> 'from', now())
    returning * into c;
    update b2c.call_events set call_id = c.id where id = v_inserted;
  end if;

  update b2c.calls set provider_ref = coalesce(provider_ref, v_ref), status = v_status, provider_status = coalesce(p ->> 'provider_status', provider_status),
         bridged_at = case when v_status = 'answered' then coalesce(bridged_at, now()) else bridged_at end,
         cost = coalesce(nullif(p ->> 'cost', '')::numeric, cost)
   where id = c.id;
  if v_status not in ('completed', 'no_answer', 'busy', 'failed', 'agent_no_answer', 'missed') or c.ended_at is not null then
    return jsonb_build_object('call_id', c.id, 'status', v_status);
  end if;

  v_dur := greatest(coalesce(nullif(p ->> 'duration_s', '')::int, 0), 0);
  update b2c.calls set ended_at = now(),
         recording_status = case when nullif(p ->> 'recording_url', '') is not null then 'pending' else recording_status end,
         recording_url = coalesce(nullif(p ->> 'recording_url', ''), recording_url)
   where id = c.id;
  if c.direction = 'in' and (v_status in ('missed', 'no_answer', 'agent_no_answer', 'busy', 'failed') or (v_status = 'completed' and v_dur = 0)) then
    update b2c.calls set logged_at = now(), auto_logged = true where id = c.id;
    insert into b2c.activities (lead_id, kind, direction, body, meta, actor_id, at)
    values (c.lead_id, 'call', 'in', 'Missed call from the student', jsonb_build_object('call_id', c.id, 'provider', c.provider, 'missed', true), null, c.tapped_at);
    select owner_id into v_owner from b2c.leads_state where lead_id = c.lead_id;
    perform b2c.add_task(c.lead_id, v_owner, 'call', 'Call back: missed call from the student', now() + make_interval(mins => v_minutes), null, false, 'missed_call');
    perform b2c.queue_update(c.lead_id, jsonb_build_object('next_task_due_at', b2c.refresh_next_task(c.lead_id)), false);
    if v_owner is not null then
      perform b2c.notify(v_owner, 'missed_call', 'Missed call: call back', null, '/s/leads/' || c.lead_id, c.lead_id, 'missed:' || c.id);
    else
      perform b2c.notify_admins('missed_call', 'Missed call from an unassigned lead', null, '/w/leads/' || c.lead_id, c.lead_id, 'missed:' || c.id, false);
    end if;
    return jsonb_build_object('call_id', c.id, 'missed', true);
  end if;
  if v_status = 'agent_no_answer' then
    update b2c.calls set logged_at = now(), auto_logged = true where id = c.id;
    insert into b2c.activities (lead_id, kind, direction, body, meta, actor_id, at)
    values (c.lead_id, 'call', 'out', 'Call not placed: your phone did not answer', jsonb_build_object('call_id', c.id, 'provider', c.provider, 'not_placed', true), c.user_id, c.tapped_at);
    if c.user_id is not null then
      perform b2c.notify(c.user_id, 'call_not_placed', 'Your phone did not answer', 'The student was not called. Tap Call again when you are ready.', '/s/leads/' || c.lead_id, c.lead_id, 'np:' || c.id);
    end if;
    return jsonb_build_object('call_id', c.id, 'not_placed', true);
  end if;
  v_outcome := case v_status when 'completed' then case when v_dur > 0 then 'connected' else 'no_answer' end
                             when 'no_answer' then 'no_answer' when 'busy' then 'busy' else 'switched_off' end;
  r := b2c.call_record(c.id, v_outcome, v_dur, null, now() + make_interval(mins => (b2c.call_suggestion(c.lead_id, v_outcome) ->> 'in_minutes')::int),
                       b2c.call_suggestion(c.lead_id, v_outcome) ->> 'kind', null, c.user_id, true, 'bridged');
  return jsonb_build_object('call_id', c.id, 'outcome', v_outcome) || r;
end $function$;

-- b2c.calendar_queue(bigint): production body md5 940318ca08ff9b780381097ea87615f6
CREATE OR REPLACE FUNCTION b2c.calendar_queue(p_task bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t b2c.tasks; v_on boolean; ce b2c.calendar_events; v_want text;
begin
  select * into t from b2c.tasks where id = p_task;
  if t.id is null then return; end if;
  select calendar_sync into v_on from b2c.users where user_id = t.owner_id and is_active;
  v_want := case when t.status = 'open' and coalesce(v_on, false) then 'upsert' else 'remove' end;
  select * into ce from b2c.calendar_events where task_id = p_task;
  if ce.task_id is null then
    if v_want = 'remove' then return; end if;
    insert into b2c.calendar_events (task_id, user_id, want) values (p_task, t.owner_id, 'upsert');
    return;
  end if;
  if ce.user_id is distinct from t.owner_id and ce.event_id is not null then
    update b2c.calendar_events set old_user_id = ce.user_id, old_event_id = ce.event_id, event_id = null, etag = null where task_id = p_task;
  end if;
  update b2c.calendar_events set user_id = t.owner_id, want = v_want, state = 'pending', attempts = 0, error = null, updated_at = now() where task_id = p_task;
end $function$;

-- b2c.support_mail_take(integer): production body md5 5f5e468383407127f8b97494079b8ed2
CREATE OR REPLACE FUNCTION b2c.support_mail_take(p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if jsonb_array_length(coalesce(b2c.setting('support') -> 'developer_emails', '[]')) = 0 then return '[]'; end if;
  with due as (select m.id from b2c.support_messages m where m.to_developer and m.mailed_at is null and m.mail_attempts < 6
                and m.created_at <= now() - make_interval(secs => power(2, m.mail_attempts)::int * 30 - 30)
                order by m.id limit p_limit for update skip locked),
       x as (update b2c.support_messages m set mail_attempts = m.mail_attempts + 1 from due where m.id = due.id returning m.*)
  select coalesce(jsonb_agg(jsonb_build_object('message_id', x.id, 'ticket_id', t.id, 'number', b2c.support_number(t.id), 'subject', t.subject, 'kind', t.kind,
           'priority', t.priority, 'status', t.status, 'page', t.page, 'first', (select min(id) from b2c.support_messages where ticket_id = t.id) = x.id,
           'body', x.body, 'urls', x.urls, 'attachments', x.attachments, 'status_to', x.status_to,
           'author', coalesce(a.full_name, ''), 'author_email', a.email, 'author_role', a.role, 'by', u.full_name, 'by_email', u.email, 'by_role', u.role,
           'developer_emails', b2c.setting('support') -> 'developer_emails', 'mailbox', b2c.setting('support') ->> 'mailbox')), '[]') into v
    from x join b2c.support_tickets t on t.id = x.ticket_id join b2c.users u on u.user_id = t.created_by left join b2c.users a on a.user_id = x.author_id;
  return v;
end $function$;

