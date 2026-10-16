-- B2C CRM b29 (Phase 4): guide articles for telephony, ad spend, performance allocation and Google Calendar.
insert into b2c.user_guides as g (role, slug, section, title, body, screens, sort) values
('admin', 'telephony', 'Calls', 'Calls through Exotel', $t$Today counsellors dial from their own phones and log every call. That stays so until you switch **Settings → telephony → provider** to `exotel`.

Then the Call button rings the counsellor's mobile first and the student next. When the call ends it is logged by itself: outcome, real talk time, the automatic stage move and a suggested follow-up. **Every call is recorded** and kept for `retention_days` (180 by default); a recording opens only for someone who may see the lead, and each play is logged.

- A missed call from a student becomes a call-back task for their counsellor; an unknown number is listed under **Connectors** for you.
- Test leads always use the mock: nobody is dialled.
- Needs: the Exotel keys on the server (EXOTEL_SID, EXOTEL_API_KEY, EXOTEL_API_TOKEN, EXOTEL_WEBHOOK_KEY), LIVE_MODE on, the virtual number as `caller_id`, and every counsellor's mobile number in Teams.$t$, '{/w/connectors,/w/settings}', 130),
('admin', 'ad_spend', 'Analytics', 'Ad spend and return on ad spend', $t$**Money → Ad spend** imports the day-by-day campaign reports of Meta Ads Manager and Google Ads (CSV, in rupees). Importing the same days again replaces them.

A lead counts for a campaign when its campaign value equals the platform campaign's id or name, or when you **match** the campaign to a campaign value or a source. Cost per lead, cost per enrolment and **ROAS** (net university commission of the period's leads for each rupee spent) are on the **Ad spend** dashboard, and every number opens its leads.$t$, '{/w/money}', 135),
('admin', 'performance_allocation', 'Leads', 'Performance-weighted allocation', $t$A rule with the **Performance-weighted** logic gives more turns to counsellors who convert better over the last 30 or 90 days. Shares stay between a floor and a cap (by default half and twice an equal share), new counsellors count at the team's rate until they have 20 leads, and small samples lean towards the team's rate.

Open the rule and press **Show current shares** to see each counsellor's conversion and share before you switch it on. Every decision records the shares it used.$t$, '{/w/allocation}', 85),
('marketing', 'ad_spend', 'Analytics', 'Ad spend and return on ad spend', $t$Import the day-by-day campaign reports from Meta Ads Manager and Google Ads under **Money → Ad spend** (CSV, in rupees; a second import of the same days replaces the first). Match each campaign to the campaign value or the source its leads carry if they do not match by themselves.

The **Ad spend** dashboard shows spend, cost per lead, cost per qualified lead, cost per enrolment and return on ad spend, by campaign and platform.$t$, '{/w/money,/w/analytics}', 120),
('sales', 'calendar', 'Follow-ups', 'Follow-ups in Google Calendar', $t$Under **Me → Availability and alerts** turn on **Show my follow-ups in my Google Calendar**. Each follow-up becomes an event in your calendar with a 10-minute reminder and the lead's link; moving, finishing or handing over a follow-up updates it.

Changes made in Calendar are not copied back: move follow-ups in the CRM.$t$, '{/s/me,/s/followups}', 45),
('sales', 'bridged_calls', 'Calling', 'Calls through the CRM (when switched on)', $t$When the Admin switches on calling through Exotel, **Call** rings your own mobile first; answer it and the student is called. When the call ends it is logged by itself with the real talk time and a suggested follow-up; add a note if you like. All such calls are recorded.

Until then nothing changes: dial from your phone and log each call.$t$, '{/s/leads/*}', 28)
on conflict (role, slug) do update set title = excluded.title, body = excluded.body, screens = excluded.screens, updated_at = now()
 where g.updated_by is null and g.version = 1;
