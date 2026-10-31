-- 0031 the independent audit's second round (owner's go of 31 Oct: everything that needs no business decision).
--   one.mask_text                 the app's contact shapes in the database too (D-119)
--   one.ui_chat_action_propose    an action's arguments are stored as proposed, never masked into something else, so
--                                 the card shows what runs (D-115)
--   one.ui_chat_action_decide     a confirmation carries the arguments its card showed, and they must be the stored ones
--                                 (D-115); the 3-argument form is replaced by one with p_shown
--   one.ui_user_put               an address maps only to a Supabase user who has confirmed it (D-117)
--   one.ai_reserve, ai_reservations, ai_calls_add   a model call reserves its worst case before it runs and settles at
--                                 its real cost, one reservation at a time, so calls in parallel cannot pass the day's cap
--                                 together (D-118)
-- Numbered 0031: 0029 and 0030 precede it.

-- The app's contact shapes in the database (D-119). one.mask_text masked fewer phone shapes than web/lib/ai/pii.ts's
-- maskText; it now follows the same steps: other scripts' characters normalised (NFKC, unusual spaces and dashes, every
-- Unicode decimal digit as its ASCII digit), emails, then the app's three phone shapes outside the spans the app leaves
-- alone (UUIDs, long hex ids, ISO dates and times, d/m/y dates). The earlier Indian-mobile shape stays as a fourth pass,
-- so nothing it masked before is left. Emails become [email] and phones [phone], as before. Both maskers are tested
-- against one corpus (supabase/tests/mask-corpus.json).
create or replace function one.mask_normalise(p text) returns text
language sql immutable parallel safe set search_path = '' as $$
  select pg_catalog.translate(
           pg_catalog.translate(case when pg_catalog.getdatabaseencoding() = 'UTF8' then pg_catalog.normalize(p, 'NFKC') else p end,
                                '             ​  　﻿‐‑‒–—―−', '                  -------'),
           '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹߀߁߂߃߄߅߆߇߈߉०१२३४५६७८९০১২৩৪৫৬৭৮৯੦੧੨੩੪੫੬੭੮੯૦૧૨૩૪૫૬૭૮૯୦୧୨୩୪୫୬୭୮୯௦௧௨௩௪௫௬௭௮௯౦౧౨౩౪౫౬౭౮౯೦೧೨೩೪೫೬೭೮೯൦൧൨൩൪൫൬൭൮൯෦෧෨෩෪෫෬෭෮෯๐๑๒๓๔๕๖๗๘๙໐໑໒໓໔໕໖໗໘໙༠༡༢༣༤༥༦༧༨༩၀၁၂၃၄၅၆၇၈၉႐႑႒႓႔႕႖႗႘႙០១២៣៤៥៦៧៨៩᠐᠑᠒᠓᠔᠕᠖᠗᠘᠙᥆᥇᥈᥉᥊᥋᥌᥍᥎᥏᧐᧑᧒᧓᧔᧕᧖᧗᧘᧙᪀᪁᪂᪃᪄᪅᪆᪇᪈᪉᪐᪑᪒᪓᪔᪕᪖᪗᪘᪙᭐᭑᭒᭓᭔᭕᭖᭗᭘᭙᮰᮱᮲᮳᮴᮵᮶᮷᮸᮹᱀᱁᱂᱃᱄᱅᱆᱇᱈᱉᱐᱑᱒᱓᱔᱕᱖᱗᱘᱙꘠꘡꘢꘣꘤꘥꘦꘧꘨꘩꣐꣑꣒꣓꣔꣕꣖꣗꣘꣙꤀꤁꤂꤃꤄꤅꤆꤇꤈꤉꧐꧑꧒꧓꧔꧕꧖꧗꧘꧙꧰꧱꧲꧳꧴꧵꧶꧷꧸꧹꩐꩑꩒꩓꩔꩕꩖꩗꩘꩙꯰꯱꯲꯳꯴꯵꯶꯷꯸꯹０１２３４５６７８９𐒠𐒡𐒢𐒣𐒤𐒥𐒦𐒧𐒨𐒩𐴰𐴱𐴲𐴳𐴴𐴵𐴶𐴷𐴸𐴹𐵀𐵁𐵂𐵃𐵄𐵅𐵆𐵇𐵈𐵉𑁦𑁧𑁨𑁩𑁪𑁫𑁬𑁭𑁮𑁯𑃰𑃱𑃲𑃳𑃴𑃵𑃶𑃷𑃸𑃹𑄶𑄷𑄸𑄹𑄺𑄻𑄼𑄽𑄾𑄿𑇐𑇑𑇒𑇓𑇔𑇕𑇖𑇗𑇘𑇙𑋰𑋱𑋲𑋳𑋴𑋵𑋶𑋷𑋸𑋹𑑐𑑑𑑒𑑓𑑔𑑕𑑖𑑗𑑘𑑙𑓐𑓑𑓒𑓓𑓔𑓕𑓖𑓗𑓘𑓙𑙐𑙑𑙒𑙓𑙔𑙕𑙖𑙗𑙘𑙙𑛀𑛁𑛂𑛃𑛄𑛅𑛆𑛇𑛈𑛉𑛐𑛑𑛒𑛓𑛔𑛕𑛖𑛗𑛘𑛙𑛚𑛛𑛜𑛝𑛞𑛟𑛠𑛡𑛢𑛣𑜰𑜱𑜲𑜳𑜴𑜵𑜶𑜷𑜸𑜹𑣠𑣡𑣢𑣣𑣤𑣥𑣦𑣧𑣨𑣩𑥐𑥑𑥒𑥓𑥔𑥕𑥖𑥗𑥘𑥙𑯰𑯱𑯲𑯳𑯴𑯵𑯶𑯷𑯸𑯹𑱐𑱑𑱒𑱓𑱔𑱕𑱖𑱗𑱘𑱙𑵐𑵑𑵒𑵓𑵔𑵕𑵖𑵗𑵘𑵙𑶠𑶡𑶢𑶣𑶤𑶥𑶦𑶧𑶨𑶩𑽐𑽑𑽒𑽓𑽔𑽕𑽖𑽗𑽘𑽙𖄰𖄱𖄲𖄳𖄴𖄵𖄶𖄷𖄸𖄹𖩠𖩡𖩢𖩣𖩤𖩥𖩦𖩧𖩨𖩩𖫀𖫁𖫂𖫃𖫄𖫅𖫆𖫇𖫈𖫉𖭐𖭑𖭒𖭓𖭔𖭕𖭖𖭗𖭘𖭙𖵰𖵱𖵲𖵳𖵴𖵵𖵶𖵷𖵸𖵹𜳰𜳱𜳲𜳳𜳴𜳵𜳶𜳷𜳸𜳹𝟎𝟏𝟐𝟑𝟒𝟓𝟔𝟕𝟖𝟗𝟘𝟙𝟚𝟛𝟜𝟝𝟞𝟟𝟠𝟡𝟢𝟣𝟤𝟥𝟦𝟧𝟨𝟩𝟪𝟫𝟬𝟭𝟮𝟯𝟰𝟱𝟲𝟳𝟴𝟵𝟶𝟷𝟸𝟹𝟺𝟻𝟼𝟽𝟾𝟿𞅀𞅁𞅂𞅃𞅄𞅅𞅆𞅇𞅈𞅉𞋰𞋱𞋲𞋳𞋴𞋵𞋶𞋷𞋸𞋹𞓰𞓱𞓲𞓳𞓴𞓵𞓶𞓷𞓸𞓹𞗱𞗲𞗳𞗴𞗵𞗶𞗷𞗸𞗹𞗺𞥐𞥑𞥒𞥓𞥔𞥕𞥖𞥗𞥘𞥙🯰🯱🯲🯳🯴🯵🯶🯷🯸🯹',
           '012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678999999999990123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567899999999999999999999999999999999999999999012345678901234567890123456789012345678901234567890123456789')
$$;

create or replace function one.mask_phones(p text) returns text
language sql immutable parallel safe set search_path = '' as $$
  select pg_catalog.regexp_replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(pg_catalog.regexp_replace(p,
           '(?<![0-9])(?:(?:\+|00)?91[ .()/_-]{0,2}|0)?[6-9](?:[ .()/_-]?[0-9]){9}(?![0-9])', '[phone]', 'g'),
           '\+[ (]?[0-9](?:[ .()/_-]{0,2}[0-9]){7,14}(?![0-9])', '[phone]', 'g'),
           '(?<![0-9])[0-9](?:[ .()/_-]?[0-9]){9,14}(?![0-9])', '[phone]', 'g'),
           '(\+?91[\s-]?)?[6-9][0-9]{4}[\s-]?[0-9]{5}(?![0-9])', '[phone]', 'g')
$$;

create or replace function one.mask_text(p text) returns text
language plpgsql immutable parallel safe set search_path = '' as $$
declare
  c_keep constant text := '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9a-f]{20,}|[0-9]{4}-[0-9]{2}-[0-9]{2}(?:[t ][0-9]{2}:[0-9]{2}(?::[0-9]{2}(?:\.[0-9]+)?)?(?:[+-][0-9]{2}(?::?[0-9]{2})?|z)?)?|\y[0-9]{1,2}[/.-][0-9]{1,2}[/.-][0-9]{2,4}\y';
  v text := p;
  v_gaps text[];
  v_keep text[];
  v_out text := '';
begin
  -- The short path, as before: text with no digit, no @ and nothing outside ASCII holds no contact.
  if v is null or (v !~ '[0-9@]' and pg_catalog.octet_length(v) = pg_catalog.char_length(v)) then
    return v;
  end if;
  if pg_catalog.octet_length(v) <> pg_catalog.char_length(v) then
    v := one.mask_normalise(v);
  end if;
  if pg_catalog.strpos(v, '@') > 0 then
    v := pg_catalog.regexp_replace(v, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[email]', 'g');
  end if;
  if v !~ '[0-9]' then
    return v;
  end if;
  if v !~* c_keep then
    return one.mask_phones(v);
  end if;
  -- Phones are masked between the kept spans, which go back in their places.
  v_gaps := pg_catalog.regexp_split_to_array(v, c_keep, 'i');
  select coalesce(array_agg(m[1] order by n), '{}') into v_keep from pg_catalog.regexp_matches(v, c_keep, 'gi') with ordinality as x(m, n);
  if cardinality(v_gaps) <> cardinality(v_keep) + 1 then
    return one.mask_phones(v);
  end if;
  for i in 1 .. cardinality(v_keep) loop
    v_out := v_out || one.mask_phones(v_gaps[i]) || v_keep[i];
  end loop;
  return v_out || one.mask_phones(v_gaps[cardinality(v_gaps)]);
end $$;

-- The assistant proposes an action. What the card shows is what runs (D-115): arguments the masker would change (an
-- email, a phone-shaped number) are refused instead of being stored masked. At most five wait in one conversation.
create or replace function one.ui_chat_action_propose(p_task bigint, p_holder text, p_tool text, p_args jsonb, p_summary text, p_risk text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_task one.ai_tasks;
  v_t one.chat_threads;
  v_id bigint;
  v_args jsonb := coalesce(p_args, '{}'::jsonb);
begin
  select * into v_task from one.ai_tasks where id = p_task and kind = 'chat' and status = 'claimed' and claimed_by = p_holder;
  if not found then
    raise exception 'turn % is not open for this holder', p_task using errcode = '55000';
  end if;
  v_t := one.chat_own_thread((v_task.input ->> 'thread_id')::bigint);
  if coalesce(p_tool, '') !~ '^[a-z_]{3,40}$' or coalesce(p_risk, '') not in ('low', 'medium', 'high')
     or length(trim(coalesce(p_summary, ''))) not between 3 and 500
     or jsonb_typeof(v_args) <> 'object' or pg_column_size(v_args) > 20000 then
    raise exception 'an action names a tool, a risk (low, medium, high), a summary of 3 to 500 characters and an object of arguments' using errcode = '22023';
  end if;
  if one.mask_json(v_args) is distinct from v_args then
    raise exception 'an action''s arguments cannot hold an email address or a phone-shaped number: refer to the person or the row another way, or use its page' using errcode = '22023';
  end if;
  if (select count(*) from one.chat_actions where thread_id = v_t.id and status = 'proposed') >= 5 then
    raise exception 'five actions already wait for a decision in this conversation' using errcode = '22023';
  end if;
  insert into one.chat_actions (thread_id, task_id, tool, args, summary, risk, proposed_by)
  values (v_t.id, p_task, p_tool, v_args, trim(p_summary), p_risk, v_actor) returning id into v_id;
  return jsonb_build_object('id', v_id);
end $$;

-- The person decides in the chat (0021), now bound to the card (D-115): a confirmation sends back the arguments the card
-- showed. The 3-argument form is dropped so that no call can confirm without them.
drop function if exists one.ui_chat_action_decide(bigint, text, text);
create or replace function one.ui_chat_action_decide(p_id bigint, p_decision text, p_request_id text default null, p_shown jsonb default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_a one.chat_actions;
  v_t one.chat_threads;
begin
  select * into v_a from one.chat_actions where id = p_id for update;
  if not found then
    raise exception 'no action %', p_id using errcode = 'P0002';
  end if;
  v_t := one.chat_own_thread(v_a.thread_id);
  if p_decision not in ('confirm', 'decline') then
    raise exception 'the decision is confirm or decline' using errcode = '22023';
  end if;
  if v_a.status <> 'proposed' then
    raise exception 'action % is not waiting for a decision (%)', p_id, v_a.status using errcode = 'P0002';
  end if;
  if v_a.proposed_at < now() - interval '2 hours' then
    update one.chat_actions set status = 'expired' where id = p_id;
    perform one.chat_append(v_t.id, 'action', jsonb_build_object('action_id', p_id, 'tool', v_a.tool, 'status', 'expired', 'summary', v_a.summary));
    return jsonb_build_object('ok', false, 'status', 'expired', 'error', 'this action expired two hours after it was proposed; ask for it again');
  end if;
  if p_decision = 'decline' then
    update one.chat_actions set status = 'declined', decided_by = v_actor, decided_at = now(), request_id = p_request_id where id = p_id;
    perform one.chat_append(v_t.id, 'action', jsonb_build_object('action_id', p_id, 'tool', v_a.tool, 'status', 'declined', 'summary', v_a.summary));
    perform one.ui_audit_write(v_actor, 'chat.action.decline', 'chat_action:' || p_id, null, jsonb_build_object('tool', v_a.tool), p_request_id);
    return jsonb_build_object('ok', true, 'status', 'declined');
  end if;
  -- A confirmation binds what its card showed (D-115): the arguments come back with it and must be the stored ones.
  if p_shown is null or p_shown is distinct from v_a.args then
    raise exception 'this card does not show the action''s arguments: nothing ran. Reload the conversation and decide again' using errcode = '22023';
  end if;
  update one.chat_actions set status = 'confirmed', decided_by = v_actor, decided_at = now(), request_id = p_request_id where id = p_id;
  perform one.ui_audit_write(v_actor, 'chat.action.confirm', 'chat_action:' || p_id, null, jsonb_build_object('tool', v_a.tool, 'args', v_a.args), p_request_id);
  return jsonb_build_object('ok', true, 'status', 'confirmed', 'id', p_id, 'tool', v_a.tool, 'args', v_a.args, 'summary', v_a.summary, 'risk', v_a.risk);
end $$;

update one.api_grants set fn = 'one.ui_chat_action_decide(bigint,text,text,jsonb)'
 where fn = 'one.ui_chat_action_decide(bigint,text,text)' and role = 'authenticated';

-- People (0011), mapped only to a Supabase user who has confirmed the address (D-117): with open sign-ups an
-- unconfirmed user of the same address may be someone else's.
create or replace function one.ui_user_put(p_email text, p_role text, p_active boolean, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('owner');
  v_email text := lower(trim(p_email));
  v_uid uuid;
  v_before jsonb;
begin
  if v_email !~ '^[^@\s]+@eduwit\.in$' then
    raise exception 'only @eduwit.in addresses' using errcode = '22023';
  end if;
  if p_role not in ('owner', 'engineer') then
    raise exception 'role must be owner or engineer' using errcode = '22023';
  end if;
  select id into v_uid from auth.users where lower(email) = v_email and email_confirmed_at is not null;
  if v_uid is null then
    if exists (select 1 from auth.users where lower(email) = v_email) then
      raise exception 'the Supabase user with this address has not confirmed it yet: they sign in once (Google), then add them' using errcode = '22023';
    end if;
    raise exception 'no Supabase user has this address yet: ask the CRM owner to create it first (S-21)' using errcode = 'P0002';
  end if;
  if v_uid = one.uid() and (p_role <> 'owner' or not p_active) then
    raise exception 'you cannot remove your own owner access' using errcode = '22023';
  end if;
  select to_jsonb(o) into v_before from one.users o where o.user_id = v_uid;
  insert into one.users (user_id, email, role, is_active) values (v_uid, v_email, p_role, p_active)
  on conflict (user_id) do update set email = excluded.email, role = excluded.role, is_active = excluded.is_active;
  if not exists (select 1 from one.users where role = 'owner' and is_active) then
    raise exception 'at least one active owner must remain' using errcode = '22023';
  end if;
  if not p_active then
    update one.trusted_devices set revoked_at = now() where user_id = v_uid and revoked_at is null;
    delete from one.session_checks where user_id = v_uid;
  end if;
  perform one.ui_audit_write(v_actor, 'user.put', 'user:' || v_email, v_before,
                             jsonb_build_object('role', p_role, 'is_active', p_active), p_request_id);
  return jsonb_build_object('ok', true);
end $$;

-- Budget reservations (D-118). Before a model call the app reserves the call's worst case for its task; the reservation
-- holds only while today's spend, every other call in flight and this one fit under ai.daily_cap_inr, and reservations
-- are taken one at a time, so chat turns and worker tasks running in parallel cannot each spend the same room. The
-- call's record settles it (one.ai_calls_add). A task that is no longer claimed holds nothing.
create table one.ai_reservations (
  task_id bigint primary key references one.ai_tasks (id) on delete cascade,
  amount_inr numeric not null check (amount_inr >= 0),
  reserved_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- What the calls in flight may still cost, other than p_except's.
create or replace function one.ai_reserved(p_except bigint default null) returns numeric
language sql stable set search_path = '' as $$
  select coalesce(sum(r.amount_inr), 0) from one.ai_reservations r join one.ai_tasks t on t.id = r.task_id
   where t.status = 'claimed' and r.task_id is distinct from p_except
$$;

create or replace function one.ai_reserve(p_task bigint, p_holder text, p_amount numeric) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_t one.ai_tasks := one.ai_held(p_task, p_holder);
  v_cap numeric := coalesce((one.setting('ai') ->> 'daily_cap_inr')::numeric, 0);
  v_spent numeric;
  v_other numeric;
begin
  if p_amount is null or p_amount < 0 or p_amount > 1000000 then
    raise exception 'a reservation is an amount in INR, 0 or more' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('one.ai_budget'));
  delete from one.ai_reservations r using one.ai_tasks t where t.id = r.task_id and t.status <> 'claimed';
  -- One statement, one snapshot: a call recorded meanwhile counts once, as its cost or as its reservation.
  select one.ai_spent_today(), one.ai_reserved(v_t.id) into v_spent, v_other;
  if v_spent + v_other + p_amount > v_cap then
    delete from one.ai_reservations where task_id = v_t.id;
    return jsonb_build_object('ok', false, 'spent_inr', v_spent, 'in_flight_inr', v_other,
                              'remaining_inr', greatest(v_cap - v_spent - v_other, 0));
  end if;
  insert into one.ai_reservations (task_id, amount_inr) values (v_t.id, p_amount)
  on conflict (task_id) do update set amount_inr = excluded.amount_inr, reserved_at = now();
  return jsonb_build_object('ok', true, 'spent_inr', v_spent, 'in_flight_inr', v_other + p_amount,
                            'remaining_inr', greatest(v_cap - v_spent - v_other - p_amount, 0));
end $$;

-- The calls a task made (0018), each settling the task's reservation; what is left counts the calls still in flight.
create or replace function one.ai_calls_add(p_task bigint, p_holder text, p_calls jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_t one.ai_tasks := one.ai_held(p_task, p_holder);
  v_cap numeric := coalesce((one.setting('ai') ->> 'daily_cap_inr')::numeric, 0);
  v_spent numeric;
  v_other numeric;
begin
  perform one.ai_record_calls(v_t.id, p_calls);
  delete from one.ai_reservations where task_id = v_t.id;
  select one.ai_spent_today(), one.ai_reserved(v_t.id) into v_spent, v_other;
  return jsonb_build_object('spent_inr', v_spent, 'remaining_inr', greatest(v_cap - v_spent - v_other, 0));
end $$;

insert into one.api_grants (fn, role, why) values
  ('one.ai_reserve(bigint,text,numeric)', 'service_role', 'the app reserves a model call''s worst case before it runs (0031, D-118)')
on conflict do nothing;

call one.apply_grants();
