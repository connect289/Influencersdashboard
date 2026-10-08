-- M31p: the partner go-live checklist's 'agreement' item. Until now every version of b2b.partner_checklist hard-coded it
-- as done:false / available:false, and partner_set_live refuses while any item is not done, so no partner could ever be
-- switched live. The Admin now confirms the signed agreement and data-processing terms (a reference such as the
-- document name or folder link, kept as a note); the item is done once confirmed. Clearing it takes the partner's
-- live switch off again. Document upload stays outside the CRM.

alter table b2b.partners add column if not exists agreement_confirmed_at timestamptz;
alter table b2b.partners add column if not exists agreement_confirmed_by text;
alter table b2b.partners add column if not exists agreement_note text;

create or replace function b2b.partner_agreement_confirm(p_id bigint, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  p b2b.partners;
  v_by text := coalesce(auth.jwt() ->> 'email', auth.uid()::text, 'admin');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_note, ''))) < 3 then
    raise exception 'say where the signed agreement is (document name or link, at least 3 characters)' using errcode = '22023';
  end if;
  select * into p from b2b.partners where id = p_id for update;
  if p.id is null then raise exception 'partner not found' using errcode = 'P0002'; end if;
  update b2b.partners
     set agreement_confirmed_at = now(), agreement_confirmed_by = v_by, agreement_note = left(trim(p_note), 500), updated_at = now()
   where id = p_id;
  perform b2b.log_event('partner.agreement_confirmed', null, null, p_id,
                        jsonb_build_object('note', left(trim(p_note), 500), 'by', v_by));
  return jsonb_build_object('confirmed_at', now(), 'by', v_by);
end $fn$;

create or replace function b2b.partner_agreement_clear(p_id bigint, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  p b2b.partners;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into p from b2b.partners where id = p_id for update;
  if p.id is null then raise exception 'partner not found' using errcode = 'P0002'; end if;
  update b2b.partners set agreement_confirmed_at = null, agreement_confirmed_by = null, agreement_note = null, updated_at = now() where id = p_id;
  -- a partner without a confirmed agreement must not receive leads
  if b2b.is_live('partner:' || p_id) then
    perform b2b.set_live_switch('partner:' || p_id, false, 'agreement cleared: ' || left(trim(p_reason), 200));
  end if;
  perform b2b.log_event('partner.agreement_cleared', null, null, p_id, jsonb_build_object('reason', left(trim(p_reason), 300)));
  return jsonb_build_object('cleared', true, 'live', false);
end $fn$;

-- the checklist as in M31i, with the agreement item now real
create or replace function b2b.partner_checklist(p b2b.partners)
returns jsonb language sql stable set search_path = '' as $fn$
  select jsonb_build_array(
    jsonb_build_object('key', 'agreement',   'done', p.agreement_confirmed_at is not null, 'available', true),
    jsonb_build_object('key', 'programmes',  'done', exists (select 1 from b2b.partner_programmes o where o.partner_id = p.id and o.valid_to is null and o.active), 'available', true),
    jsonb_build_object('key', 'credentials', 'done', p.api_base_url is not null and (p.outbound_secret_id is not null or p.outbound_auth ->> 'type' = 'none')
                                                     and p.inbound_secret_id is not null, 'available', true),
    jsonb_build_object('key', 'dedupe',      'done', p.dedupe_mode <> 'sync' or p.dedupe_confirmed_at is not null, 'available', true),
    jsonb_build_object('key', 'mapping',     'done', b2b.mapping_ready(p.id), 'available', true),
    jsonb_build_object('key', 'sla_hours',   'done', exists (select 1 from jsonb_each(p.working_hours) d where jsonb_typeof(d.value) = 'object'), 'available', true),
    jsonb_build_object('key', 'branding',    'done', p.display_name is not null and p.brand_color is not null and p.logo_url is not null, 'available', true),
    jsonb_build_object('key', 'test_leads',  'done', exists (select 1 from b2b.allocations a where a.partner_id = p.id and a.is_test and a.status in ('accepted', 'closed')), 'available', true)
  );
$fn$;

revoke execute on function b2b.partner_agreement_confirm(bigint, text), b2b.partner_agreement_clear(bigint, text) from public, anon;
grant execute on function b2b.partner_agreement_confirm(bigint, text), b2b.partner_agreement_clear(bigint, text) to authenticated, service_role;
