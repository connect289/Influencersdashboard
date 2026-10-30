-- M33g: the legacy CRM's internal stage writer is not callable by anon or a signed-in stranger; its guarded caller
-- crm_set_stage still is, and still refuses a stranger. Every row must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
grant all on r to authenticated, anon;
insert into r select 'anon cannot execute crm_apply_stage_system',
  not has_function_privilege('anon', 'public.crm_apply_stage_system(bigint,text,text,text,jsonb,text,boolean)', 'EXECUTE'), null;
insert into r select 'authenticated cannot execute crm_apply_stage_system',
  not has_function_privilege('authenticated', 'public.crm_apply_stage_system(bigint,text,text,text,jsonb,text,boolean)', 'EXECUTE'), null;
insert into r select 'service_role still can',
  has_function_privilege('service_role', 'public.crm_apply_stage_system(bigint,text,text,text,jsonb,text,boolean)', 'EXECUTE'), null;
insert into r select 'crm_set_stage is still callable by authenticated (it checks crm_require itself)',
  has_function_privilege('authenticated', 'public.crm_set_stage(bigint,text,text,text,jsonb)', 'EXECUTE'), null;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "aaaaaaaa-0000-0000-0000-0000000033a7", "role": "authenticated"}', true);
do $x$ declare e text; begin
  begin
    perform public.crm_apply_stage_system(1, 'lost', null, 'test', '{}'::jsonb, 'test', true);
    e := 'executed';
  exception when insufficient_privilege then e := '42501'; when others then e := sqlstate;
  end;
  insert into r values ('a stranger calling it directly is refused with 42501', e = '42501', e);
  begin
    perform public.crm_set_stage(1, 'lost', null, 'test', '{}'::jsonb);
    e := 'executed';
  exception when others then e := sqlstate;
  end;
  insert into r values ('a stranger calling crm_set_stage is refused by crm_require (42501)', e = '42501', e);
end $x$;
reset role;
select * from r order by ok, name;
rollback;
