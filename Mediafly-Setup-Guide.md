# Mediafly Integration — Setup Guide (Start Here)

This is the paint-by-numbers guide for standing up the **Level 1 Mediafly content search** in a Salesforce org. Follow the phases top to bottom. Every step maps to the exact names used in the reference code, so you can copy values straight across.

- **What you get when done:** a rep asks the P&G Sales Companion for materials ("what do I have for Oral-B iO hygienist training?") and the agent returns a short ranked list of Mediafly assets with direct links.
- **What this does NOT do:** answer questions from inside a PDF/deck/video. Mediafly's API returns asset metadata and links only. See `Mediafly-Agent-Action-Walkthrough.md` for the why.
- **Time estimate:** ~2–3 hours of Salesforce config once you have the Mediafly values from Phase 1.

If you want the design rationale and API details, read `Mediafly-Agent-Action-Walkthrough.md`. This guide is just the steps.

---

## Phase 1 — Get these values from Mediafly

Request these from your Mediafly rep before you start. You cannot finish without them.

| # | You need | Where it plugs in later |
|---|----------|-------------------------|
| 1 | A dedicated **service-account** username + password (not a rep's login) | External Credential principal (Phase 3) |
| 2 | The **Company Code** for the P&G tenant | `Mediafly_Config__mdt.Company_Code__c` (Phase 4) |
| 3 | The **productId** (UUID) for the P&G environment | `Mediafly_Config__mdt.Product_Id__c` (Phase 4) |
| 4 | The **Accounts API base URL** (token host) | `Mediafly_Accounts` Named Credential URL (Phase 3) |
| 5 | The **Launchpad API base URL** (e.g. `https://launchpadapi.mediafly.com`) | `Mediafly_Launchpad` Named Credential URL (Phase 3) |
| 6 | The exact **token endpoint path** and the **token field name** in the response | Two `TODO`s in `MediaflyAuthService.cls` (Phase 5) |
| 7 | Confirmation of **direct-link behavior** — do reps need to be logged into Mediafly for links to open? | Informs the rep experience; no code change |

> **Auth model (confirmed by Mediafly, July 2026):** the public API authorizes at the **service-account level, not per user**, so search results reflect the integration account's access. Viewer links stay permission-enforced on open (the rep is prompted to log in and only sees assets they can access). Per-user, permission-scoped *search* is only available via Mediafly's **MCP + OAuth** route (the recommended production path — see the walkthrough). For a pilot where every rep should see the same POH content library, the service-account model in this guide is correct as-is. The only open item is a P&G product decision: is per-rep content scoping required for the pilot?

---

## Phase 2 — Copy the code into your project

Copy these four files from this repo into your SFDX project (e.g. `force-app/main/default/classes/` and your agent bundle). They are reference files with no `-meta.xml` — add the standard Apex class meta files as you copy them in.

- `apex/SearchMediaflyContentAction.cls`
- `apex/MediaflyAuthService.cls`
- `apex/MediaflyConfig.cls`
- `agent/PG_SalesCompanion.agent` (the `mediafly_content_search` subagent + router transition — Phase 6)

---

## Phase 3 — Create the credentials (no secrets in code)

You will create **two** Named Credentials. The service-account username/password live here, never in Apex.

**3a. Accounts (token) credential — `Mediafly_Accounts`**

This credential holds the service-account login used to fetch the token. The exact auth setup depends on what Mediafly confirms in Phase 1 #6, but the recommended pattern in the current Named Credential model is:

1. Setup → Named Credentials → **External Credentials** → New.
   - Label / Name: `Mediafly_Accounts`
   - Authentication Protocol: **Custom** (the new model has no built-in "Basic" protocol; you build the auth header yourself).
2. Under **Principals**, add a Named Principal (e.g. `Mediafly_Service_Account`) and store the service-account **username** and **password** from Phase 1 #1 as protected **Custom Headers / Parameters** on that principal (they are stored encrypted, never in code).
   - If Mediafly's token call expects HTTP Basic auth, add a Custom Header on the External Credential named `Authorization` with value `Basic <base64(username:password)>` (or the equivalent credential merge field). Confirm the exact shape against Phase 1 #6.
3. Setup → Named Credentials → **Named Credentials** → New.
   - Label / Name: **`Mediafly_Accounts`** (must match exactly — the code calls `callout:Mediafly_Accounts`)
   - URL: the Accounts API base URL from Phase 1 #4 — must be **HTTPS**.
   - Link it to the External Credential above, and enable "Allow Formulas in HTTP Header" if you used a header merge field.

**3b. Launchpad (search) credential — `Mediafly_Launchpad`**
4. Create a Named Credential named **`Mediafly_Launchpad`** (the code calls `callout:Mediafly_Launchpad`).
   - URL: the Launchpad base URL from Phase 1 #5 — must be **HTTPS**.
   - The code attaches the Bearer token itself, so this credential does not need its own auth principal (set "No Authentication" / anonymous).
   - **Turn OFF "Generate Authorization Header"** on this Named Credential so the code's manual `Authorization: Bearer <token>` header is honored and Salesforce does not generate a conflicting one.

**3c. Grant Principal Access on a permission set (do NOT skip — callouts fail without it)**
5. On the permission set you use for this integration (the same one from Phase 7): Setup → Permission Sets → your set → **External Credential Principal Access** → **Add** the `Mediafly_Accounts` principal from step 2.
   - Without this, callouts fail at runtime with an "unauthorized / no access to named credential" style error even though everything else is configured correctly. This is the most commonly missed step.

> Names must match exactly: `Mediafly_Accounts` and `Mediafly_Launchpad`. The Apex references them as `callout:Mediafly_Accounts` and `callout:Mediafly_Launchpad`. Both URLs must be HTTPS. Because the endpoint host comes only from the Named Credential (the search term is a URL-encoded query param), the bearer token can never be sent to a host other than Mediafly.

---

## Phase 4 — Create the config metadata

1. Setup → **Custom Metadata Types** → New.
   - Label: `Mediafly Config`  •  Object Name: **`Mediafly_Config`** (API name becomes `Mediafly_Config__mdt`)
2. Add these custom fields:
   - `Company_Code__c` — Text
   - `Product_Id__c` — Text
   - `Api_Version__c` — Number (0 decimals)
3. Manage Records → New. Set **Label** and **DeveloperName** to exactly **`Default`** (the code calls `getInstance('Default')`).
   - `Company_Code__c` = Phase 1 #2
   - `Product_Id__c` = Phase 1 #3
   - `Api_Version__c` = `3` (unless Mediafly says otherwise)

---

## Phase 5 — Confirm the two token TODOs

Open `MediaflyAuthService.cls` and resolve the two `TODO` markers using the Mediafly Accounts API docs (<https://devdocs.mediafly.com/accounts/>) and the values from Phase 1 #6:

1. **Token endpoint path** — line with `req.setEndpoint(ACCOUNTS_NAMED_CREDENTIAL + '/tokens');`. Change `/tokens` to the real Accounts API token path if different.
2. **Token field name** — line with `String token = (String) body.get('accessToken');`. Change `accessToken` to whatever field name the Accounts API returns the token in.

Also confirm whether the token call needs the `X-Company-Code` header (already sent) or the Company Code in the body/URL, and adjust if needed.

---

## Phase 6 — Create the Platform Cache partition

The ~1-hour token is cached and reused across reps. Without this, the code still works (it falls back to fetching a token each call) but is slower.

1. Setup → **Platform Cache** → New Platform Cache Partition.
   - Name: **`Mediafly`** (must match — the code calls `Cache.Org.getPartition('Mediafly')`)
   - Allocate a small **Org** cache capacity (even 1 MB is plenty).

---

## Phase 7 — Wire the agent + grant access

1. Bring the `mediafly_content_search` subagent and the router's `go_to_mediafly_content` transition from `agent/PG_SalesCompanion.agent` into your agent. `PG_SalesCompanion.agent` is an Agent Script file — recreate the subagent in Agentforce Builder, or merge the snippet into your own agent's script/metadata. (The router already had a `go_to_product_qa` transition; this replaces it.)
2. Confirm the action target resolves: `search_mediafly_content` → `apex://SearchMediaflyContentAction`.
3. On the permission set from Phase 3c, also grant **Apex class access** to `SearchMediaflyContentAction`, `MediaflyAuthService`, and `MediaflyConfig`, and assign that permission set to the agent's running user and any test users.
4. Deploy everything and activate the agent version.

---

## Phase 7.5 — Smoke-test the callout first (recommended)

Before touching the agent, confirm auth + search work in isolation. This separates credential problems from agent-wiring problems. Run in Setup → Developer Console → **Execute Anonymous**:

```apex
SearchMediaflyContentAction.Request r = new SearchMediaflyContentAction.Request();
r.searchTerm = 'Oral-B iO';
System.debug(SearchMediaflyContentAction.search(new List<SearchMediaflyContentAction.Request>{ r })[0].summary);
```

- If you get a ranked list of assets, credentials and config are correct — move on to the agent.
- If you get an auth error, revisit Phase 3 (especially the Principal Access in 3c and the token TODOs in Phase 5) before blaming the agent.

---

## Phase 8 — Test

Run these in the agent's live-action preview:

```text
What materials do I have for Oral-B iO hygienist training?
Pull up the Gingivitis ER sell sheet.
Find assets for Crest Gum Detoxify.
Do we have a video I can share about iO patient outcomes?
```

**Definition of done:**
- The router sends these to `mediafly_content_search` (not briefing or logging).
- You get a short ranked list (≤ 3–5) of real Mediafly assets, each with a link.
- A nonsense search returns a polite "refine your search" message, not an error.
- Tapping a link opens the asset in Mediafly.

---

## Phase 9 — Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Callout fails immediately with "unauthorized" / no access to the named credential | Permission set is missing External Credential Principal Access | Add the `Mediafly_Accounts` principal on the permission set (Phase 3c) and assign it to the running user |
| "Unable to authenticate with Mediafly" | Wrong token path/field, or bad service-account creds | Recheck Phase 5 TODOs and the `Mediafly_Accounts` principal |
| "I could not reach Mediafly just now" (non-401) | Wrong Launchpad URL, missing `productId`, or callout not allowed | Verify `Mediafly_Launchpad` URL + `Product_Id__c`; confirm the org allows the callout |
| Every search returns no results | `productId` wrong, or service account lacks content permissions | Confirm Phase 1 #3 and the service account's library access |
| Repeated auth on every call / slow | Platform Cache partition missing or misnamed | Create the `Mediafly` Org partition (Phase 6) |
| Links prompt a login | Direct-link behavior requires an active Mediafly session | Expected — reps should be signed into Mediafly (Phase 1 #7) |

---

## Security hardening

The reference implementation already follows the core Salesforce security practices: secrets live only in Named/External Credentials and `Mediafly_Config__mdt` (never in code or source control); the rep's search term is URL-encoded before it reaches the callout; the bearer token can only be sent to the Mediafly host (the endpoint host comes from the Named Credential, not from user input); errors returned to the rep never contain tokens, exceptions, or HTTP bodies; and debug logs never write the token or response body. Classes are `with sharing`, the token is short-lived, and a rejected token triggers a single refresh-and-retry.

Confirm or tighten the following before go-live:

1. **Least privilege on the Mediafly service account (most important).** All rep searches run under one Mediafly identity, so every rep effectively sees everything that account can see. Ask Mediafly to scope the service account to only the content appropriate for all pilot reps. This authorization boundary lives on the Mediafly side, not in Salesforce.
2. **Cached-token visibility.** The ~1-hour token is stored in an Org Platform Cache partition, which any Apex in the org can read. This is an accepted trade-off for a read-only content-library token with a short TTL. If the content is sensitive, tighten it: shorten the TTL, or remove Org caching and re-authenticate per call (slower, but the token never persists).
3. **Named Credential settings.** Both credentials must be HTTPS. On `Mediafly_Launchpad`, "Generate Authorization Header" must be OFF (see Phase 3). Do not add a Remote Site Setting that broadens allowed callout hosts beyond Mediafly.
4. **Credential rotation.** The service-account password is long-lived and powerful. Agree a rotation cadence with the P&G/Mediafly admins; rotate it in the External Credential principal (no code change needed).
5. **Search-term governance.** The rep's typed search phrase is sent to Mediafly. It is the only data that leaves the org. If P&G is strict about data egress, advise reps not to type patient or personal information into searches.

## Pre-commit check

- No service-account username/password, token, `productId`, or Company Code in Apex, the agent script, or source control.
- The action never returns raw tokens, exceptions, or HTTP bodies to the rep.
