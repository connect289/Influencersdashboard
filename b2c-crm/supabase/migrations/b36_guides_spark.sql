-- Guide articles brought up to date for Eduwit Spark (16 Oct 2026): the first-time setup as it was actually done on
-- staging, search anywhere, the lead screen's sections, alerts. Only articles the Admin has not edited are replaced.

insert into b2c.user_guides as g (role, slug, section, title, body, screens, sort) values
('admin', 'setup', 'First-time setup', 'Setting up, in order', $t$Do these once, on staging first. The developer's deploy script (`web/scripts/deploy-staging.mjs`) creates the Vercel project, sets its variables and points the database timers at the site; the rest is yours.

- **Sign-in**: Google sign-in is on (Supabase → Authentication → Google, with the OAuth client's redirect `…/auth/v1/callback`). Anyone without Google uses **"First time, or forgot your password?"** on the sign-in page: a one-time link by email, then a password of 12+ characters. Every sign-in on a new device needs the 6-digit code emailed to the company inbox.
- **Email**: the sign-in codes, password links, alerts and support tickets go out by SMTP (a Workspace mailbox with an app password, or the relay). Without it nobody can finish signing in.
- **Teams**: add each person with their role, languages, skills and caps; give counsellors their **work mobile** under Phone numbers. Mark test users: they only ever receive test leads.
- **Google Workspace** (later): the service account with domain-wide delegation, for counsellors' Gmail, the Teams sync, Google Calendar and the support mailbox.
- **WhatsApp** (later): the Eduwit B2C number and its approved templates.
- **B2B CRM** (later): the webhook endpoint, the signing secret and the API key, once its Addendum 4 is deployed.
- **Lead Allocation**: working hours and holidays, then the rules; test with test leads.
- **Settings → live mode**: keep it off until the end-to-end test passes. Test leads never get a real message, live or not.$t$, '{/w/settings,/w/teams,/w/connectors}', 10),
('admin', 'search', 'Getting around', 'Search anywhere', $t$Press **⌘K** (Ctrl+K on Windows) or **/** on any screen, or use **Search…** at the top of the sidebar. Type a student's name, phone, email or application ID to open their lead, or the name of a screen (for example "queue", "phone numbers", "ad spend") to go there. Arrow keys move, Enter opens.$t$, '{/w,/s}', 15),
('sales', 'search', 'Getting started', 'Search anywhere', $t$Press **⌘K** (Ctrl+K) or **/** on a laptop, or **Search…** in the sidebar, and type a student's name, phone or email to jump to them. On a phone, use the search box on **Leads**.$t$, '{/s,/s/leads}', 12),
('sales', 'lead_sections', 'Working a lead', 'The lead screen', $t$The top card is who they are and what to do next: name and temperature, the stage (tap it to move the lead), why they are with us, and the four actions: **Call**, **WhatsApp**, **Email**, **Follow-up**. The line under them is the next planned follow-up.

Below it, one section at a time: **Overview** (the brief before you call, contact details, interest, programme fit), **Profile** (what we know about the student, consent and source) and **Applications**. On a laptop the activity rail is always beside them: open follow-ups, the timeline with your notes, nurture, and Witty's conversation. On a phone the rail is the **Activity** tab.

**Next: …** at the top right takes you to the next student in Today's queue, so you can work the queue without going back.$t$, '{/s/leads/*}', 30),
('sales', 'alerts', 'Your day', 'Alerts', $t$Today shows your latest six alerts; **Alerts** in the sidebar (or **All** on the card) shows every one, newest first: new leads, re-engaged leads, SLA warnings, reminders, replies, enrolment checks and number changes. Each one opens the lead or screen it is about. **Mark all read** clears the count on Today.$t$, '{/s/alerts,/s}', 40)
on conflict (role, slug) do update set section = excluded.section, title = excluded.title, body = excluded.body, screens = excluded.screens, sort = excluded.sort, updated_at = now()
 where g.updated_by is null and g.version = 1;
