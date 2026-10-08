# Eduwit B2B CRM: partner CRM adapters

Most partners run their admissions on a standard CRM. For these, Eduwit does not ask the partner to build anything: the
B2B CRM creates the lead through the CRM's own API and reads stage changes back. Partners with their own in-house CRM
have three options, described under [Partners with an in-house CRM](#partners-with-an-in-house-crm).

| CRM | Creates the lead with | Duplicate check | Reads changes back | Field list (Mapping studio) |
| --- | --- | --- | --- | --- |
| LeadSquared | `POST https://<host>/v2/LeadManagement.svc/Lead.Create` (access and secret key headers) | LeadSquared's unique fields (Phone, and Email if the partner set it) | Polls `Leads.RecentlyModified` | `LeadsMetaData.Get` |
| Zoho CRM | `POST https://<api domain>/crm/v5/Leads` (OAuth, refresh token) | Zoho's unique fields (`DUPLICATE_DATA`) | Polls Leads with `If-Modified-Since` | `/crm/v5/settings/fields` |
| Salesforce | `POST <instance>/services/data/<version>/sobjects/Lead/` (OAuth, refresh token) | The org's Lead duplicate rule (`DUPLICATES_DETECTED`) | SOQL query on `LastModifiedDate` | `sobjects/Lead/describe` |
| HubSpot | `POST https://api.hubapi.com/crm/v3/objects/contacts` (private app token) | Email is unique (HTTP 409) | Contacts search on `lastmodifieddate` | `/crm/v3/properties/contacts` |
| Meritto (NoPaperForms) | `POST <base url>/lead/v1/create` (access and secret key headers) | "already exists" in the reply | Webhook only (events address, `partner-api.md` §2) | — |

Everything else stays the same as for the generic contract: the hold window, the retries (10 s, 1 min, 5 min, 15 min,
1 h, then the next partner), the duplicate window and disputes, the student's message, and the Pushes table on the
partner's Connection tab.

## What the partner must do

1. **Create a reference field** (single-line text) so Eduwit can find its leads again:

   | CRM | Field |
   | --- | --- |
   | LeadSquared | custom lead field `mx_Eduwit_Reference` |
   | Zoho CRM | Leads custom field, API name `Eduwit_Reference` |
   | Salesforce | Lead field `Eduwit_Reference__c` |
   | HubSpot | contact property `eduwit_reference` |
   | Meritto | `eduwit_reference` on the lead form used for the API |

   Another name works too: enter it under *Fields and polling* on the Connection tab.
2. **Make duplicates fail.** Without this a lead the partner already has is created again and the duplicate is never
   reported to Eduwit.
   - LeadSquared: Phone is unique by default; keep it so.
   - Zoho: mark Phone (and Email if wanted) as *Do not allow duplicate values* on the Leads module.
   - Salesforce: an active Lead duplicate rule (Phone or Email matching rule) with action *Block* on create.
     Eduwit sends `allowSave=false` so the rule blocks instead of warning.
   - HubSpot: Email is unique already. Leads without email cannot be checked by HubSpot.
3. **Give Eduwit an API user** with permission to create and read leads, for both a sandbox (or test account) and live:
   - LeadSquared: an access key and secret key (Settings → API and Webhooks) and the API host for the account's region.
   - Zoho: a *Self Client* or server-based client in the Zoho API console with scopes
     `ZohoCRM.modules.leads.ALL,ZohoCRM.settings.fields.READ`, its client ID and secret, and a refresh token
     (`access_type=offline`). Use the data centre the account lives in (`zohoapis.in` / `accounts.zoho.in` for India).
   - Salesforce: a connected app with OAuth scopes `api refresh_token`, its consumer key and secret, a refresh token for
     an integration user, and the login URL (`https://test.salesforce.com` for a sandbox, or the org's My Domain).
   - HubSpot: a private app with `crm.objects.contacts.read`, `crm.objects.contacts.write` and `crm.schemas.contacts.read`.
   - Meritto: the API access and secret keys and the source name to show on Eduwit's leads.
4. Optionally, send stage changes by webhook as well (`partner-api.md` §2). Polling and webhooks can run together;
   each change is applied once.

## What the Admin does

On the partner's page, set *Adapter* in Settings to the partner's CRM, then open **Connection**:

1. **Sandbox (test leads)**: enter the sandbox settings and keys and Save. Keys go to Supabase Vault and are never
   shown again; leave a key empty to keep the stored one.
2. **Preview a push** shows exactly what the next lead (or a sample student) would send, with credentials masked.
3. Route a test lead from **Routing → Simulate**. Test leads go only to the sandbox, real students only to live.
4. **Fetch fields** takes the CRM's field list into Mapping studio as a schema snapshot; map the CRM's stages there
   (Status map) so polled changes become Eduwit stages.
5. **Live**: enter the live settings and keys and Save. Live polling runs once every sync interval (15 minutes by
   default, set on B2C CRM link → Sync cadence) to keep the partner's API calls down. While testing, the sandbox is polled
   every 2 minutes. A partner's own minutes (2–1,440 under *Fields and polling*) win; turn polling off if the partner
   sends webhooks. The live field list is checked daily; a change
   raises `alert.mapping_drift`.
6. *Fixed values* add fields every lead carries (for example an owner or a source the partner asks for). Mapping studio's
   outbound field map, when it has one, is sent too and wins over the defaults.

## What is sent

Name, phone, email, city, state, the Eduwit reference, the push note and the source `Eduwit`; Meritto also gets
the course and specialisation. Other fields (programme, qualification, timeline, language) can be added with Mapping
studio's outbound map. The student's budget, lead source, campaign and score are never
sent (spec B8.1).

Defaults per CRM:

| CRM | Fields |
| --- | --- |
| LeadSquared | `FirstName`, `LastName`, `Phone` (`+91-XXXXXXXXXX`), `EmailAddress`, `mx_City`, `mx_State`, `Source`, `Notes`, `mx_Eduwit_Reference` |
| Zoho CRM | `First_Name`, `Last_Name` (required; falls back to the full name), `Phone`, `Email`, `City`, `State`, `Lead_Source`, `Description`, `Eduwit_Reference` |
| Salesforce | `FirstName`, `LastName` (required), `Company` (`Individual`), `Phone`, `Email`, `City`, `State`, `LeadSource`, `Description`, `Eduwit_Reference__c` |
| HubSpot | `firstname`, `lastname`, `phone`, `email`, `city`, `state`, `lifecyclestage` (`lead`), `eduwit_reference` |
| Meritto | `name`, `email`, `mobile` (10 digits), `country_dial_code`, `city`, `state`, `course`, `specialization`, `eduwit_reference`, `remarks` |

## How replies are read

| Reply | Result |
| --- | --- |
| Created (with the CRM's record ID) | Accepted; the record ID is stored on the allocation |
| Duplicate | Duplicate: the lead moves on, or becomes a commission dispute if it was already accepted |
| 401/403 or an expired token | The OAuth token is dropped and renewed on the next try; a refused refresh token raises `alert.partner_auth` |
| Anything else | A failed attempt, retried on the usual schedule |

Polling reads leads changed since the last poll that carry an Eduwit reference. A changed stage becomes a `stage`
event and any other change an `update` event, applied exactly as webhook events are (event IDs
`poll:<record>:stage:<modified time>`), so a change seen twice counts once. Leads without an Eduwit reference are
ignored.

## Partners with an in-house CRM

Some partners run their own CRM, built in-house. Choose one of three ways on the partner's *CRM type*:

| Option | CRM type | Who builds what | Use it when |
| --- | --- | --- | --- |
| 1. Eduwit adapts to their API | **In-house CRM (partner's own API)** | Nothing on the partner's side if their CRM already has a create-lead API | The CRM has an API, even a simple one |
| 2. They build Eduwit's contract | **Eduwit's API contract** | The partner's developer implements `partner-api.md` (create, signed events) | They have a developer and no usable API yet |
| 3. No API | Not built for routing (see below) | Nobody; leads are handed over by hand | No API and no developer |

### Option 1: the In-house CRM adapter

On the partner's Connection tab, for sandbox and live:

| Setting | Example | Notes |
| --- | --- | --- |
| Create-lead address | `https://crm.partner.com/api/leads` | `POST`, JSON body. https only. |
| How the CRM checks Eduwit's key | Bearer token / API key in a header / Basic auth / key in the address / no key | As their API documentation says. "No key" suits an IP allow-list. |
| Header or parameter name | `X-Api-Key`, `api_key` | For a key in a header or the address. |
| API key or token | (vault) | For Basic auth enter `user:password`. |
| Wrap the lead in | `lead` | If the API expects `{"lead": {...}}`. Empty: fields at the top level. |
| Record ID in the answer | `data.lead_id` | A dotted path. Empty: `id`, `record_id`, `lead_id`, `data.id`, `result.id` are tried. |
| HTTP status for a duplicate | `422` | 409, `"duplicate": true` or "already exists" in the answer are always read as duplicate. |
| Changed-leads address | `https://crm.partner.com/api/leads?updated_since={since}` | Optional. `GET`; `{since}` becomes the last poll time (ISO, UTC). Without `{since}`, the *since parameter* (default `updated_since`) is added. |

**Fields.** The lead goes out with these plain field names:
- `name`, `first_name`, `last_name`;
- `phone` and `email`;
- `city` and `state`;
- `course`, `specialization`, `university`, `level` and `mode`;
- `eduwit_reference`, `note` and `source: "Eduwit"`.

Rename or add fields with Mapping studio's outbound map. Every lead can also carry fixed values.

**Status back.** There are three ways, and they can run together:
- polling the changed-leads address;
- the partner calling Eduwit's events address (`partner-api.md` §2);
- uploading their export on Sync & SLAs.

**The changed-leads list.** It can be:
- a bare array;
- an array under `data`, `records`, `results`, `items`, `leads` or `data.records`.

Each record needs:
- an ID (`id`, `record_id` or `lead_id`);
- the Eduwit reference;
- the status;
- ideally a modified time (`updated_at`, `modified_at`…).

The status and reference fields may be nested; write them as paths such as `stage.name`. Map the CRM's statuses to
Eduwit stages in Mapping studio.

**Answers.** Answers to a create call are read as follows:

| Answer | Result |
| --- | --- |
| 2xx | Created |
| The partner's duplicate status, 409, or a duplicate flag or message | Duplicate (with the existing record ID if given) |
| 401 or 403 | Credentials refused: an alert is raised |
| 403 or 422 with `"rejected": true` or a `reason` | Rejected |
| Anything else | A failed attempt, retried on the usual schedule |

**What to ask the partner's developer:**
- the create-lead address and a sandbox one;
- a key for Eduwit;
- what a duplicate answer looks like;
- where the new lead's ID is in the answer;
- to store `eduwit_reference` on the lead;
- optionally, a changed-leads address.

### Option 3: no API

The CRM cannot route automatically to a partner without an API: there is no email or file push yet. For now:
- keep the partner paused for routing;
- export the leads meant for it from Leads and hand them over yourself;
- reconcile the partner's export on Sync & SLAs (matched by reference, phone or name);
- reconcile its commission statement on Commission & Finance. Enrolments found only in the partner's statement show as
  *partner only* for checking.

An email or CSV push for such partners can be added if needed.

## Not yet verified

The adapters are built from each CRM's public API documentation and tested against simulated replies. None has been
run against a real account yet. Before a partner goes live, run the sandbox steps above and check the first pushes in
the Pushes table. Known points to watch:

- Salesforce: the token call sends the grant in the query string with a JSON content type (pg_net's limitation).
  Salesforce normally expects a form body; if it refuses, the token call moves to a server route.
- Meritto: the API shape varies by account; confirm the create URL and the reply format with the partner.
- Zoho: refresh tokens issued by one data centre only work with that centre's accounts domain.
- In-house CRMs differ: preview a push and send a test lead to the partner's sandbox before going live, and check the
  first answers in the Pushes table (record ID found, duplicates read as duplicates).
