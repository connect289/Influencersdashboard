-- D4 (approved 6 Oct 2026): switch off the old auto-assign trigger.
-- It ran crm_allocate_lead() synchronously inside every Witty write (via lead_intake ->
-- is_sales_ready) and, with 0 active sales managers, assigned nothing. Queue-based
-- assignment replaces it in the new CRM. The trigger is disabled, not dropped, so
-- `enable trigger crm_auto_assign` restores it exactly.
alter table public.student_leads disable trigger crm_auto_assign;
