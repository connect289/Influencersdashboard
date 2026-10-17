-- Rollback for s05. Refuses if any lead already records one of these consent versions (consent records are kept).
do $$ begin
  if exists (select 1 from public.student_leads where consent_text_version in ('web-gate-2026-10-v1', 'web-form-2026-10-v1')) then
    raise exception 's05 rollback: leads reference these consent versions; deactivate instead (update b2b.consent_texts set active = false ...)';
  end if;
end $$;
delete from b2b.consent_texts where version in ('web-gate-2026-10-v1', 'web-form-2026-10-v1');
