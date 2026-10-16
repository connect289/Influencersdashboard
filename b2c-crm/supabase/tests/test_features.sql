-- b37 checks (snippets, bulk actions for counsellors, catalogue suggestions, the campaign calendar, system health, the audit
-- and sign-in viewers, duplicate suspects), rolled back. Every row of the final select must say ok = true.
-- Writes only test users and test leads (phones 9100009997xx); safe on staging (SQL editor) and on a local copy.
begin;
create temp table r (n serial, name text, ok boolean, detail text);
grant all on r to authenticated, service_role;
grant usage, select on sequence r_n_seq to authenticated, service_role;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-0000-0000-00000000f301', 'tina.ft@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000f302', 'raj.ft@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000f303', 'mona.ft@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000f304', 'adi.ft@eduwit.in', 'authenticated', 'authenticated');
insert into b2c.users (user_id, email, full_name, role, is_active, is_test_user, takes_leads) values
  ('aaaaaaaa-0000-0000-0000-00000000f301', 'tina.ft@eduwit.in', 'Tina FT', 'counsellor', true, true, false),
  ('aaaaaaaa-0000-0000-0000-00000000f302', 'raj.ft@eduwit.in', 'Raj FT', 'counsellor', true, true, false),
  ('aaaaaaaa-0000-0000-0000-00000000f303', 'mona.ft@eduwit.in', 'Mona FT', 'marketing', true, true, false),
  ('aaaaaaaa-0000-0000-0000-00000000f304', 'adi.ft@eduwit.in', 'Adi FT', 'admin', true, true, false);
create function pg_temp.as_user(p uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated', 'session_id', ('bbbbbbbb-0000-0000-0000-' || right(p::text, 12))::uuid)::text, true);
end $f$;
create function pg_temp.as_system() returns void language plpgsql as $f$ begin perform set_config('request.jwt.claims', '', true); end $f$;
insert into b2c.session_checks (session_id, user_id, method)
select ('bbbbbbbb-0000-0000-0000-' || right(user_id::text, 12))::uuid, user_id, 'email_code' from b2c.users where email like '%.ft@eduwit.in' on conflict do nothing;

create function pg_temp.lead(p_id bigint, p_phone text, p_email text) returns void language plpgsql as $f$
begin
  perform b2c.handoff_receive(jsonb_build_object('id', 'ft-' || p_id || '-u', 'type', 'b2c.lead_upserted', 'lead_id', p_id, 'occurred_at', now(), 'test', true, 'contract_version', 3,
    'data', jsonb_build_object('version', 1, 'seq', 1, 'record', jsonb_build_object('id', p_id, 'is_test', true, 'held_by_b2c', true, 'contract_version', 3,
      'student', jsonb_build_object('name', 'FT Student ' || p_id, 'phone', p_phone, 'email', p_email), 'interest', jsonb_build_object('course', 'MBA'),
      'consent', jsonb_build_object('state', 'given', 'opted_out', false), 'source', jsonb_build_object('lead_source', 'website')))), 'test');
  perform b2c.handoff_receive(jsonb_build_object('id', 'ft-' || p_id || '-h', 'type', 'b2c.lead_handed_off', 'lead_id', p_id, 'occurred_at', now(), 'test', true,
    'contract_version', 3, 'data', '{"b2c_lane": "sales", "reason": "no_partner_offers_programme"}'::jsonb), 'test');
end $f$;

do $x$
declare j jsonb; v bigint; v2 bigint; t bigint; n int;
begin
  perform pg_temp.as_system();
  perform pg_temp.lead(997701, '9100009997' || '01', 'ft1@example.com');
  perform pg_temp.lead(997702, '9100009997' || '02', 'ft2@example.com');
  perform pg_temp.lead(997703, '9100009997' || '03', 'ft3@example.com');
  update b2c.leads_state set owner_id = 'aaaaaaaa-0000-0000-0000-00000000f301', status = 'active' where lead_id in (997701, 997702);
  update b2c.leads_state set owner_id = 'aaaaaaaa-0000-0000-0000-00000000f302', status = 'active' where lead_id = 997703;

  -- ---------- snippets ----------
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000f301');
  v := b2c.snippet_save('{"title": "Fee options", "body": "Hi {{first_name}}, here are the EMI options.", "shared": true}');
  v2 := b2c.snippet_save('{"title": "Private note", "body": "Only mine"}');
  j := b2c.snippets_mine();
  insert into r (name, ok, detail) values ('snippets_own_listed', jsonb_array_length(j) = 2 and (j -> 0 ->> 'mine')::boolean, left(j::text, 300));
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000f302');
  j := b2c.snippets_mine();
  insert into r (name, ok, detail) values ('shared_snippet_seen_by_colleague', jsonb_array_length(j) = 1 and j -> 0 ->> 'title' = 'Fee options' and not (j -> 0 ->> 'mine')::boolean and j -> 0 ->> 'author' = 'Tina FT', left(j::text, 300));
  begin
    perform b2c.snippet_save(jsonb_build_object('id', v, 'title', 'Hijacked', 'body', 'x'));
    insert into r (name, ok, detail) values ('colleague_cannot_edit_shared_snippet', false, 'edit allowed');
  exception when others then
    insert into r (name, ok, detail) values ('colleague_cannot_edit_shared_snippet', sqlerrm like '%not your snippet%', sqlerrm);
  end;
  perform b2c.snippet_used(v);
  insert into r (name, ok, detail) values ('snippet_use_counted', (select uses from b2c.snippets where id = v) = 1, null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000f301');
  perform b2c.snippet_delete(v2);
  insert into r (name, ok, detail) values ('snippet_deleted_by_owner', jsonb_array_length(b2c.snippets_mine()) = 1, null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000f303');
  insert into r (name, ok, detail) values ('marketing_sees_shared_snippets_only', jsonb_array_length(b2c.snippets_mine()) = 1, null);

  -- ---------- bulk actions for a counsellor ----------
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000f301');
  n := b2c.tag_own(array[997701, 997702, 997703], 'Webinar', true);
  insert into r (name, ok, detail) values ('tag_own_only_own_leads', n = 2 and (select tags from b2c.leads_state where lead_id = 997701) @> array['webinar'] and not ((select tags from b2c.leads_state where lead_id = 997703) @> array['webinar']), n::text);
  j := b2c.tasks_bulk(array[997701, 997702, 997703], 'call', 'Webinar follow-up', now() + interval '1 day', 'after the webinar');
  insert into r (name, ok, detail) values ('tasks_bulk_creates_own_skips_others', (j ->> 'created')::int = 2 and jsonb_array_length(j -> 'skipped') = 1 and j -> 'skipped' -> 0 ->> 'lead_id' = '997703', left(j::text, 300));
  insert into r (name, ok, detail) values ('tasks_bulk_tasks_exist', (select count(*) from b2c.tasks where lead_id in (997701, 997702) and title = 'Webinar follow-up' and status = 'open') = 2, null);
  begin
    perform b2c.tasks_bulk(array[997701], 'call', 'Past', now() - interval '1 day', null);
    insert into r (name, ok, detail) values ('tasks_bulk_refuses_past_time', false, 'allowed');
  exception when others then
    insert into r (name, ok, detail) values ('tasks_bulk_refuses_past_time', sqlerrm like '%future%', sqlerrm);
  end;
  -- a template to several leads: own leads go, the colleague's lead is refused by name
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000f304');
  t := b2c.wa_template_save('{"name": "ft_opener", "language": "en", "category": "utility", "audience": "sales", "usable_by_sales": true, "purpose": "opener", "body": "Hi {{1}}, this is {{2}} from Eduwit.", "variables": ["first_name", "counsellor_first_name"]}');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000f301');
  j := b2c.wa_bulk_template(array[997701, 997702, 997703], t);
  insert into r (name, ok, detail) values ('wa_bulk_sends_own_refuses_others', (j ->> 'sent')::int = 2 and jsonb_array_length(j -> 'refused') = 1 and j -> 'refused' -> 0 ->> 'lead_id' = '997703', left(j::text, 300));
  insert into r (name, ok, detail) values ('wa_bulk_queued_messages', (select count(*) from b2c.wa_messages where lead_id in (997701, 997702) and template_id = t and direction = 'out') = 2, null);
  insert into r (name, ok, detail) values ('wa_bulk_audited', exists (select 1 from b2c.audit_log where action = 'wa_bulk' and actor_id = 'aaaaaaaa-0000-0000-0000-00000000f301'), null);

  -- ---------- suggest a catalogue correction ----------
  j := b2c.catalogue_suggest(11, 'The fee shown is last year''s; it is now 1,89,000.');
  insert into r (name, ok, detail) values ('catalogue_suggest_makes_ticket', (j ->> 'ticket_id') is not null and exists (select 1 from b2c.support_tickets where id = (j ->> 'ticket_id')::bigint and kind = 'data' and subject like 'Catalogue: %'), left(j::text, 300));
  insert into r (name, ok, detail) values ('catalogue_suggest_tells_admin', exists (select 1 from b2c.notifications where user_id = 'aaaaaaaa-0000-0000-0000-00000000f304' and title like 'Catalogue correction suggested%'), null);
  begin
    perform b2c.catalogue_suggest(11, 'bad');
    insert into r (name, ok, detail) values ('catalogue_suggest_needs_a_note', false, 'allowed');
  exception when others then
    insert into r (name, ok, detail) values ('catalogue_suggest_needs_a_note', sqlerrm like '%say what is wrong%', sqlerrm);
  end;

  -- ---------- the campaign calendar (Marketing) ----------
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000f303');
  j := b2c.campaign_calendar(null);
  insert into r (name, ok, detail) values ('campaign_calendar_shape', j ? 'month' and jsonb_typeof(j -> 'campaigns') = 'array' and jsonb_typeof(j -> 'sent') = 'object', left(j::text, 300));
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000f301');
  begin
    perform b2c.campaign_calendar(null);
    insert into r (name, ok, detail) values ('campaign_calendar_not_for_sales', false, 'allowed');
  exception when others then
    insert into r (name, ok, detail) values ('campaign_calendar_not_for_sales', sqlstate = '42501', sqlerrm);
  end;

  -- ---------- system health, audit and sign-ins (Admin only) ----------
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000f304');
  j := b2c.system_health();
  insert into r (name, ok, detail) values ('system_health_checks', jsonb_array_length(j -> 'checks') = 7 and j ->> 'overall' in ('ok', 'warn', 'bad')
    and (select bool_and(c ->> 'level' in ('ok', 'warn', 'bad')) from jsonb_array_elements(j -> 'checks') c), left(j::text, 400));
  j := b2c.audit_list('{"action": "wa_bulk"}');
  insert into r (name, ok, detail) values ('audit_list_filters_by_action', (j ->> 'total')::int >= 1 and jsonb_array_length(j -> 'rows') >= 1 and j -> 'rows' -> 0 ->> 'actor' = 'Tina FT' and j -> 'actions' ? 'wa_bulk', left(j::text, 300));
  j := b2c.sign_in_list('{}');
  insert into r (name, ok, detail) values ('sign_in_list_shape', jsonb_typeof(j -> 'rows') = 'array' and j ? 'failed_24h', left(j::text, 300));
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000f303');
  begin
    perform b2c.system_health();
    insert into r (name, ok, detail) values ('system_health_admin_only', false, 'allowed');
  exception when others then
    insert into r (name, ok, detail) values ('system_health_admin_only', sqlstate = '42501', sqlerrm);
  end;
  begin
    perform b2c.audit_list('{}');
    insert into r (name, ok, detail) values ('audit_list_admin_only', false, 'allowed');
  exception when others then
    insert into r (name, ok, detail) values ('audit_list_admin_only', sqlstate = '42501', sqlerrm);
  end;

  -- ---------- duplicate suspects ----------
  perform pg_temp.as_system();
  -- the third lead gets the first lead's email as an extra address (through the contact table, as a counsellor would add it)
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000f302');
  perform b2c.add_contact(997703, 'email', 'ft1@example.com', 'parent', '{}');
  perform pg_temp.as_system();
  update b2c.leads_state set is_test = false where lead_id in (997701, 997703);
  update b2c.lead_records set is_test = false where lead_id in (997701, 997703);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000f303');
  j := b2c.duplicate_suspects(50);
  insert into r (name, ok, detail) values ('duplicate_suspects_finds_shared_email', exists (select 1 from jsonb_array_elements(j) g where g ->> 'kind' = 'email' and g -> 'leads' @> '[{"lead_id": 997701}]' and g -> 'leads' @> '[{"lead_id": 997703}]'), left(j::text, 400));
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000f301');
  begin
    perform b2c.duplicate_suspects(50);
    insert into r (name, ok, detail) values ('duplicate_suspects_not_for_sales', false, 'allowed');
  exception when others then
    insert into r (name, ok, detail) values ('duplicate_suspects_not_for_sales', sqlstate = '42501', sqlerrm);
  end;

  -- nothing new for anon
  insert into r (name, ok, detail) values ('b37_nothing_for_anon', not has_function_privilege('anon', 'b2c.system_health()', 'execute') and not has_function_privilege('anon', 'b2c.snippets_mine()', 'execute')
    and not has_table_privilege('anon', 'b2c.snippets', 'select'), null);
end $x$;

select n, name, ok, case when ok then null else detail end as detail from r order by n;
rollback;
