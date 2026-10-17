-- web1_foundation behaviour: settings history + audit, outbox idempotency/claim/backoff/dead-letter, limiter, health.
begin;
create temp table r (ok boolean, name text) on commit drop;

-- settings
insert into r select (public.web_settings_all() ->> 'web_advisor_enabled') = 'false', 'advisor flag defaults to off';
select public.web_settings_set('web_advisor_enabled', 'true'::jsonb, null, 'test@eduwit.in');
insert into r select (public.web_settings_all() ->> 'web_advisor_enabled') = 'true', 'setting updated';
insert into r select exists (select 1 from public.web_settings_history where key = 'web_advisor_enabled' and value = 'false'::jsonb), 'previous value kept in history';
insert into r select exists (select 1 from public.web_audit_log where action = 'settings.update' and entity_id = 'web_advisor_enabled'), 'settings change audited';
do $$ begin
  perform public.web_settings_set('no_such_setting', '1'::jsonb);
  insert into r values (false, 'unknown setting rejected');
exception when others then insert into r values (true, 'unknown setting rejected');
end $$;

-- outbox: idempotent enqueue
insert into r select public.web_outbox_enqueue('email_confirmation', 'test:dedupe:1', '{"a":1}') = public.web_outbox_enqueue('email_confirmation', 'test:dedupe:1', '{"a":2}'), 'enqueue is idempotent on dedupe key';
insert into r select (select payload ->> 'a' from public.web_outbox where dedupe_key = 'test:dedupe:1') = '1', 'first payload wins';
-- claim then fail with backoff
create temp table claimed on commit drop as select * from public.web_outbox_claim(10, array['email_confirmation']);
insert into r select (select count(*) from claimed where dedupe_key = 'test:dedupe:1') = 1, 'claimed once';
insert into r select (select count(*) from public.web_outbox_claim(10, array['email_confirmation']) c where c.dedupe_key = 'test:dedupe:1') = 0, 'claimed row not re-claimed while locked';
insert into r select public.web_outbox_fail((select id from claimed where dedupe_key = 'test:dedupe:1'), 'smtp down') = 'pending', 'failure reschedules';
insert into r select (select next_attempt_at > now() + interval '50 seconds' from public.web_outbox where dedupe_key = 'test:dedupe:1'), 'backoff applied';
update public.web_outbox set attempts = max_attempts where dedupe_key = 'test:dedupe:1';
insert into r select public.web_outbox_fail((select id from public.web_outbox where dedupe_key = 'test:dedupe:1'), 'still down') = 'dead', 'dead after max attempts';
select public.web_outbox_retry((select id from public.web_outbox where dedupe_key = 'test:dedupe:1'));
insert into r select (select status = 'pending' and attempts = 0 from public.web_outbox where dedupe_key = 'test:dedupe:1'), 'admin retry revives dead row';
-- done
insert into r select (select count(*) from public.web_outbox_claim(10, array['email_confirmation']) c where c.dedupe_key = 'test:dedupe:1') = 1, 'revived row claimable';
select public.web_outbox_done((select id from public.web_outbox where dedupe_key = 'test:dedupe:1'));
insert into r select (select status from public.web_outbox where dedupe_key = 'test:dedupe:1') = 'done', 'marked done';

-- limiter
insert into r select public.web_rate_hit('test:ip:1', 60, 2) and public.web_rate_hit('test:ip:1', 60, 2) and not public.web_rate_hit('test:ip:1', 60, 2), 'limiter allows 2 then blocks';

-- funnel strips PII keys
select public.web_funnel_track('gate', 'gate_open', 'anon-12345678', '{"email":"x@y.z","phone":"9","page":"/"}');
insert into r select (select context from public.web_funnel_events where anon_id = 'anon-12345678') = '{"page":"/"}'::jsonb, 'funnel context drops PII keys';

-- health
insert into r select (public.web_health() ->> 'db')::boolean and (public.web_health() ->> 'catalogue_rows')::int >= 0, 'health reports';

do $$ begin
  if exists (select 1 from r where not ok) then
    raise exception 'FAILED (%): %', (select count(*) from r where not ok), (select string_agg(name, ' | ') from r where not ok);
  end if;
  raise notice 'PASS % checks', (select count(*) from r);
end $$;
rollback;
