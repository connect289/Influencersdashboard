-- w5_cache_plan_skip_unchanged (proposed 30 Oct 2026, Witty audit; not applied)
--
-- What: w2_cache_plan writes prompt_text (and updated_at) only when the rebuilt prompt differs from the stored one.
-- Why: it rewrote both prompt texts (about 41 KB) every 15 minutes even when they were unchanged: WAL, dead row
-- versions, new TOAST chunks and a row lock for nothing. The jobs it plans are unchanged; nothing reads updated_at
-- (Eduwit One reads expire_at). Everything else is the live definition of 30 Oct 2026. Idempotent.

create or replace function public.w2_cache_plan(p_model text, p_refresh_minutes integer default 40)
 returns jsonb
 language plpgsql
as $function$
declare
v_out jsonb := '[]'::jsonb;
v_name text;
v_text text;
v_hash text;
c w2_gemini_caches;
begin
foreach v_name in array array['extractor', 'counselor'] loop
v_text := w2_build_prompt(v_name);
continue when v_text is null;
v_hash := md5(v_text);
insert into w2_gemini_caches (name) values (v_name) on conflict (name) do nothing;
select * into c from w2_gemini_caches where name = v_name;
update w2_gemini_caches set prompt_text = v_text, updated_at = now()
 where name = v_name and prompt_text is distinct from v_text;
if c.cache_name is null or c.prompt_hash is distinct from v_hash or c.model is distinct from p_model
or c.expire_at is null or c.expire_at < now() + make_interval(mins => p_refresh_minutes) then
v_out := v_out || jsonb_build_object('name', v_name, 'hash', v_hash, 'text', v_text, 'old_cache', c.cache_name, 'model', p_model);
end if;
end loop;
return v_out;
end $function$;

-- rollback (the definition live on production on 30 Oct 2026):
-- create or replace function public.w2_cache_plan(p_model text, p_refresh_minutes integer default 40)
--  returns jsonb
--  language plpgsql
-- as $function$
-- declare
-- v_out jsonb := '[]'::jsonb;
-- v_name text;
-- v_text text;
-- v_hash text;
-- c w2_gemini_caches;
-- begin
-- foreach v_name in array array['extractor', 'counselor'] loop
-- v_text := w2_build_prompt(v_name);
-- continue when v_text is null;
-- v_hash := md5(v_text);
-- insert into w2_gemini_caches (name) values (v_name) on conflict (name) do nothing;
-- select * into c from w2_gemini_caches where name = v_name;
-- update w2_gemini_caches set prompt_text = v_text, updated_at = now() where name = v_name;
-- if c.cache_name is null or c.prompt_hash is distinct from v_hash or c.model is distinct from p_model
-- or c.expire_at is null or c.expire_at < now() + make_interval(mins => p_refresh_minutes) then
-- v_out := v_out || jsonb_build_object('name', v_name, 'hash', v_hash, 'text', v_text, 'old_cache', c.cache_name, 'model', p_model);
-- end if;
-- end loop;
-- return v_out;
-- end $function$;
