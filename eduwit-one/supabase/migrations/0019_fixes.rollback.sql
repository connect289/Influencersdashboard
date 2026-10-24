-- Rollback of 0019: the earlier versions of the three functions 0019 replaced (0018's tick_app_call and ai_brief_stats,
-- 0011's ui_proposal_decide), copied verbatim, then everything 0019 added: its functions (the fixer's among them), the
-- fixer's grants on the apps, the action columns and the catalogue. Action rows and the proposals the fixes opened stay
-- (they are history); the step and run columns go with the rest.

create or replace function one.tick_app_call() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v jsonb;
begin
  v := jsonb_build_object('app', coalesce(one.job_call('/api/internal/tick')::text, 'not_configured'));
  begin
    v := v || one.ai_step();
  exception when others then
    v := v || jsonb_build_object('ai_error', sqlerrm);
  end;
  return v;
exception when others then
  return jsonb_build_object('app_error', sqlerrm);
end $$;

-- The numbers a brief is written from: the IST day before p_for_date (the brief built at 02:30 IST on a day reports
-- the day before). Kept on the brief as its stats, so the page shows what the text was built from.
create or replace function one.ai_brief_stats(p_for_date date) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_from timestamptz := ((p_for_date - 1)::timestamp) at time zone 'Asia/Kolkata';
  v_to timestamptz := (p_for_date::timestamp) at time zone 'Asia/Kolkata';
  v jsonb;
  v_witty jsonb;
begin
  v := jsonb_build_object(
    'window', jsonb_build_object('day_ist', p_for_date - 1, 'from', v_from, 'to', v_to),
    'incidents_opened', (select coalesce(jsonb_agg(jsonb_build_object('app', app, 'severity', severity, 'n', n) order by app, severity), '[]')
                           from (select app, severity, count(*) as n from one.incidents
                                  where opened_at >= v_from and opened_at < v_to and check_id <> 'ONE-SYNTH' group by 1, 2) s),
    'p1', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'check_id', i.check_id, 'app', i.app, 'title', i.title, 'opened_at', i.opened_at,
                                                        'resolved_at', i.resolved_at, 'resolution', i.resolution, 'summary', i.summary,
                                                        'minutes_open', round(extract(epoch from coalesce(i.resolved_at, now()) - i.opened_at) / 60))
                                     order by i.opened_at), '[]')
             from (select * from one.incidents where severity = 'P1' and opened_at >= v_from and opened_at < v_to order by opened_at limit 30) i),
    'resolved', (select coalesce(jsonb_object_agg(coalesce(resolution, '?'), n), '{}')
                   from (select resolution, count(*) as n from one.incidents where resolved_at >= v_from and resolved_at < v_to and check_id <> 'ONE-SYNTH' group by 1) s),
    'open_now', jsonb_build_object(
       'by_severity', (select coalesce(jsonb_object_agg(severity, n), '{}') from (select severity, count(*) as n from one.incidents where resolved_at is null group by 1) s),
       'oldest', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'severity', i.severity, 'app', i.app, 'title', i.title, 'opened_at', i.opened_at,
                                                              'acknowledged', i.acknowledged_at is not null) order by i.opened_at), '[]')
                    from (select * from one.incidents where resolved_at is null and check_id <> 'ONE-SYNTH' order by opened_at limit 10) i)),
    'checks_failing_now', (select coalesce(jsonb_agg(jsonb_build_object('check_id', x.check_id, 'app', x.app, 'severity', x.severity, 'status', x.status)
                                                     order by x.severity, x.check_id), '[]')
                             from (select distinct on (r.check_id) r.check_id, r.status, c.app, c.severity
                                     from one.results r join one.checks c on c.id = r.check_id
                                    where c.enabled and r.ran_at > now() - interval '1 day'
                                    order by r.check_id, r.ran_at desc) x where x.status <> 'ok'),
    'checks_off', (select coalesce(jsonb_object_agg(reason, n), '{}')
                     from (select coalesce(split_part(disabled_reason, ':', 1), 'off') as reason, count(*) as n from one.checks where not enabled group by 1) s),
    'tests', (select coalesce(jsonb_agg(jsonb_build_object('test', test_id, 'runs', n, 'passed', ok_n, 'failed', bad_n, 'last_error', last_error) order by test_id), '[]')
                from (select test_id, count(*) as n, count(*) filter (where ok) as ok_n, count(*) filter (where ok = false) as bad_n,
                             (array_agg(error order by started_at desc) filter (where ok = false))[1] as last_error
                        from one.test_runs where started_at >= v_from and started_at < v_to group by 1) s),
    'deliveries', (select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'status', status, 'n', n) order by kind, status), '[]')
                     from (select kind, status, count(*) as n from one.deliveries where created_at >= v_from and created_at < v_to group by 1, 2) s),
    'ai', jsonb_build_object(
       'spend_inr', (select coalesce(sum(cost_inr), 0) from one.ai_calls where created_at >= v_from and created_at < v_to),
       'calls', (select count(*) from one.ai_calls where created_at >= v_from and created_at < v_to),
       'tasks', (select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'status', status, 'n', n) order by kind, status), '[]')
                   from (select kind, status, count(*) as n from one.ai_tasks where created_at >= v_from and created_at < v_to group by 1, 2) s)),
    'proposals', jsonb_build_object(
       'opened', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'kind', p.kind, 'app', p.app, 'title', p.title, 'source', p.source, 'risk', p.risk) order by p.id), '[]')
                    from (select * from one.proposals where created_at >= v_from and created_at < v_to order by id limit 20) p),
       'open_total', (select count(*) from one.proposals where status = 'open')),
    'events_by_app', (select coalesce(jsonb_object_agg(app, n), '{}') from (select app, count(*) as n from one.events where occurred_at >= v_from and occurred_at < v_to group by 1) s),
    'heartbeats_down', (select coalesce(jsonb_agg(h.component order by h.component), '[]') from one.heartbeats h
                         where h.last_error_at is not null and h.last_error_at > coalesce(h.last_ok_at, '-infinity')));
  begin
    perform set_config('lock_timeout', '2s', true);
    select e into v_witty from jsonb_array_elements(one.embed_data('witty.replies')) e where e ->> 'day' = (p_for_date - 1)::text;
    perform set_config('search_path', '', true);
    v := v || jsonb_build_object('witty_replies', v_witty);
  exception when others then
    perform set_config('search_path', '', true);
    v := v || jsonb_build_object('witty_replies_error', left(sqlerrm, 160));
  end;
  v := one.redact(v, one.pii_keys());
  -- Answers pinned to this brief (Ask page). Questions are staff's own words; the app masks them like everything else.
  return v || jsonb_build_object('pins', (select coalesce(jsonb_agg(jsonb_build_object('question', t.input ->> 'question', 'answer', t.result ->> 'answer')
                                                                    order by p.created_at), '[]')
                                            from one.brief_pins p join one.ai_tasks t on t.id = p.task_id where p.for_date = p_for_date));
end $$;

-- Approve (the owner, for every fix or config proposal and whatever touches money, allocation, live switches, partner
-- mappings, prompts, settings or security: one.proposal_sensitive), reject with a note, or snooze. A snoozed proposal
-- comes back to the queue when the snooze ends (one.nightly), with a fresh expiry; the builder's never expire.
-- Approving with edited arguments keeps both versions in the audit. Approval records the decision; running an approved
-- change through the owning app's own function arrives with the fixes (phase 7).
create or replace function one.ui_proposal_decide(p_id bigint, p_decision text, p_note text default null, p_change jsonb default null,
                                                  p_snooze_days integer default null, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_p one.proposals;
  v_change jsonb;
begin
  select * into v_p from one.proposals where id = p_id for update;
  if not found or v_p.status not in ('open', 'snoozed') then
    raise exception 'proposal % is not open', p_id using errcode = 'P0002';
  end if;
  case p_decision
    when 'approve' then
      v_change := coalesce(p_change, v_p.change);
      if one.proposal_sensitive(v_p.kind, v_p.change) or one.proposal_sensitive(v_p.kind, v_change) then
        perform one.ui_require('owner');
      end if;
      update one.proposals set status = 'approved', decided_by = v_actor, decided_at = now(), decision_note = left(p_note, 1000),
                               change = v_change, check_due_at = now() + interval '1 day'
       where id = p_id;
    when 'reject' then
      update one.proposals set status = 'rejected', decided_by = v_actor, decided_at = now(), decision_note = one.ui_reason(p_note) where id = p_id;
    when 'snooze' then
      if coalesce(p_snooze_days, 0) not between 1 and 30 then
        raise exception 'snooze for 1 to 30 days' using errcode = '22023';
      end if;
      update one.proposals set status = 'snoozed', decision_note = left(p_note, 1000), expires_at = now() + make_interval(days => p_snooze_days)
       where id = p_id;
    else
      raise exception 'decision must be approve, reject or snooze' using errcode = '22023';
  end case;
  perform one.ui_audit_write(v_actor, 'proposal.' || p_decision, 'proposal:' || p_id,
                             jsonb_build_object('status', v_p.status, 'change', v_p.change),
                             jsonb_build_object('note', p_note, 'change', v_change, 'snooze_days', p_snooze_days), p_request_id);
  return jsonb_build_object('ok', true);
end $$;

delete from one.api_grants where fn in ('one.app_fixes_claim(text)', 'one.app_fix_report(bigint,boolean,jsonb)', 'one.ui_fixes()',
                                        'one.ui_fix_set(text,jsonb,text,text)', 'one.ui_fix_dry_run(text,bigint,text)');

drop function if exists one.fix_outbox_w2(bigint,boolean);
drop function if exists one.fix_cache_w2(bigint,boolean);
drop function if exists one.fix_n8n_retry(bigint,boolean);
drop function if exists one.fix_outbox_b2b(bigint,boolean);
drop function if exists one.fix_cursor_b2c(bigint,boolean);
drop function if exists one.fix_webhook_rekick(bigint,boolean);
drop function if exists one.fix_inbox_retry(bigint,boolean);
drop function if exists one.fix_outbox_b2c(bigint,boolean);
drop function if exists one.fix_outbox_web(bigint,boolean);
drop function if exists one.fix_catalog_poll(bigint,boolean);
drop function if exists one.fix_cache_b2c(bigint,boolean);
drop function if exists one.ui_fixes();
drop function if exists one.ui_fix_set(text,jsonb,text,text);
drop function if exists one.ui_fix_dry_run(text,bigint,text);
drop function if exists one.app_fixes_claim(text);
drop function if exists one.app_fix_report(bigint,boolean,jsonb);
drop function if exists one.proposal_execute(bigint,text);
drop function if exists one.fixes_step();
drop function if exists one.fix_verify_due();
drop function if exists one.proposals_verify_due();
drop function if exists one.fix_run(text,bigint,boolean,text,bigint,jsonb);
drop function if exists one.fix_propose(one.fixes,one.incidents,jsonb,text);
drop function if exists one.fix_act(text,jsonb);
drop function if exists one.fix_plan_within(jsonb,jsonb);
drop function if exists one.fix_plan(text,one.incidents);
drop function if exists one.fix_record(text,bigint,text,text,boolean,jsonb,jsonb,text,text,timestamptz,bigint);
drop function if exists one.incident_escalate(bigint,text);
drop function if exists one.fix_grants(text);
drop function if exists one.fix_window();
drop function if exists one.fixer_b2c_sync();
drop function if exists one.fixer_outbox_kick();
drop function if exists one.fixer_b2b_outbox_retry(bigint);
drop function if exists one.fixer_inbox_retry();
drop function if exists one.fixer_b2c_outbox();
drop function if exists one.fixer_web_outbox(bigint[]);
drop function if exists one.fixer_catalog_poll();
drop function if exists one.fixer_programme_cache();

do $$
begin
  if to_regprocedure('b2b.b2c_sync_tick(integer)') is not null then
    revoke execute on function b2b.b2c_sync_tick(integer) from eduwit_one_fixer;
  end if;
  if to_regprocedure('b2b.outbox_kick()') is not null then
    revoke execute on function b2b.outbox_kick() from eduwit_one_fixer;
  end if;
  if to_regprocedure('b2b.outbox_retry(bigint)') is not null then
    revoke execute on function b2b.outbox_retry(bigint) from eduwit_one_fixer;
  end if;
  if to_regprocedure('b2c.inbox_retry(integer)') is not null then
    revoke execute on function b2c.inbox_retry(integer) from eduwit_one_fixer;
  end if;
  if to_regprocedure('b2c.outbox_unstick()') is not null then
    revoke execute on function b2c.outbox_unstick() from eduwit_one_fixer;
  end if;
  if to_regprocedure('b2c.job_call(text)') is not null then
    revoke execute on function b2c.job_call(text) from eduwit_one_fixer;
  end if;
  if to_regprocedure('b2c.programme_cache_refresh(boolean)') is not null then
    revoke execute on function b2c.programme_cache_refresh(boolean) from eduwit_one_fixer;
  end if;
  if to_regprocedure('public.web_outbox_retry(bigint,uuid)') is not null then
    revoke execute on function public.web_outbox_retry(bigint, uuid) from eduwit_one_fixer;
  end if;
  if to_regprocedure('public.web_job_call(text,integer)') is not null then
    revoke execute on function public.web_job_call(text, integer) from eduwit_one_fixer;
  end if;
  if to_regprocedure('public.web_catalog_poll()') is not null then
    revoke execute on function public.web_catalog_poll() from eduwit_one_fixer;
  end if;
  if exists (select 1 from pg_namespace where nspname = 'public') then
    revoke usage on schema public from eduwit_one_fixer;
  end if;
  if exists (select 1 from pg_namespace where nspname = 'b2b') then
    revoke usage on schema b2b from eduwit_one_fixer;
  end if;
  if exists (select 1 from pg_namespace where nspname = 'b2c') then
    revoke usage on schema b2c from eduwit_one_fixer;
  end if;
end $$;

drop index if exists one.actions_fix_time_idx;
alter table one.actions drop column if exists proposal_id;
alter table one.actions drop column if exists claimed_by;
alter table one.actions drop column if exists claimed_at;
alter table one.actions drop column if exists verify_at;
alter table one.actions drop column if exists run_key;
alter table one.actions drop column if exists step;
drop table if exists one.fixes;

revoke eduwit_one_fixer from current_user;
call one.apply_grants();
