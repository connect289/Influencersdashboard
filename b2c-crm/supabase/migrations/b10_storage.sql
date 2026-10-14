-- B2C CRM b10: the private bucket for student documents and enrolment proofs. Staging first.
-- Files live under leads/<lead_id>/; the app uploads them on the server after b2c.can_see() and opens them only through
-- signed links valid for 5 minutes. No storage policy for anon or authenticated: the browser never reads the bucket directly.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('b2c-documents', 'b2c-documents', false, 4194304, array['application/pdf', 'image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
