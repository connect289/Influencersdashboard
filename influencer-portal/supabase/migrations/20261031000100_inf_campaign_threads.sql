-- Estate audit, 31 Oct 2026: campaign conversations follow campaign visibility (schema inf only).
-- A creator, and an agency they let negotiate, may read and write a campaign conversation only while the creator
-- takes part in a published campaign: it is open to them in the marketplace (as the creator's campaign page shows it),
-- or they were invited, applied, have a deal in it, or already have a conversation about it. Staff keep their access.
-- An archived campaign's conversations stay readable and take no new messages.
-- Idempotent (create or replace). Inverse statements: see the rollback block at the end.

create or replace function inf.thread_resolve(p_type text, p_entity uuid, p_creator uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_creator uuid;
  v_subject text;
  v_staff_perm text;
  v_agency_grant text;
  v_staff_only boolean := false;
  v_owner uuid;
  v_admin_link text;
  v_creator_link text;
  v_agency_link text;
  v_side text;
  v_read boolean := false;
  v_post boolean := false;
  v_campaign_status text;
  v_takes_part boolean := false;
begin
  case p_type
    when 'application' then
      select a.creator_id, 'Application: ' || c.name, coalesce(c.owner_id, c.created_by), '/admin/applications/' || a.id,
             '/creator/applications/' || a.id
        into v_creator, v_subject, v_owner, v_admin_link, v_creator_link
        from inf.campaign_applications a join inf.campaigns c on c.id = a.campaign_id where a.id = p_entity;
      v_staff_perm := 'campaign.read'; v_agency_grant := 'negotiate'; v_agency_link := '/agency/applications/' || p_entity;
    when 'campaign' then
      select p_creator, 'Campaign: ' || c.name, coalesce(c.owner_id, c.created_by), '/admin/campaigns/' || c.id || '?tab=messages&thread=' || p_creator,
             '/creator/campaigns/' || c.id, c.status,
             (c.visibility in ('open', 'both') and c.status in ('open', 'active'))
               or exists (select 1 from inf.campaign_invites i where i.campaign_id = c.id and i.creator_id = p_creator)
               or exists (select 1 from inf.campaign_applications a where a.campaign_id = c.id and a.creator_id = p_creator)
               or exists (select 1 from inf.deals d where d.campaign_id = c.id and d.creator_id = p_creator)
               or exists (select 1 from inf.threads t where t.entity_type = 'campaign' and t.entity_id = c.id
                            and coalesce(t.creator_id, '00000000-0000-0000-0000-000000000000'::uuid) = p_creator)
        into v_creator, v_subject, v_owner, v_admin_link, v_creator_link, v_campaign_status, v_takes_part
        from inf.campaigns c where c.id = p_entity and p_creator is not null;
      v_staff_perm := 'campaign.read'; v_agency_grant := 'negotiate';
      v_agency_link := '/agency/creators/' || p_creator || '/campaigns/' || p_entity;
    when 'deal' then
      select d.creator_id, 'Deal: ' || d.title, d.owner_id, '/admin/deals/' || d.id, '/creator/deals/' || d.id
        into v_creator, v_subject, v_owner, v_admin_link, v_creator_link from inf.deals d where d.id = p_entity;
      v_staff_perm := 'deal.read'; v_agency_grant := 'negotiate'; v_agency_link := '/agency/deals/' || p_entity;
    when 'contract' then
      select d.creator_id, 'Contract ' || k.number, d.owner_id, '/admin/contracts/' || k.id, '/creator/contracts/' || k.id
        into v_creator, v_subject, v_owner, v_admin_link, v_creator_link
        from inf.contracts k join inf.deals d on d.id = k.deal_id where k.id = p_entity;
      v_staff_perm := 'contract.read'; v_agency_grant := 'negotiate'; v_agency_link := '/agency/contracts/' || p_entity;
    when 'brief' then
      select d.creator_id, 'Brief: ' || d.title, d.owner_id, '/admin/briefs/' || b.id, '/creator/briefs/' || b.id
        into v_creator, v_subject, v_owner, v_admin_link, v_creator_link
        from inf.briefs b join inf.deals d on d.id = b.deal_id where b.id = p_entity;
      v_staff_perm := 'brief.read'; v_agency_grant := 'deliverables'; v_agency_link := '/agency/briefs/' || p_entity;
    when 'deliverable' then
      select d.creator_id, 'Deliverable: ' || x.title, d.owner_id, '/admin/content/' || x.id, '/creator/deliverables/' || x.id
        into v_creator, v_subject, v_owner, v_admin_link, v_creator_link
        from inf.deliverables x join inf.deals d on d.id = x.deal_id where x.id = p_entity;
      v_staff_perm := 'deliverable.read'; v_agency_grant := 'deliverables'; v_agency_link := '/agency/deliverables/' || p_entity;
    when 'payout' then
      select p.creator_id, 'Payout ' || p.ref, null, '/admin/finance/payouts/' || p.batch_id || '?payout=' || p.id, '/creator/earnings?payout=' || p.id
        into v_creator, v_subject, v_owner, v_admin_link, v_creator_link from inf.payouts p where p.id = p_entity;
      v_staff_perm := 'payout.read'; v_agency_grant := 'earnings'; v_agency_link := '/agency/creators/' || v_creator || '/earnings?payout=' || p_entity;
    when 'lead' then
      select a.creator_id, 'Lead note', null, '/admin/leads?lead=' || a.id, null
        into v_creator, v_subject, v_owner, v_admin_link, v_creator_link from inf.lead_attributions a where a.id = p_entity;
      v_staff_perm := 'lead.read'; v_agency_grant := null; v_staff_only := true;
    when 'support' then
      select c.id, 'Support: ' || c.display_name, c.owner_id, '/admin/creators/' || c.id || '?tab=messages', '/creator/messages'
        into v_creator, v_subject, v_owner, v_admin_link, v_creator_link from inf.creators c where c.id = p_entity;
      v_staff_perm := 'creator.read'; v_agency_grant := 'view'; v_agency_link := '/agency/messages?creator=' || p_entity;
    else
      raise exception 'invalid thread type' using errcode = '22023';
  end case;
  if v_creator is null then return null; end if;
  if inf.has_perm('message.read') and inf.has_perm(v_staff_perm) then
    v_side := 'eduwit'; v_read := true; v_post := inf.has_perm('message.write');
  elsif not v_staff_only and coalesce(v_creator = inf.current_creator_id(), false) then
    v_side := 'creator'; v_read := true; v_post := true;
  elsif not v_staff_only and v_agency_grant is not null and inf.agency_can(v_creator, v_agency_grant) then
    v_side := 'agency'; v_read := true; v_post := true;
  end if;
  -- Campaign conversations: the creator's side only while the creator takes part in a published campaign; an archived
  -- campaign's conversations are read-only for everyone.
  if p_type = 'campaign' then
    if v_side in ('creator', 'agency') and (v_campaign_status = 'draft' or not coalesce(v_takes_part, false)) then
      v_side := null; v_read := false; v_post := false;
    end if;
    if v_campaign_status = 'archived' then v_post := false; end if;
  end if;
  return jsonb_build_object('creator_id', v_creator, 'subject', v_subject, 'side', v_side, 'can_read', v_read, 'can_post', v_post,
                            'staff_only', v_staff_only, 'owner_id', v_owner, 'admin_link', v_admin_link, 'creator_link', v_creator_link,
                            'agency_link', v_agency_link, 'agency_grant', v_agency_grant);
end $$;

call inf.apply_client_grants();

-- rollback: (inverse statements; run in one transaction)
-- The previous definition, verbatim:
-- create or replace function inf.thread_resolve(p_type text, p_entity uuid, p_creator uuid default null) returns jsonb
-- language plpgsql stable security definer set search_path = '' as $$
-- declare
--   v_creator uuid;
--   v_subject text;
--   v_staff_perm text;
--   v_agency_grant text;
--   v_staff_only boolean := false;
--   v_owner uuid;
--   v_admin_link text;
--   v_creator_link text;
--   v_agency_link text;
--   v_side text;
--   v_read boolean := false;
--   v_post boolean := false;
-- begin
--   case p_type
--     when 'application' then
--       select a.creator_id, 'Application: ' || c.name, coalesce(c.owner_id, c.created_by), '/admin/applications/' || a.id,
--              '/creator/applications/' || a.id
--         into v_creator, v_subject, v_owner, v_admin_link, v_creator_link
--         from inf.campaign_applications a join inf.campaigns c on c.id = a.campaign_id where a.id = p_entity;
--       v_staff_perm := 'campaign.read'; v_agency_grant := 'negotiate'; v_agency_link := '/agency/applications/' || p_entity;
--     when 'campaign' then
--       select p_creator, 'Campaign: ' || c.name, coalesce(c.owner_id, c.created_by), '/admin/campaigns/' || c.id || '?tab=messages&thread=' || p_creator,
--              '/creator/campaigns/' || c.id
--         into v_creator, v_subject, v_owner, v_admin_link, v_creator_link
--         from inf.campaigns c where c.id = p_entity and p_creator is not null;
--       v_staff_perm := 'campaign.read'; v_agency_grant := 'negotiate';
--       v_agency_link := '/agency/creators/' || p_creator || '/campaigns/' || p_entity;
--     when 'deal' then
--       select d.creator_id, 'Deal: ' || d.title, d.owner_id, '/admin/deals/' || d.id, '/creator/deals/' || d.id
--         into v_creator, v_subject, v_owner, v_admin_link, v_creator_link from inf.deals d where d.id = p_entity;
--       v_staff_perm := 'deal.read'; v_agency_grant := 'negotiate'; v_agency_link := '/agency/deals/' || p_entity;
--     when 'contract' then
--       select d.creator_id, 'Contract ' || k.number, d.owner_id, '/admin/contracts/' || k.id, '/creator/contracts/' || k.id
--         into v_creator, v_subject, v_owner, v_admin_link, v_creator_link
--         from inf.contracts k join inf.deals d on d.id = k.deal_id where k.id = p_entity;
--       v_staff_perm := 'contract.read'; v_agency_grant := 'negotiate'; v_agency_link := '/agency/contracts/' || p_entity;
--     when 'brief' then
--       select d.creator_id, 'Brief: ' || d.title, d.owner_id, '/admin/briefs/' || b.id, '/creator/briefs/' || b.id
--         into v_creator, v_subject, v_owner, v_admin_link, v_creator_link
--         from inf.briefs b join inf.deals d on d.id = b.deal_id where b.id = p_entity;
--       v_staff_perm := 'brief.read'; v_agency_grant := 'deliverables'; v_agency_link := '/agency/briefs/' || p_entity;
--     when 'deliverable' then
--       select d.creator_id, 'Deliverable: ' || x.title, d.owner_id, '/admin/content/' || x.id, '/creator/deliverables/' || x.id
--         into v_creator, v_subject, v_owner, v_admin_link, v_creator_link
--         from inf.deliverables x join inf.deals d on d.id = x.deal_id where x.id = p_entity;
--       v_staff_perm := 'deliverable.read'; v_agency_grant := 'deliverables'; v_agency_link := '/agency/deliverables/' || p_entity;
--     when 'payout' then
--       select p.creator_id, 'Payout ' || p.ref, null, '/admin/finance/payouts/' || p.batch_id || '?payout=' || p.id, '/creator/earnings?payout=' || p.id
--         into v_creator, v_subject, v_owner, v_admin_link, v_creator_link from inf.payouts p where p.id = p_entity;
--       v_staff_perm := 'payout.read'; v_agency_grant := 'earnings'; v_agency_link := '/agency/creators/' || v_creator || '/earnings?payout=' || p_entity;
--     when 'lead' then
--       select a.creator_id, 'Lead note', null, '/admin/leads?lead=' || a.id, null
--         into v_creator, v_subject, v_owner, v_admin_link, v_creator_link from inf.lead_attributions a where a.id = p_entity;
--       v_staff_perm := 'lead.read'; v_agency_grant := null; v_staff_only := true;
--     when 'support' then
--       select c.id, 'Support: ' || c.display_name, c.owner_id, '/admin/creators/' || c.id || '?tab=messages', '/creator/messages'
--         into v_creator, v_subject, v_owner, v_admin_link, v_creator_link from inf.creators c where c.id = p_entity;
--       v_staff_perm := 'creator.read'; v_agency_grant := 'view'; v_agency_link := '/agency/messages?creator=' || p_entity;
--     else
--       raise exception 'invalid thread type' using errcode = '22023';
--   end case;
--   if v_creator is null then return null; end if;
--   if inf.has_perm('message.read') and inf.has_perm(v_staff_perm) then
--     v_side := 'eduwit'; v_read := true; v_post := inf.has_perm('message.write');
--   elsif not v_staff_only and coalesce(v_creator = inf.current_creator_id(), false) then
--     v_side := 'creator'; v_read := true; v_post := true;
--   elsif not v_staff_only and v_agency_grant is not null and inf.agency_can(v_creator, v_agency_grant) then
--     v_side := 'agency'; v_read := true; v_post := true;
--   end if;
--   return jsonb_build_object('creator_id', v_creator, 'subject', v_subject, 'side', v_side, 'can_read', v_read, 'can_post', v_post,
--                             'staff_only', v_staff_only, 'owner_id', v_owner, 'admin_link', v_admin_link, 'creator_link', v_creator_link,
--                             'agency_link', v_agency_link, 'agency_grant', v_agency_grant);
-- end $$;
-- call inf.apply_client_grants();
