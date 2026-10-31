-- After the Supabase Pro plan is active (D-112). NOT a migration yet: it waits in supabase/pending/ so no apply can run
-- it early. Once the organisation is on Pro (8 GB disk, daily backups), move this file and its rollback into
-- supabase/migrations/ under the next free number, rehearse the set, then apply it.
-- What it does: Eduwit One's history goes back to the lengths it had before 0029 (ok results 14 days, failures 90,
-- copied events 180, tick reports and app_report audit rows 30), and PLAT-10 measures the database against Pro's 8 GB
-- disk instead of the Free plan's 500 MB read-only limit (P2 at 80 %, P1 at 90 %, unchanged). Each setting moves only
-- while its row is still a seed version, as 0029 did: a value a person set stays, and the file says so.

do $$
declare
  v_row one.settings;
begin
  select * into v_row from one.settings where key = 'retention';
  if not found then
    raise exception 'after Pro: no retention setting; 0007 must be applied first';
  end if;
  if v_row.actor <> 'seed' then
    raise notice 'after Pro: the retention setting was changed by % (version %), so it is left as it is', v_row.actor, v_row.version;
  else
    perform one.settings_put('retention', v_row.value || '{"results_days": 90, "events_days": 180, "ok_results_days": 14, "runs_days": 30, "app_report_days": 30}',
                             'seed', 'D-112 (after Pro): history back to its lengths before 0029 on the Pro plan''s 8 GB database');
  end if;
  select * into v_row from one.settings where key = 'thresholds';
  if not found then
    raise exception 'after Pro: no thresholds setting; 0007 must be applied first';
  end if;
  if v_row.actor <> 'seed' then
    raise notice 'after Pro: the thresholds setting was changed by % (version %), so it is left as it is', v_row.actor, v_row.version;
  else
    perform one.settings_put('thresholds', v_row.value || '{"db_size_limit_mb": 8192}',
                             'seed', 'D-112 (after Pro): PLAT-10 measures against the Pro plan''s 8 GB disk');
  end if;
end $$;
