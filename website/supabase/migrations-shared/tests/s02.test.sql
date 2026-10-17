-- Smoke test for s02: existing rows and existing writers default to whatsapp; web rows accepted; anything else refused.
do $$ begin
  if exists (select 1 from public.w2_messages where channel <> 'whatsapp') then raise exception 's02: existing rows are not whatsapp'; end if;
  insert into public.w2_messages (phone, direction, content) values ('919812300003', 'in', 'dry run');
  if (select channel from public.w2_messages where phone = '919812300003') <> 'whatsapp' then raise exception 's02: default is not whatsapp'; end if;
  insert into public.w2_messages (phone, direction, content, channel, session_id) values ('919812300003', 'out', 'dry run', 'web', 'sess');
  begin
    insert into public.w2_messages (phone, direction, content, channel) values ('919812300003', 'out', 'x', 'sms');
    raise exception 's02: unknown channel accepted';
  exception when check_violation then null;
  end;
  raise notice 's02 smoke: PASS';
end $$;
