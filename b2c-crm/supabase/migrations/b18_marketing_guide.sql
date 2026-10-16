-- B2C CRM b18 (Phase 2): the Marketing guide for the nurture screens, and one grant the jobs need.
grant execute on function b2c.notify_admins(text, text, text, text, bigint, text, boolean) to service_role;

-- the Phase 1 article on what Marketing can change is out of date; replaced only if nobody has edited it
insert into b2c.user_guides as g (role, slug, section, title, body, screens, sort)
select role, slug, section, title, $t$You act only on marketing: the Nurture page (journeys, campaigns, segments, replies, scoring), marketing templates, tags, marketing consent and opt-outs. Lead edits, stage changes, reassignment, partner routing and sales templates are for the sales team and the Admin; the app does not offer them to you and the database refuses them.$t$, screens, sort
  from b2c.user_guides where role = 'marketing' and slug = 'do'
on conflict (role, slug) do update set body = excluded.body, version = g.version + 1, updated_at = now()
 where g.updated_by is null and g.version = 1;

insert into b2c.user_guides (role, slug, section, title, body, screens, sort) values
('marketing', 'nurture', 'Nurture', 'The Nurture page', $t$**Overview** shows the pool by reason and age, what came in and what re-engaged each day, messages sent today, the email allowance, WhatsApp spend and what the guardrails held back.

**Pool** lists every pooled lead: why it is there, what is missing, its score, consent, journey step, last message and last reply. Open a lead to start or stop a journey, send one message, record consent or hand it to a counsellor.$t$, '{/w/nurture}', 50),
('marketing', 'journeys', 'Nurture', 'Journeys', $t$A pooled lead enters the journey its lost reason names, after that reason's delay (for example 7 days for a fee concern). Partner-lost leads are matched by the partner's reason.

- Edit the **draft**, then **Publish**: running leads stay on their version unless you move them.
- Steps: send, wait, branch (on a reply, a condition or an A/B split), score, tag, Admin task, hand to a counsellor, move to another journey, exit.
- **Test mode** lets only test leads in; **Test on a test lead** runs it at once. Test leads never get real messages.

The starter journeys begin **paused**: read each one, check its templates are approved, then **Run** it.$t$, '{/w/nurture,/w/nurture/journeys/*}', 60),
('marketing', 'campaigns', 'Nurture', 'Segments and campaigns', $t$A **segment** is a saved set of conditions (dynamic, always current) or a fixed list (a snapshot or pasted phone numbers). **Count now** shows how many leads it has and how many each channel may reach.

A **campaign** sends one template to a segment, now or at a time, once or repeating, within a send window and a per-minute limit. An **A/B test** sends two templates to a sample and the better one to everyone else after 4 hours. Start in **test mode** (test leads only), then copy it for real.$t$, '{/w/nurture}', 70),
('marketing', 'replies', 'Nurture', 'Replies', $t$Every reply to a nurture message is classified: positive, question, negative, opt-out or other. Buttons and keyword rules decide first; Claude decides the rest from the reply text and the course alone.

- **Positive** hands the lead to a counsellor at once, as hot.
- **Negative** moves it to a long-gap journey (or closes it if they enrolled elsewhere).
- **Opt-out** stops everything.
- **Questions** and anything below 80% confidence wait in **Replies**: answer on WhatsApp within the 24-hour window, hand the lead over, or correct the class. Corrections are kept to measure accuracy.$t$, '{/w/nurture}', 80),
('marketing', 'scoring', 'Nurture', 'Lead scoring', $t$Score = **fit** (timeline, budget, qualification, experience, verified phone) + **engagement** (reads, replies, opens, clicks, talking to Witty again, a new form). Engagement halves after 14 days without activity.

A lead that **rises** to 60 or more after entering the pool, with engagement since, goes to a counsellor. A lead that arrives already at 60 from fit alone does not. Change the points under **Scoring and rules**.$t$, '{/w/nurture}', 90),
('marketing', 'templates', 'Templates', 'Templates and Meta approval', $t$**WhatsApp marketing templates** are yours to write: choose the category, map each {{1}} to a field, add up to three buttons ("Yes, call me", "I'm interested", "Share details" re-engage the lead), then **Submit to Meta**. Status updates arrive every hour. Changing an approved template sends it back to draft.

**Email templates** use {{first_name}}, {{programme}}, {{university}}, {{city}}. Every email gets an "I'm interested, call me" link and the unsubscribe footer.

Sales WhatsApp templates are the Admin's; counsellors' email templates are theirs.$t$, '{/w/templates}', 100),
('marketing', 'guardrails', 'Rules', 'Guardrails', $t$Every marketing message checks, for that lead, at that moment: consent for the channel, the suppression list, quiet hours (9 am to 8 pm IST), at most 1 marketing WhatsApp a day and 6 in 30 days, 2 emails a day, no message within 30 minutes of a Witty chat, nothing while a counsellor is selling (unless the Admin allows it for a journey or campaign), nothing while a partner holds the lead, one journey at a time.

A message held by quiet hours, a cap or a Witty chat waits and goes later; the others are skipped and counted on the Overview.$t$, '{/w/nurture}', 35)
on conflict (role, slug) do nothing;

-- the Admin's guide gets the same nurture articles' pointer
insert into b2c.user_guides (role, slug, section, title, body, screens, sort) values
('admin', 'nurture', 'Marketing', 'Nurture and templates', $t$The Nurture page and the Template page work the same for you as for Marketing (see the Marketing guide). Only you can let a journey or a campaign reach leads in active sales, and only you create the sales and system WhatsApp templates.

Before going live: approve the templates with Meta, set **ANTHROPIC_API_KEY** for reply classification, and check Settings → messaging (quiet hours and caps).$t$, '{/w/nurture,/w/templates}', 75)
on conflict (role, slug) do nothing;
