-- Rollback of the after-Pro file (D-112): each of retention and thresholds goes back to the version before D-112, but only
-- while D-112's seed version is still the latest (a person's later edit stays).
do $$
declare
  v_key text;
  v_row one.settings;
  v_prev one.settings_versions;
begin
  foreach v_key in array array['retention', 'thresholds'] loop
    select * into v_row from one.settings where key = v_key;
    if found and v_row.actor = 'seed'
       and exists (select 1 from one.settings_versions where key = v_key and version = v_row.version and reason like 'D-112 (after Pro)%') then
      select * into v_prev from one.settings_versions where key = v_key and version = v_row.version - 1;
      if found then
        perform one.settings_put(v_key, v_prev.value, 'seed', 'rollback of the after-Pro file: the version before D-112');
      end if;
    end if;
  end loop;
end $$;
