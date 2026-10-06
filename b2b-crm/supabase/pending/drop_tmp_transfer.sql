-- PENDING (needs a confirmed run): remove the temporary objects used on 6 Oct 2026 to copy the baseline schema
-- from production to staging. EXECUTE was already revoked from every API role, so nothing can call the function;
-- the table holds only schema text (no personal data). The Supabase connector holds DROP statements for manual
-- confirmation, so run this in the Supabase SQL editor (production project xlseqwgyjuqhktrguhyc), or approve it
-- when the connector asks.
drop function if exists public.b2b_tmp_transfer_get(text);
drop table if exists public.b2b_tmp_transfer;
