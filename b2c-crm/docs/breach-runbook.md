# Eduwit Spark: breach runbook

What to do when personal data in Spark (students' names, phones, emails, documents, chats; staff accounts) may have been
seen, copied, changed or lost by someone who should not have it. Spec B18 (DPDP Act 2023). Keep it short and in order:
**contain, assess, notify, recover, review**. When in doubt, contain first and ask afterwards.

**Contact and decision-maker: Vikas, vikas@eduwit.in.** Eduwit's lawyer advises on notices. Write everything down as
you go (who, what, when, in IST) in one incident note: the Board and CERT-In will ask for it.

Signs that start this runbook: an unknown device in someone's "Signed-in devices", sign-ins from unexpected places,
an export nobody asked for, a leaked key or `.env` file, a laptop or phone lost with Spark signed in, a report from a
student or partner, an alert from Supabase, Vercel, Google or GitHub (secret scanning, Dependabot).

## 1. Contain (first hour)

1. **Stop outgoing messages.** In Vercel set `LIVE_MODE=off` and redeploy; in the SQL editor:
   `update b2c.settings set value = '{"whatsapp": false, "email": false}', updated_at = now() where key = 'live_mode';`
2. **Sign everyone out.** Spark checks every request against `b2c.session_checks`, so this takes effect at once (it is
   what `b2c.session_revoke` does for each person; the SQL editor has no signed-in Admin, so run it directly):
   ```sql
   update b2c.session_checks set revoked_at = now() where revoked_at is null;
   update b2c.trusted_devices set revoked_at = now() where revoked_at is null;
   insert into b2c.audit_log (action, detail) values ('sign_out_remote', '{"scope": "everyone", "reason": "breach runbook"}');
   ```
   For one person instead: the same two updates with `where user_id = '<uuid>'`, or the person uses Me → Signed-in
   devices → "Sign out everywhere else".
   Then rotate Supabase's JWT signing key (Project Settings → JWT Keys: rotate, then revoke the old key) so stolen
   access tokens stop working too.
3. **Deactivate** any account that may be compromised (Teams → deactivate; in Google Workspace suspend the user and
   reset the password). The daily Teams sync also deactivates suspended Workspace users.
4. **Rotate secrets** (each in its own system, then the new value in Vercel and a redeploy). Start with whatever leaked:
   - `SUPABASE_SERVICE_ROLE_KEY`: Supabase → Project Settings → API keys: create a new secret key, deploy it, delete the
     old one.
   - `B2B_SIGNING_SECRET` and `B2B_API_KEY`: with the B2B developer (B2B CRM → System health → Webhooks and API keys).
   - `B2C_INTERNAL_KEY`: new value in Vercel and in Vault (`select vault.update_secret(id, '<new>') from vault.secrets
     where name = 'b2c_internal_key';`).
   - `GMAIL_TOKEN_KEY` and `GOOGLE_OAUTH_CLIENT_SECRET`: a new key makes every stored Gmail connection unreadable, which
     is the point; also reset the OAuth client secret in Google Cloud. Everyone reconnects Gmail on Me.
   - `GOOGLE_SA_PRIVATE_KEY`: delete the service account key in Google Cloud and create a new one.
   - `WHATSAPP_TOKEN` and `WHATSAPP_APP_SECRET` (Meta Business settings), `ANTHROPIC_API_KEY`, `SMTP_PASSWORD`, the
     `EXOTEL_*` keys, `LINK_SECRET` (old links in sent emails stop working; acceptable in a breach).
5. **Preserve evidence.** Do not delete logs or rows. Export the Vercel and Supabase logs for the window (they expire),
   and take a copy of `b2c.audit_log`, `b2c.sign_in_log` and `b2c.session_checks` for the period.

## 2. Assess (same day)

Work out what was reached, whose data, from when to when. Useful queries (SQL editor; adjust the window):

```sql
-- sign-ins: failures, refusals, unusual addresses
select at, email, method, outcome, ip, user_agent from b2c.sign_in_log
 where at > now() - interval '14 days' order by at desc;
select ip, count(*) n, array_agg(distinct email) who from b2c.sign_in_log
 where at > now() - interval '14 days' and outcome not in ('success', 'code_sent') group by ip order by n desc;

-- sessions and the devices behind them
select c.session_id, u.email, c.method, c.at, c.last_seen_at, c.ip, c.user_agent, c.revoked_at
  from b2c.session_checks c join b2c.users u using (user_id) where c.at > now() - interval '30 days' order by c.at desc;

-- sensitive actions: exports, phone reveals, viewing as someone else, settings, deletions, connections
select at, actor_id, action, lead_id, detail from b2c.audit_log
 where at > now() - interval '14 days'
   and action in ('export', 'phone_reveal', 'view_as_sales', 'settings', 'delete', 'contact_edit', 'connection_saved', 'sign_out_remote')
 order by at desc;
select id, user_id, status, rows, created_at, params from b2c.exports where created_at > now() - interval '14 days' order by id desc;

-- traffic on the public endpoints (rate-limit counters, last hour)
select key, bucket, n from b2c.rate_hits order by n desc limit 50;
```

Also check: Supabase logs (API, Auth, Storage: downloads from `b2c-documents`, `b2c-recordings`, `b2c-exports`), Vercel
logs for `/v1/*` and `/api/internal/*`, the Google Workspace audit log (Gmail and Drive), Meta's WhatsApp account
activity, GitHub for leaked secrets. Decide: **is it a personal data breach** (any unauthorised processing, accidental
disclosure, loss of access, change or destruction of personal data)? If yes, or not sure, notify.

## 3. Notify (without delay)

Under India's **Digital Personal Data Protection Act, 2023** (section 8(6)) and the **DPDP Rules, 2025** (rule 7),
Eduwit as the Data Fiduciary informs, without delay:

- **The Data Protection Board of India**: at once, a description of the breach (nature, extent, timing, location,
  likely impact); then, **within 72 hours** of becoming aware (or longer if the Board allows), the detailed report:
  updated facts, the circumstances and reasons, what was done to limit the harm, who caused it if known, what will stop
  it happening again, and a report on the notices sent to students, through the Board's digital channel.
- **Every affected student (and staff member)**, in plain language, by email or WhatsApp from the system mailbox (turn
  live mode back on for that send only, or send by hand): what happened and when, what data, the likely consequences,
  what Eduwit has done, what they can do (beware of calls or messages claiming to be Eduwit, change passwords), and
  who to contact (Vikas, vikas@eduwit.in).
- **Also, separately**: **CERT-In** within 6 hours of noticing a cyber security incident (CERT-In directions of
  28 April 2022: incident@cert-in.org.in); the **B2B CRM side and partners** if shared leads are affected (they have
  their own duties); Supabase, Vercel, Google or Meta if their service was the way in.

The lawyer confirms the wording and which provisions are in force on the day (the Rules phase in); do not wait for a
perfect answer to send the first notices.

## 4. Recover

- Fix the cause (patch, configuration, access) and deploy; check with `npx tsc --noEmit`, `npx vitest run` and the
  CI dependency audit.
- Restore damaged data from Supabase backups (point-in-time recovery) into a separate project first; compare, then
  copy back what is needed. Never overwrite live data blind.
- Bring people back one by one: they sign in again (emailed code), reconnect Gmail, and the Admin re-enables any
  deactivated accounts that were clean. Turn live mode back on only when Vikas agrees.

## 5. Review (within two weeks)

A short blameless note: timeline, cause, what worked, what did not, actions with owners and dates. Update this runbook,
the rate limits and the alerts if they would have caught it sooner. Keep the incident note and notices for at least
the retention period the lawyer sets.
