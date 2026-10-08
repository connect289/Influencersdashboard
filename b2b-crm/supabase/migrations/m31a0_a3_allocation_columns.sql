-- M31a0: Addendum 3, step 0 (docs/B2B_CRM_ADDENDUM_3.md). Only the new b2b.allocations columns, in one metadata-only
-- statement, plus two NOT VALID checks (m31a validates them).
--   Why a file of its own: public.w2_crm_owned (live Witty) reads b2b.allocations on every inbound student message. An
--   ALTER TABLE takes an ACCESS EXCLUSIVE lock, so Witty's reads queue behind it for as long as it waits and runs. Every
--   column below is nullable or has a constant default, so nothing is rewritten or scanned and the lock is held for
--   milliseconds. lock_timeout makes the file fail fast (and leave nothing behind) instead of stalling Witty behind a long
--   reader: re-run it when it times out. It is idempotent.
--   Runbook: before applying, pause the b2b-* cron jobs and check pg_stat_activity for long readers of b2b.allocations.
--   Columns (filled from m31f on; m31a fills origin and the claim columns for existing rows):
--     stage, score_inr, p_enroll, effort_factor, sla_factor     the Stage A/B/C score of a partner allocation
--     segment_exact, interest_rank, origin                      course|level|mode|u<id>; the interest used; auto, pass,
--                                                              to_partners, requalify, reroute or sandbox
--     paid, paid_platform, campaign_id, cause                   the attribution label (no routing effect); the cause
--                                                              behind no_capacity and manual_route_failed
--     claim_existing_record_id, claim_existing_created_at,     the duplicate claim's proof (PART 5.3)
--     claim_proof_ok
--     lost_at, lost_grace_until, lost_detail, lost_prev_stage, the 7-day lost grace (PART 6.1): the allocation keeps
--     lost_revived_at, lost_count                              status accepted (or pushed) while it runs
--     recall_reason                                            the Admin's re-route reason (PART 6.2)
--     model_version                                            the ML model that decided Stage C P(enrol), if any

set local lock_timeout = '3s';
set local statement_timeout = '30s';

alter table b2b.allocations
  add column if not exists stage                     text,
  add column if not exists score_inr                 numeric(14, 2),
  add column if not exists p_enroll                  numeric(6, 5),
  add column if not exists effort_factor             numeric(5, 4),
  add column if not exists sla_factor                numeric(5, 4),
  add column if not exists segment_exact             text,
  add column if not exists interest_rank             smallint,
  add column if not exists origin                    text,
  add column if not exists paid                      boolean,
  add column if not exists paid_platform             text,
  add column if not exists campaign_id               text,
  add column if not exists cause                     text,
  add column if not exists claim_existing_record_id  text,
  add column if not exists claim_existing_created_at timestamptz,
  add column if not exists claim_proof_ok            boolean,
  add column if not exists lost_at                   timestamptz,
  add column if not exists lost_grace_until          timestamptz,
  add column if not exists lost_detail               jsonb,
  add column if not exists lost_prev_stage           text,
  add column if not exists lost_revived_at           timestamptz,
  add column if not exists lost_count                int not null default 0,
  add column if not exists recall_reason             text,
  add column if not exists model_version             text;

do $chk$
begin
  if not exists (select 1 from pg_constraint where conname = 'allocations_stage_check' and conrelid = 'b2b.allocations'::regclass) then
    alter table b2b.allocations add constraint allocations_stage_check check (stage in ('A', 'B', 'C')) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'allocations_origin_check' and conrelid = 'b2b.allocations'::regclass) then
    alter table b2b.allocations add constraint allocations_origin_check
      check (origin in ('auto', 'pass', 'to_partners', 'requalify', 'reroute', 'sandbox')) not valid;
  end if;
end $chk$;
