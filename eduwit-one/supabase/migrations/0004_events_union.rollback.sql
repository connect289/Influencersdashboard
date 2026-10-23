-- Rollback of 0004. one.events and one.event_watermarks belong to 0002 and stay; only the copy functions go.

drop function if exists one.events_refresh();
drop function if exists one.events_sources();
drop function if exists one.events_copy(text, text, text);
