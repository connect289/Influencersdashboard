# Conversions (CAPI): setup guide

The B2B CRM tells Meta and Google how far each lead from **their paid ads** got. Their bidding then learns which
campaigns bring students who enrol, not just form fills.
- **Paid leads only.** A lead is reported only if a paid Meta or Google ad brought it, and only to that platform. A lead
  from a Google ad never reaches Meta, and an organic lead reaches neither.
- **Campaign by campaign.** Every lead's campaign is recorded, and each event carries it, so the platform's feedback
  lands on the campaign that bought the lead.
- Email and phone are sent only as SHA-256 hashes.
- Test leads are never sent.
- Nothing is sent until a platform's switch on the Conversions screen is on.

## Which leads count as paid

Every lead gets a campaign record (`b2b.lead_campaigns`) for its current enquiry. The record holds:
- the platform;
- whether the lead is paid;
- campaign, ad set and ad (IDs and names);
- the lead form;
- the UTM tags.

The first paid touch of the enquiry wins. Sources, in time order:

| Source | Paid when |
| --- | --- |
| Meta Lead Ads form | The form fill came from an ad (Meta's `is_organic` is false) |
| Google lead form | Always (it lives in an ad) |
| Any touch with an ad click ID (API, imports, the website, Witty's link) | It carries `fbclid` / `fbc` (Meta) or `gclid` / `gbraid` / `wbraid` (Google) |
| UTM tags only | `utm_medium` is cpc, ppc, paid, paid_social, cpm, display, sem… |

A lead with **UTM tags only** is recorded and shown on the Campaigns tab, but it is not reported: the platform has no way
to match it to its ad. Meta's browser cookie (`fbp`) on its own is not an ad click either. To report website leads,
make the site pass the click ID (`fbclid`, `gclid`) to the intake API.

## Signals, strongest first

| Signal | When | Value sent | Meta event | Google |
| --- | --- | --- | --- | --- |
| Enrolled (verified) | Enrolment reported (then verified) | The expected (then realised) net commission | `Enrolled` / `Enrollment Verified` | one conversion action |
| Applicant | The student applied | 40% of the lead's expected commission | `Applicant` | one conversion action |
| Interested | Counselled or further, as reported by the partner's CRM or the B2C CRM | 15% | `Interested` | one conversion action |
| Qualified | Routed to a partner or to Eduwit's B2C sales team (not nurture, not junk) | 5% | `Qualified Lead` | one conversion action |

The percentages and the default commission are set on Conversions → Setup → *Signals and their value*. The default
commission is ₹15,000 and is used when the lead's allocation has no expected commission.

Weak signals are kept but off by default:
- Lead received;
- Accepted;
- Contacted;
- Disqualified (junk), which is sent only when Routing → Hand-off rules → junk signal is on.

Each signal is sent once per lead and enquiry (event ID `<lead>:<signal>:<cycle>`).

**Optimising.** Optimise a campaign for the strongest signal that reaches about 50 events a week. Start with Applicant or
Interested, and move to Enrolled once volume allows. In Google Ads, make Enrolled (or Applicant) the primary conversion
action and keep the earlier ones secondary.

## The Campaigns tab

Conversions → Campaigns lists, for the last 30, 90, 180 or 365 days, every paid campaign with:
- its leads, and how many the platform can match;
- how many became qualified, interested, applicants and enrolled (with the share of the campaign's leads);
- junk;
- the commission earned;
- the events sent.

This is what each platform learns about its own campaigns. Use it to compare campaigns across Meta and Google on
enrolments and commission, not on cost per lead.

## Consent

By default, only students with **marketing** consent are reported. Setup can change this to **contact** consent.
Events without the consent are logged as skipped. They are sent if the consent arrives later and the event is still
recent enough: 7 days for Meta, 90 days for Google.

## Meta

1. In Events Manager, choose the dataset (pixel) your lead forms and website use. Under Settings → Conversions API, generate an access token.
2. On Conversions → Setup, enter the dataset ID and the token.
3. For Lead Ads, set up the CRM integration (conversion leads) in Events Manager. Use the same stage names as the "Meta event name" column: Qualified Lead, Interested, Applicant, Enrolled.
4. Before going live, put a **test event code** (from Events Manager → Test events) in Setup. Then turn Meta on and watch the events arrive in Test events.
5. Remove the test event code to send real events.

Leads match on:
- the Meta lead ID (Lead Ads);
- the click (`fbc`, built from `fbclid`);
- the browser ID (`fbp`), when the lead also has a click;
- the hashed email and phone.

## Google Ads

1. Create one conversion action per signal: Qualified lead, Interested, Applicant and Enrolled. Use "Import → CRMs, files or other data sources → Track conversions from clicks". Copy each action's resource name, `customers/<id>/conversionActions/<id>`.
2. In Google Ads → Tools → API Center, get a developer token (basic access or higher).
3. In Google Cloud, create an OAuth client. Then create a refresh token, with the `adwords` scope, for a user who can access the Ads account.
4. On Conversions → Setup, enter:
   - the customer ID;
   - the manager account ID, if access goes through an MCC;
   - the developer token, client ID, client secret and refresh token;
   - each signal's conversion action.
5. Turn Google on. Uploads use the gclid, gbraid or wbraid, plus hashed email and phone (enhanced conversions for leads; accept its terms in Google Ads).

A signal that is ticked but has no conversion action is logged and held until you add one.

## Checking a lead

Conversions → Check a lead shows, for any lead number:
- its campaign: paid or not, the platform, the campaign, ad set and ad;
- its ad identifiers and consent;
- the signals it has reached, with their values;
- the exact payload its platform would get.

Use a test lead (phone `910000…`): its events are logged as dry runs and never sent.

## When something fails

- Failures retry after 1, 5 and 30 minutes, then 2 and 6 hours.
- An event the platform refuses (for example a click that is too old) is marked **Rejected** and not retried.
- The Command Center alerts on failures and refused credentials.
- Retry is on the Event log.
