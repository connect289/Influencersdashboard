-- B2C CRM b12: the first version of the three guides (spec B16). The Admin edits them in the app (Guide → Edit);
-- this only adds articles that are missing, so it never overwrites an edit.
insert into b2c.user_guides (role, slug, section, title, body, screens, sort) values
-- ---------- Sales guide ----------
('sales', 'day', 'Getting started', 'A day in the app', $t$Start on **Today**. Work the queue from the top: overdue follow-ups, then new leads, then what is due today.

Every lead you touch ends with a next follow-up. The app will not let you save a call or a stage without one, so nothing is forgotten.

- **Today**: your queue and your numbers for the day.
- **Leads**: every lead you own, with saved views.
- **Follow-ups**: everything due, as a list or a calendar.
- **Inbox**: WhatsApp conversations with your students.
- **Me**: your hours, away status, email templates and this guide.$t$, '{/s}', 10),
('sales', 'sla', 'Getting started', 'New leads and the first-contact timer', $t$A new lead shows a timer: call before it runs out. The Admin sets the limits; by default 15 minutes for a hot lead, 4 hours for warm and a day for cold, counted in your working hours.

When the timer runs out the lead turns red and the Admin is told. Call it first.$t$, '{/s,/s/leads}', 20),
('sales', 'calling', 'Working a lead', 'Calling and logging', $t$On a phone, tap **Call**: your dialler opens. When you come back, the log sheet is waiting: choose the outcome, add a note, pick the next follow-up.

On a laptop, **Call** shows the number, a copy button and a QR code: scan it with your phone to dial. The log sheet opens at the same time.

- A tapped call that is not logged within 10 minutes shows **Call not logged** on the lead and alerts you.
- From New Lead the stage moves by itself: No answer, Busy or Switched off go to Could Not Connect; Connected goes to Contacted.$t$, '{/s/leads/*}', 30),
('sales', 'whatsapp', 'Working a lead', 'WhatsApp and the 24-hour window', $t$You can type freely only within 24 hours of the student's last message. Outside that window, start with an approved sales template.

Messages go from the Eduwit B2C number. In test mode nothing reaches the student; the message shows "test mode, not sent".

If a student writes STOP, every message stops at once and the lead shows **Opted out**.$t$, '{/s/inbox,/s/leads/*}', 40),
('sales', 'email', 'Working a lead', 'Email and your templates', $t$Tap **Email** on a lead. Pick one of your templates (or start blank), check the subject and the text, and send. The email goes from your own @eduwit.in mailbox and appears on the lead's timeline.

Templates fill in **{{first_name}}**, **{{programme}}**, **{{university}}** and **{{counsellor}}** for you. Write and save your own under **Me → Email templates**. Editing a colleague's shared template saves your own copy; theirs stays as it was.$t$, '{/s/leads/*,/s/me}', 50),
('sales', 'programmes', 'Working a lead', 'Programme fit and sharing', $t$**Programme fit** on the lead lists the programmes that match the student's interest: course, specialization, university and mode, with fees and eligibility.

Tick up to three and share them on WhatsApp or by email, or mark them as explained on a call. Each share is kept on the timeline. Stage 6, **Program Details Explained**, needs at least one.

The full catalogue is under **Leads → Programmes**.$t$, '{/s/leads/*,/s/programmes}', 60),
('sales', 'witty', 'Working a lead', 'What Witty already said', $t$Most students spoke to Witty, the WhatsApp assistant, before they reach you. Open **Witty's conversation** on the lead to read it before you call: what they asked, what Witty recommended, what they worried about.

You cannot reply there. Witty has its own number; you speak from the Eduwit B2C number. If a student mentions Witty, say you have the conversation in front of you.$t$, '{/s/leads/*}', 70),
('sales', 'stages', 'Working a lead', 'Stages and sub-stages', $t$Choose a stage and a sub-stage. Some stages need something done first (a call attempt, a programme shared, an application). The app says what is missing.

Lost always needs a comment; some Lost reasons send the lead to nurture, others close it for good. Moving a lead back to an earlier stage needs the Admin.

On **Pipeline** you can drag a card to another stage; the same sheet opens to choose the sub-stage and the next follow-up.$t$, '{/s/leads/*,/s/pipeline}', 80),
('sales', 'crosssell', 'Working a lead', 'Changing interest (cross-sell)', $t$If the student wants a different programme or university, use **Change** on Interest and say why. The change is kept in the history, reaches the master lead table and refreshes Programme fit.$t$, '{/s/leads/*}', 90),
('sales', 'followups', 'Your day', 'Follow-ups: list and calendar', $t$**Follow-ups** shows what is overdue, due today and coming up. Switch to **Day** or **Week** to see them on a calendar.

Each row has Call, WhatsApp and Snooze. Snoozing asks for the new time; completing asks for the next follow-up.

Reminders arrive 10 minutes before a follow-up is due: in the app's bell and, if you allow notifications on this device, as a phone notification.$t$, '{/s/followups,/s/me}', 100),
('sales', 'views', 'Your day', 'Your own lead views', $t$On **Leads**, choose **New view** to save a filter you use often: stage, temperature, source, programme, follow-up date and more, sorted the way you like. Your views are yours; the Admin can publish standard views for everyone.$t$, '{/s/leads}', 110),
('sales', 'applications', 'Closing', 'Applications and enrolment', $t$Add the application with the university's application ID; the lead becomes an Applicant. Tick the documents as they arrive and upload the files (PDF or photo, up to 4 MB).

Record the enrolment with the fee, the date and the proof (receipt or university letter). The Admin verifies it; then it counts.$t$, '{/s/leads/*}', 120),
('sales', 'partners', 'Closing', 'Students already with partners', $t$Some students were already contacted by admission partners. The lead says so. Open as a neutral adviser: "Eduwit can help you compare your options"; do not pitch one university.$t$, '{/s/leads/*}', 130),
('sales', 'privacy', 'Rules', 'Privacy', $t$A counsellor sees only their own leads; the sales head, the Admin and Marketing see all. Every number you reveal or copy is logged. Never copy student data into personal chats or sheets.$t$, '{/s/me}', 140),
-- ---------- Admin guide ----------
('admin', 'setup', 'First-time setup', 'Setting up, in order', $t$Do these once, on staging first.

- **Google Workspace**: the service account with domain-wide delegation (Gmail send for counsellors, directory read for Teams).
- **Teams**: add each person with their role, languages, skills and caps. Mark test users.
- **WhatsApp**: the Eduwit B2C number and its approved templates.
- **B2B CRM**: the webhook endpoint, the signing secret and the API key (README step 6).
- **Working calendars**: everyone's hours, holidays and leave.
- **Lead Allocation**: rules and pools; run a simulation.
- **Stages, templates, settings**: check them under Settings.
- **Go live**: switch live mode on only after the end-to-end test with test leads passes.$t$, '{/w,/w/settings,/w/connectors}', 10),
('admin', 'sources', 'Leads', 'Where leads come from', $t$The B2B CRM decides every lead first. When it hands one to B2C you see it here within seconds: the sales lane goes to a counsellor through Lead Allocation; the nurture lane goes to the pool.

Counsellors and you can add students too (**New lead**). They go in through the master lead table so a student is never created twice, and come straight back.$t$, '{/w,/w/leads}', 20),
('admin', 'allocation', 'Leads', 'Lead Allocation', $t$Rules run top to bottom; the first that matches decides. Each picks from its pool among people working now, not on leave or away, and under their caps. The catch-all is always last.

Every decision is kept with the people it skipped and why (Decisions tab, and on each lead). Run a simulation before changing a rule that matters.

Leads nobody can take wait in **Queues**; the engine retries every minute and alerts you after 5 minutes in working hours.$t$, '{/w/allocation}', 30),
('admin', 'ledger', 'Leads', 'Every hand-off is recorded in the B2B CRM', $t$A lead goes to a partner only through the B2B engine (**Send to partners**). Each counsellor assignment, reassignment and its end is sent to the B2B CRM at once, so the B2B ledger shows who had each student and when, whether a partner or one of our counsellors.$t$, '{/w/leads,/w/leads/*}', 40),
('admin', 'leads', 'Leads', 'Editing, removing and exporting leads', $t$Open a lead to edit a contact, reassign it, add a coaching note or send it to partners. Select several on **Leads** to tag, reassign or remove them; removed leads wait in the Recycle bin and can be restored.

**Export** downloads the current view as a CSV (up to 10,000 rows). Every export is logged with the filter, the columns and the row count.$t$, '{/w/leads,/w/leads/*}', 50),
('admin', 'teams', 'People', 'Teams and Workspace sync', $t$Add people under **Teams** with an @eduwit.in address and a role: Counsellor, Sales head, Marketing or Admin. Deactivating someone signs them out, revokes their trusted devices and reassigns their open leads by the rules.

Every night the app reads Google Workspace: names, photos and job titles stay current, and an account suspended in Workspace is deactivated here the same way.$t$, '{/w/teams}', 60),
('admin', 'enrolments', 'Money', 'Enrolments', $t$A counsellor records the enrolment with the fee, the date and the proof. Check the proof and verify it, or send it back saying what is missing. Only verified enrolments count.$t$, '{/w/enrollments}', 70),
('admin', 'settings', 'Settings', 'Settings and live mode', $t$Every setting change needs a reason and is kept as a new version. **Live mode** decides whether messages reach students; keep it off until the end-to-end test passes. Test leads never get a real message, live or not.$t$, '{/w/settings}', 80),
('admin', 'tests', 'Settings', 'Test leads and test users', $t$Phones starting 910000 or 9190000000 are test leads. They go only to test users or to you, never reach a student, and stay out of reports.$t$, '{/w,/w/leads}', 90),
('admin', 'guides', 'Settings', 'Editing these guides', $t$Under **Guide**, choose **Edit** on any article, or **New article**. Write in plain text: a blank line starts a paragraph, a line starting with "- " is a bullet, **two stars** make bold. Say on which screens the "?" should offer it.

A changed article shows as unread again for everyone. **Who has read** lists each person's progress.$t$, '{/w/guide}', 100),
-- ---------- Marketing guide ----------
('marketing', 'see', 'Getting started', 'What you can see', $t$You see everything the Admin sees: every lead with phone numbers and emails, every WhatsApp conversation and Witty transcript, and the enrolment and money views. Every number you reveal or copy is logged.$t$, '{/w,/w/leads,/w/leads/*}', 10),
('marketing', 'do', 'Getting started', 'What you can change', $t$You act only on marketing. Today that is **tags** on leads (select leads, then Tag). Lead edits, stage changes, reassignment, partner routing and sales templates are for the sales team and the Admin; the app does not offer them to you and the database refuses them.$t$, '{/w/leads}', 20),
('marketing', 'consent', 'Rules', 'Consent and opt-out', $t$A student who writes STOP is opted out of every message at once. Marketing messages need the student's marketing consent; the lead shows whether it was given and when. Quiet hours and frequency caps are set under Settings by the Admin.$t$, '{/w/leads/*}', 30),
('marketing', 'tests', 'Rules', 'Test leads', $t$Phones starting 910000 or 9190000000 are test leads. They never receive a real message and stay out of reports.$t$, '{/w}', 40)
on conflict (role, slug) do nothing;
