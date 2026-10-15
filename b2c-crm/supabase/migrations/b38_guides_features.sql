-- Guide articles for the b37 features (17 Oct 2026). New slugs are inserted; an article the Admin has edited is left alone.

insert into b2c.user_guides as g (role, slug, section, title, body, screens, sort) values
('sales', 'snippets', 'Working a lead', 'Snippets: the lines you type again and again', $t$Inside the 24-hour window you type freely. Save the lines you send often under **Me → Snippets**: a greeting, the fee and EMI line, the document list. In the composer, tap a snippet to drop it into the message; {{first_name}}, {{programme}} and {{counsellor_first_name}} are filled in from the lead.

Tick **Share with every counsellor** and your colleagues can use it too. Only you can change or remove your snippet; a colleague who wants a different wording saves their own. The most-used snippets come first.$t$, '{/s/me?tab=snippets,/s/inbox}', 34),
('sales', 'bulk', 'Your day', 'Several leads at once', $t$On **Leads**, tick the rows and the bar at the bottom offers three things:

- **Add a follow-up**: the same task, kind and time on every ticked lead (for example "Webinar reminder" on Friday at 11:00).
- **Send a WhatsApp template**: one approved sales template to up to 50 leads. Each lead is checked as if you had sent it alone: your own leads only, nobody who opted out, nobody in the middle of a Witty chat. Refusals are named.
- **Add or remove a tag**.

Leads that are not yours are skipped and listed back to you.$t$, '{/s/leads}', 36),
('sales', 'shortcuts', 'Getting started', 'Keyboard shortcuts and swipes', $t$**On a laptop**, press **?** on any screen to see its shortcuts. On a lead: **c** Call, **w** WhatsApp, **e** Email, **f** add a follow-up, **n** write a note, **s** change the stage, **]** the next lead in your queue. On lists, **j** and **k** move down and up, **Enter** opens. **⌘K** (Ctrl+K) or **/** searches anywhere. Shortcuts never fire while you are typing in a field.

**On a phone**, swipe a card on Today or a row on Follow-ups: **right** to call, **left** to open the lead (Today) or snooze (Follow-ups). The buttons are still there if you prefer to tap.$t$, '{/s,/s/followups,/s/leads/*}', 14),
('sales', 'catalogue_fix', 'Working a lead', 'A programme is wrong on the Programme page', $t$The Programme page is read-only: the catalogue is loaded in the B2B CRM from each partner's file. If a fee, an eligibility line or a brochure link is wrong, use the flag on the row (**Suggest a correction**) and say what it should be. The Admin gets it as a support ticket with the programme named, and the catalogue is corrected at its source.$t$, '{/s/programmes}', 38),
('admin', 'health', 'Running the CRM', 'System health', $t$**Settings → System health** answers "is everything running?" in seven lines, each green, amber or red:

- **Database timers**: the b2c-* cron jobs and their last run. Red if one failed or none is scheduled; amber if the minute tick is late.
- **The app answering the timers**: the sync, reconcile and directory jobs are HTTP calls from the database to the site. Red if any failed in the last hour.
- **Changes to the master lead table** (the outbox) and **events from it** (the inbox): what waits, what failed, when the last batch and the last event were.
- **WhatsApp and email sending**: queued, held (consent or window), failed in 24 hours, and whether live mode is on.
- **Claude**: today's spend against the cap, failed calls.
- **Waiting for a person**: unassigned sales leads, replies to answer, calls not logged.

Each red or amber line says where to go. Home shows a red banner whenever something is red.$t$, '{/w/settings?tab=health,/w}', 95),
('admin', 'audit', 'Running the CRM', 'The audit log and sign-ins', $t$**Settings → Audit log** lists every phone reveal, Call tap, number copy, export, "view as Sales", contact edit, delete and template-to-many, with who, when and the lead. Filter by action, person, lead or dates. It is append-only: nothing can be changed or removed.

**Settings → Sign-ins** lists every sign-in attempt: the method (Google, password, code, trusted device), the outcome, the address and the browser. Failed attempts in the last 24 hours are counted at the top; five failed passwords lock an account for 15 minutes.$t$, '{/w/settings?tab=audit,/w/settings?tab=signins}', 96),
('admin', 'duplicates', 'Leads', 'Duplicate suspects', $t$**Leads → Duplicate suspects** groups open leads that share a phone number or an email, counting every number and address on a lead (a parent's number a counsellor added, an alternate email). Open each group and decide: keep the one being worked, close the other as **Lost · Junk or test** or **Enrolled elsewhere**, or delete it to the Recycle bin. Merging records themselves is done in the B2B CRM, which owns the master lead table. Marketing sees the list too, read-only.$t$, '{/w/leads/duplicates}', 44),
('marketing', 'campaign_calendar', 'Campaigns', 'The campaign calendar', $t$**Nurture → Campaigns** opens with a month view: each campaign on its scheduled day (or the day it started), and under each day how many automated WhatsApp and email messages the journeys and campaigns sent. Use it before scheduling a broadcast, so two campaigns do not land on the same students on the same day; the guardrails would hold the second one back anyway (one marketing WhatsApp per lead per day, six per 30 days). Recurring campaigns show once, on their next run; the arrows move a month.$t$, '{/w/nurture?tab=campaigns}', 33)
on conflict (role, slug) do update set section = excluded.section, title = excluded.title, body = excluded.body, screens = excluded.screens, sort = excluded.sort, updated_at = now()
 where g.updated_by is null and g.version = 1;
