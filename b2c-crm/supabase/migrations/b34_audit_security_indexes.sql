-- Security and performance findings of the 16 Oct 2026 audit.
--   followup_counts   a counsellor only ever gets their own counts (the Admin and the sales head may ask for anyone's;
--                     internal callers without a sign-in keep the parameter): the parameter used to be trusted as given.
--   internal helpers  no longer executable by signed-in staff over the API: setting, working_now, next_working_at,
--                     window_open, has_marketing_consent, period_conversion, email_allowance_left, call_suggestion,
--                     pending_set. They are only called from other SECURITY DEFINER functions, which need no grant.
--                     (The app calls none of them directly: checked against web/.)
--   indexes           the 40 foreign keys without a covering index (Supabase performance advisor).

create or replace function b2c.followup_counts(p_user uuid) returns jsonb language sql stable security definer set search_path = '' as $f$
  with who as (select case when b2c.uid() is null or p_user = b2c.uid() or b2c.my_role() in ('admin', 'sales_head') then p_user else b2c.uid() end as id),
       d as (select date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata' + interval '1 day' as d1)
  select jsonb_build_object(
    'not_worked', (select count(*) from b2c.leads_state s, who where s.owner_id = who.id and s.status = 'active' and s.contact_attempts = 0 and s.stage_id = 1),
    'overdue', (select count(*) from b2c.tasks t, who where t.owner_id = who.id and t.status = 'open' and t.due_at < now()),
    'today', (select count(*) from b2c.tasks t, who, d where t.owner_id = who.id and t.status = 'open' and t.due_at >= now() and t.due_at < d.d1),
    'upcoming', (select count(*) from b2c.tasks t, who, d where t.owner_id = who.id and t.status = 'open' and t.due_at >= d.d1))
$f$;

revoke execute on function b2c.setting(text), b2c.working_now(uuid, timestamptz), b2c.next_working_at(uuid, timestamptz), b2c.window_open(text),
  b2c.has_marketing_consent(bigint, text), b2c.period_conversion(bigint, date, integer), b2c.email_allowance_left(), b2c.call_suggestion(bigint, text),
  b2c.pending_set(bigint) from public, anon, authenticated;

create index if not exists ix_ad_spend_daily_import_id on b2c.ad_spend_daily (import_id);
create index if not exists ix_alert_events_alert_id on b2c.alert_events (alert_id);
create index if not exists ix_allocation_rules_pool_id on b2c.allocation_rules (pool_id);
create index if not exists ix_assignments_decision_id on b2c.assignments (decision_id);
create index if not exists ix_calendar_events_user_id on b2c.calendar_events (user_id);
create index if not exists ix_calls_user_id on b2c.calls (user_id);
create index if not exists ix_campaigns_segment_id on b2c.campaigns (segment_id);
create index if not exists ix_commission_lines_override_id on b2c.commission_lines (override_id);
create index if not exists ix_commission_lines_reverses_id on b2c.commission_lines (reverses_id);
create index if not exists ix_commission_lines_run_id on b2c.commission_lines (run_id);
create index if not exists ix_commission_overrides_counsellor_id on b2c.commission_overrides (counsellor_id);
create index if not exists ix_created_leads_user_id on b2c.created_leads (user_id);
create index if not exists ix_dashboard_homes_dashboard_id on b2c.dashboard_homes (dashboard_id);
create index if not exists ix_dashboard_schedules_dashboard_id on b2c.dashboard_schedules (dashboard_id);
create index if not exists ix_dashboard_schedules_user_id on b2c.dashboard_schedules (user_id);
create index if not exists ix_dashboards_owner_id on b2c.dashboards (owner_id);
create index if not exists ix_documents_application_id on b2c.documents (application_id);
create index if not exists ix_earnings_reverses_id on b2c.earnings (reverses_id);
create index if not exists ix_email_codes_user_id on b2c.email_codes (user_id);
create index if not exists ix_enrollments_application_id on b2c.enrollments (application_id);
create index if not exists ix_enrollments_counsellor_id on b2c.enrollments (counsellor_id);
create index if not exists ix_guide_progress_guide_id on b2c.guide_progress (guide_id);
create index if not exists ix_invoice_lines_earning_id on b2c.invoice_lines (earning_id);
create index if not exists ix_invoices_credit_of on b2c.invoices (credit_of);
create index if not exists ix_leads_state_previous_owner_id on b2c.leads_state (previous_owner_id);
create index if not exists ix_leads_state_stage_id on b2c.leads_state (stage_id);
create index if not exists ix_leaves_user_id on b2c.leaves (user_id);
create index if not exists ix_metric_alerts_metric on b2c.metric_alerts (metric);
create index if not exists ix_metric_alerts_user_id on b2c.metric_alerts (user_id);
create index if not exists ix_metric_defs_source on b2c.metric_defs (source);
create index if not exists ix_pool_members_user_id on b2c.pool_members (user_id);
create index if not exists ix_receipt_allocations_receipt_id on b2c.receipt_allocations (receipt_id);
create index if not exists ix_sales_email_templates_owner_id on b2c.sales_email_templates (owner_id);
create index if not exists ix_sales_email_templates_parent_id on b2c.sales_email_templates (parent_id);
create index if not exists ix_saved_views_owner_id on b2c.saved_views (owner_id);
create index if not exists ix_send_queue_wa_message_id on b2c.send_queue (wa_message_id);
create index if not exists ix_session_checks_user_id on b2c.session_checks (user_id);
create index if not exists ix_support_messages_author_id on b2c.support_messages (author_id);
create index if not exists ix_trusted_devices_user_id on b2c.trusted_devices (user_id);
create index if not exists ix_wa_messages_template_id on b2c.wa_messages (template_id);
