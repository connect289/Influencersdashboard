-- M4a: partner adapter types (spec B5.1). public.partners is empty; 'portal' goes (partners never log in).
alter table public.partners drop constraint if exists partners_adapter_type_check;
alter table public.partners add constraint partners_adapter_type_check
  check (adapter_type in ('leadsquared', 'salesforce', 'zoho', 'meritto', 'hubspot', 'generic_rest', 'webhook'));
