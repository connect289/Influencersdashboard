-- M34b (30 Oct 2026, audit, Eduwit One B2B-11): a nightly training run that has too few matured outcomes is logged as
-- ml.training_skipped instead of ml.model_failed. Until partners have 40 outcomes matured for 60 days, ml_train refuses
-- every night ('not enough matured outcomes to train', SQLSTATE 22023) and the alert for a failed model fired each time
-- (22 times in production between 8 and 30 Oct). The model row is still marked failed with the reason, as before, and
-- every other training error, and a run that never finished, still log ml.model_failed. Same body as m25b_ml_training.sql
-- otherwise; the cron job and its timeout are untouched.
-- Re-appliable. Checked by supabase/tests/test_m25_ml.sql (training_fails_cleanly) and test_m34_audit_fixes.sql.

create or replace function b2b.ml_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.ml_cfg();
  m b2b.ml_models;
  v_hour int := extract(hour from now() at time zone 'Asia/Kolkata')::int;
  v_res jsonb := '{}';
  v_last timestamptz;
begin
  if not pg_try_advisory_xact_lock(hashtext('b2b.ml_tick')) then return '{"busy":true}'; end if;
  perform set_config('b2b.actor', 'engine', true);
  -- a run that never finished (cancelled or timed out: WHEN OTHERS cannot catch query_canceled) frees the queue
  for m in update b2b.ml_models
              set status = 'failed', error = 'training did not finish within an hour (cancelled or timed out)',
                  status_at = now(), status_by = 'engine'
            where status = 'training' and created_at < now() - interval '1 hour'
           returning * loop
    perform b2b.log_event('ml.model_failed', null, null, null, jsonb_build_object('version', m.version, 'error', 'did not finish within an hour'));
    v_res := v_res || jsonb_build_object('stuck_failed', m.version);
  end loop;
  -- nightly training when the auto switch is on and nothing was trained in the last 20 hours
  if coalesce((cfg ->> 'auto_train')::boolean, true) and v_hour = coalesce((cfg ->> 'train_hour_ist')::int, 2)
     and not exists (select 1 from b2b.ml_models where status = 'training')
     and not exists (select 1 from b2b.ml_models where created_at > now() - interval '20 hours') then
    insert into b2b.ml_models (version, requested_by) values ('v' || to_char(now() at time zone 'Asia/Kolkata', 'YYYYMMDD-HH24MISS'), 'nightly');
  end if;
  select * into m from b2b.ml_models where status = 'training' order by id limit 1;
  if m.id is not null then
    begin
      v_res := v_res || jsonb_build_object('trained', b2b.ml_train(m.id));
    exception when others then
      update b2b.ml_models set status = 'failed', error = left(sqlerrm, 500), status_at = now(), status_by = 'engine' where id = m.id;
      -- M34b: too few matured outcomes (ml_train's own 22023 refusal) is a skipped run, not a failed model
      if sqlstate = '22023' and sqlerrm like 'not enough matured outcomes%' then
        perform b2b.log_event('ml.training_skipped', null, null, null, jsonb_build_object('version', m.version, 'reason', left(sqlerrm, 300)));
      else
        perform b2b.log_event('ml.model_failed', null, null, null, jsonb_build_object('version', m.version, 'error', left(sqlerrm, 300)));
      end if;
      v_res := v_res || jsonb_build_object('failed', m.version, 'error', left(sqlerrm, 300));
    end;
  end if;
  select max(occurred_at) into v_last from b2b.events where type = 'ml.monitored';
  if v_last is null or v_last < now() - interval '23 hours' then
    if exists (select 1 from b2b.ml_models where status in ('champion', 'challenger')) then
      v_res := v_res || jsonb_build_object('monitor', b2b.ml_monitor());
    end if;
    perform b2b.log_event('ml.monitored', null, null, null, '{}');
  end if;
  return v_res;
end $fn$;
revoke execute on function b2b.ml_tick() from public, anon, authenticated;
grant execute on function b2b.ml_tick() to service_role;

-- rollback: re-run the create or replace function b2b.ml_tick() of m25b_ml_training.sql (lines 383 to 427), which logs
-- ml.model_failed for every training error, the insufficient-data refusal included.
