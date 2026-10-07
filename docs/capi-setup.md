# Conversions (CAPI): setup guide

The B2B CRM reports what happens to leads from Meta and Google ads back to those platforms. Ads can then optimise for
qualified leads and enrolments instead of form fills.
- Every lead with an ad identifier is reported, whether it went to a partner or to Eduwit's B2C team.
- Email and phone are sent only as SHA-256 hashes.
- Test leads are never sent.
- Nothing is sent until a platform's switch on the Conversions screen is on.

## Milestones and default events

| Milestone | When | Meta event (default) | Google |
| --- | --- | --- | --- |
| Lead received | The enquiry | `Lead` (off: the platform counts its own leads) | off |
| Ready to route | Qualified and sent to a partner or to B2C | `Qualified Lead` | on, needs a conversion action |
| Accepted | A partner accepted it, or B2C took it | `Sales Accepted Lead` | on |
| Contacted | First call or message reached the student | `Contacted` | off |
| Applied | Application made | `Applied` | on |
| Enrolled | Enrolment reported; value is the expected net commission in ₹ | `Enrolled` | on |
| Enrolment verified | Proof checked; value is the realised net commission in ₹ | `Enrollment Verified` | on |
| Disqualified | Junk, only when Routing → Hand-off rules → junk signal is on | `Disqualified Lead` | off |

Each milestone is sent once per lead and enquiry (event ID `<lead>:<stage>:<cycle>`).

## Consent

By default, only students with **marketing** consent are reported. Setup can change this to **contact** consent.
Events without the consent are logged as skipped. They are sent if the consent arrives later and the event is still
recent enough: 7 days for Meta, 90 days for Google.

## Meta

1. In Events Manager, choose the dataset (pixel) your lead forms and website use. Under Settings → Conversions API, generate an access token.
2. On Conversions → Setup, enter the dataset ID and the token.
3. For Lead Ads, set up the CRM integration (conversion leads) in Events Manager. Use the same stage names as the "Meta event name" column.
4. Before going live, put a **test event code** (from Events Manager → Test events) in Setup. Then turn Meta on and watch the events arrive in Test events.
5. Remove the test event code to send real events.

Leads match on the Meta lead ID (Lead Ads), the click (`fbc`, built from `fbclid`), the browser ID (`fbp`), and the hashed email and phone.

## Google Ads

1. Create one conversion action per milestone you want, using "Import → CRMs, files or other data sources → Track conversions from clicks". Copy each action's resource name, `customers/<id>/conversionActions/<id>`.
2. In Google Ads → Tools → API Center, get a developer token (basic access or higher).
3. In Google Cloud, create an OAuth client. Then create a refresh token, with the `adwords` scope, for a user who can access the Ads account.
4. On Conversions → Setup, enter:
   - the customer ID;
   - the manager account ID, if access goes through an MCC;
   - the developer token, client ID, client secret and refresh token;
   - each milestone's conversion action.
5. Turn Google on. Uploads use the gclid, gbraid or wbraid, plus hashed email and phone (enhanced conversions for leads; accept its terms in Google Ads).

## Checking a lead

Conversions → Check a lead shows, for any lead number:
- its ad identifiers and consent;
- the milestones it has reached;
- the exact payload each platform would get.

Use a test lead (phone `910000…`): its events are logged as dry runs and never sent.

## When something fails

- Failures retry after 1, 5 and 30 minutes, then 2 and 6 hours.
- An event the platform refuses (for example a click that is too old) is marked **Rejected** and not retried.
- The Command Center alerts on failures and refused credentials.
- Retry is on the Event log.
