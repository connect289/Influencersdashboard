-- Wraps a migration file, before it, in the same transaction (see app-fingerprint.sql).
\set fp_phase before
\ir app-fingerprint.sql
