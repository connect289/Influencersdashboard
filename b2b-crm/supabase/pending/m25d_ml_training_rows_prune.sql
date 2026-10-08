-- PENDING (hand-applied in the Supabase SQL editor): M25d, nightly prune of b2b.ml_training_rows.
-- Every training run (nightly) copies up to 50,000 matured outcomes into ml_training_rows, so the table grows without
-- bound. This keeps the rows of each model in use (training, shadow, challenger, champion), of each past champion (a
-- rollback target) and of each model retired or failed less than 30 days ago, and removes the rest every night at
-- 03:10 IST, after the 02:00 IST nightly training (cron job b2b-ml-prune).
-- It is a pending file because it contains DELETE, which the Supabase connector refuses in a migration.
--   Staging: apply now (after m25b).
--   Production: in the promotion window, right after m30a and before m31a0. The window's 'pause every b2b-* cron job'
--   step (the second pause, after m24a...m30a) includes b2b-ml-prune: cron.schedule below creates the job active.
-- Re-applying is safe: the function is replaced and the job is scheduled again.

create or replace function b2b.ml_training_rows_prune()
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare v_n int;
begin
  -- keep rows for models in use (shadow, challenger, champion, training), past champions (rollback targets)
  -- and models retired less than 30 days ago
  delete from b2b.ml_training_rows r
   using b2b.ml_models m
   where m.id = r.model_id and m.status in ('retired', 'failed') and not m.was_champion
     and m.status_at < now() - interval '30 days';
  get diagnostics v_n = row_count;
  if v_n > 0 then
    perform b2b.log_event('ml.training_rows_pruned', null, null, null, jsonb_build_object('rows', v_n));
  end if;
  return v_n;
end $fn$;
revoke execute on function b2b.ml_training_rows_prune() from public, anon, authenticated;
grant execute on function b2b.ml_training_rows_prune() to service_role;

do $cron$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'b2b-ml-prune';
  perform cron.schedule('b2b-ml-prune', '40 21 * * *', 'select b2b.ml_training_rows_prune()');  -- 03:10 IST, after the 02:00 IST nightly training
end $cron$;

select b2b.log_event('migration.manual_applied', null, null, null, jsonb_build_object('file', 'pending/m25d_ml_training_rows_prune'));
