-- Smoke test for s03: the website still reads the taxonomy through the old names, and search still works.
do $$ begin
  if (select count(*) from public.web_tax_programmes) <> (select count(*) from public.catalog_tax_programmes) then raise exception 's03: compatibility view differs'; end if;
  if public.web_search('{"q":"mba"}') is null then raise exception 's03: search broke'; end if;
  perform public.web_refresh_read_model();
  raise notice 's03 smoke: PASS';
end $$;
