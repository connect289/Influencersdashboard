# Eduwit B2B CRM: partner CRM adapters

Most partners run their admissions on a standard CRM. For these, Eduwit does not ask the partner to build anything: the
B2B CRM creates the lead through the CRM's own API and reads stage changes back. Partners on their own system use the
generic contract in `partner-api.md` instead.

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
5. **Live**: enter the live settings and keys and Save. Polling runs every 10 minutes (set 2–1,440 under
   *Fields and polling*, or turn it off if the partner sends webhooks). The live field list is checked daily; a change
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

## Not yet verified

The adapters are built from each CRM's public API documentation and tested against simulated replies. None has been
run against a real account yet. Before a partner goes live, run the sandbox steps above and check the first pushes in
the Pushes table. Known points to watch:

- Salesforce: the token call sends the grant in the query string with a JSON content type (pg_net's limitation).
  Salesforce normally expects a form body; if it refuses, the token call moves to a server route.
- Meritto: the API shape varies by account; confirm the create URL and the reply format with the partner.
- Zoho: refresh tokens issued by one data centre only work with that centre's accounts domain.
