-- M25c: the model registry for the Admin (spec B7.8.1 promotion path, B14.3 AI Optimiser screen: "model registry
-- (shadow, challenger, champion) with calibration plots").
--   ml_overview()                       models, the gate, metrics, the challenger check, settings, data available
--   ml_train_request(reason)            queues a training run (ml_tick trains it within 10 minutes)
--   ml_set_status(id, status, reason)   shadow -> challenger (only when the gate passed); challenger -> champion (only
--                                       when ml_champion_check is ready); any -> retired; a challenger back to shadow
--   ml_rollback(reason)                 one click: retire the champion and bring back the previous champion, if any
--   ml_settings_save(p, reason)         thresholds and the nightly switch (versioned)

create or replace function b2b.ml_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  prm jsonb := b2b.engine_params(true);
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'settings', b2b.ml_cfg(),
    'settings_version', (select version from b2b.settings where key = 'ml'),
    'data', (select jsonb_build_object('matured', count(*) filter (where o.age_days >= (prm ->> 'maturity_days')::numeric),
                                       'matured_enrolled', count(*) filter (where o.age_days >= (prm ->> 'maturity_days')::numeric and o.enrolled),
                                       'partners', count(distinct o.partner_id) filter (where o.age_days >= (prm ->> 'maturity_days')::numeric),
                                       'young', count(*) filter (where o.age_days < (prm ->> 'maturity_days')::numeric))
               from b2b.allocation_outcomes() o),
    'maturity_days', (prm ->> 'maturity_days')::int,
    'decided_30d', coalesce((select jsonb_object_agg(coalesce(model_version, 'segment P̂'), n) from (
                               select d.model_version, count(*) n from b2b.engine_decisions d
                                where d.scoring_mode = 'performance' and d.mode = 'performance' and not d.is_test and d.created_at > now() - interval '30 days'
                                group by 1) x), '{}'),
    'models', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', m.id, 'version', m.version, 'kind', m.kind, 'status', m.status, 'created_at', m.created_at, 'trained_at', m.trained_at,
                 'status_at', m.status_at, 'status_reason', m.status_reason, 'requested_by', m.requested_by, 'error', m.error,
                 'trained_on', m.trained_on, 'gate', m.gate, 'metrics', m.metrics, 'features', jsonb_array_length(m.features), 'was_champion', m.was_champion,
                 'champion_check', case when m.status = 'challenger' then b2b.ml_champion_check(m.id) end)
               order by m.id desc) from (select * from b2b.ml_models order by id desc limit 20) m), '[]'));
end $fn$;

create or replace function b2b.ml_train_request(p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_id bigint; v_version text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  if exists (select 1 from b2b.ml_models where status = 'training') then raise exception 'a model is already waiting for training' using errcode = '22023'; end if;
  v_version := 'v' || to_char(now() at time zone 'Asia/Kolkata', 'YYYYMMDD-HH24MISS');
  insert into b2b.ml_models (version, requested_by, status_reason) values (v_version, coalesce(auth.uid()::text, 'admin'), left(trim(p_reason), 300))
  returning id into v_id;
  perform b2b.log_event('ml.train_requested', null, null, null, jsonb_build_object('version', v_version, 'reason', trim(p_reason)));
  return jsonb_build_object('id', v_id, 'version', v_version);
end $fn$;

create or replace function b2b.ml_set_status(p_id bigint, p_status text, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare m b2b.ml_models; v_check jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into m from b2b.ml_models where id = p_id for update;
  if m.id is null then raise exception 'model not found' using errcode = 'P0002'; end if;
  if p_status = 'challenger' then
    if m.status <> 'shadow' then raise exception 'only a shadow model can become the challenger' using errcode = '22023'; end if;
    if not coalesce((m.gate ->> 'passed')::boolean, false) then
      raise exception 'the model has not passed the activation gate (matured outcomes, beating segment P̂, offline policy value)' using errcode = '22023';
    end if;
    update b2b.ml_models set status = 'retired', status_at = now(), status_by = coalesce(auth.uid()::text, 'admin'), status_reason = 'replaced by ' || m.version
     where status = 'challenger';
  elsif p_status = 'champion' then
    if m.status <> 'challenger' then raise exception 'only the challenger can become the champion' using errcode = '22023'; end if;
    v_check := b2b.ml_champion_check(m.id);
    if not (v_check ->> 'ready')::boolean then
      raise exception 'the challenger is not yet better with confidence (% and % matured leads, z = %; needs 100 each and z of 1.645)',
        v_check ->> 'model_leads', v_check ->> 'other_leads', v_check ->> 'z' using errcode = '22023';
    end if;
    update b2b.ml_models set status = 'retired', was_champion = true, status_at = now(), status_by = coalesce(auth.uid()::text, 'admin'),
           status_reason = 'replaced by ' || m.version where status = 'champion';
  elsif p_status = 'shadow' then
    if m.status <> 'challenger' then raise exception 'only the challenger can go back to shadow' using errcode = '22023'; end if;
    update b2b.ml_models set status = 'retired', status_at = now(), status_by = coalesce(auth.uid()::text, 'admin'), status_reason = 'replaced by ' || m.version
     where status = 'shadow';
  elsif p_status = 'retired' then
    if m.status in ('retired', 'failed', 'training') then raise exception 'this model is not in use' using errcode = '22023'; end if;
  else
    raise exception 'unknown status' using errcode = '22023';
  end if;
  update b2b.ml_models set status = p_status, status_at = now(), status_by = coalesce(auth.uid()::text, 'admin'), status_reason = left(trim(p_reason), 300),
         was_champion = was_champion or m.status = 'champion'
   where id = m.id;
  perform b2b.log_event('ml.model_status', null, null, null, jsonb_build_object('version', m.version, 'from', m.status, 'to', p_status, 'reason', trim(p_reason)));
  return jsonb_build_object('version', m.version, 'status', p_status);
end $fn$;

create or replace function b2b.ml_rollback(p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare cur b2b.ml_models; prev b2b.ml_models;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into cur from b2b.ml_models where status = 'champion' for update;
  if cur.id is null then raise exception 'there is no champion to roll back' using errcode = '22023'; end if;
  select * into prev from b2b.ml_models where was_champion and status = 'retired' and id <> cur.id order by status_at desc, id desc limit 1;
  update b2b.ml_models set status = 'retired', was_champion = true, status_at = now(), status_by = coalesce(auth.uid()::text, 'admin'),
         status_reason = 'rolled back: ' || left(trim(p_reason), 280) where id = cur.id;
  if prev.id is not null then
    update b2b.ml_models set status = 'champion', status_at = now(), status_by = coalesce(auth.uid()::text, 'admin'),
           status_reason = 'restored by rollback of ' || cur.version where id = prev.id;
  end if;
  perform b2b.log_event('ml.rollback', null, null, null, jsonb_build_object('from', cur.version, 'to', prev.version, 'reason', trim(p_reason)));
  return jsonb_build_object('retired', cur.version, 'champion', prev.version);
end $fn$;

create or replace function b2b.ml_settings_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v jsonb := b2b.ml_cfg();
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p ? 'min_outcomes' and not ((p ->> 'min_outcomes')::int between 100 and 100000) then raise exception 'matured outcomes are 100 to 100000' using errcode = '22023'; end if;
  if p ? 'challenger_share' and not ((p ->> 'challenger_share')::numeric between 0.01 and 0.5) then raise exception 'the challenger decides 1 to 50%% of leads' using errcode = '22023'; end if;
  if p ? 'ece_fallback' and not ((p ->> 'ece_fallback')::numeric between 0.01 and 0.3) then raise exception 'the calibration limit is 0.01 to 0.30' using errcode = '22023'; end if;
  if p ? 'train_hour_ist' and not ((p ->> 'train_hour_ist')::int between 0 and 23) then raise exception 'the training hour is 0 to 23' using errcode = '22023'; end if;
  if p ? 'auto_train' and jsonb_typeof(p -> 'auto_train') <> 'boolean' then raise exception 'nightly training is on or off' using errcode = '22023'; end if;
  v := v || jsonb_strip_nulls(jsonb_build_object('min_outcomes', (p ->> 'min_outcomes')::int, 'challenger_share', round((p ->> 'challenger_share')::numeric, 3),
                                                 'ece_fallback', round((p ->> 'ece_fallback')::numeric, 3), 'train_hour_ist', (p ->> 'train_hour_ist')::int,
                                                 'auto_train', (p ->> 'auto_train')::boolean));
  return b2b.set_setting('ml', v, p_reason);
end $fn$;

revoke execute on function b2b.ml_overview(), b2b.ml_train_request(text), b2b.ml_set_status(bigint, text, text), b2b.ml_rollback(text),
                           b2b.ml_settings_save(jsonb, text) from public, anon;
grant execute on function b2b.ml_overview(), b2b.ml_train_request(text), b2b.ml_set_status(bigint, text, text), b2b.ml_rollback(text),
                          b2b.ml_settings_save(jsonb, text) to authenticated, service_role;
