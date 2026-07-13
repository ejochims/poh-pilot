# Mediafly Agent Action Walkthrough

This guide describes a phase-two path for connecting the P&G Sales Companion to Mediafly. The goal is Level 1 content retrieval: a rep asks for sales materials, the agent searches Mediafly, and the agent returns a short ranked list of direct links back to Mediafly.

Mediafly remains the source of truth. Salesforce does not duplicate the content library, and Agentforce does not answer from inside the documents in this level of the integration.

## Target Use Case

The rep has already reviewed a pre-visit brief or is preparing for a customer conversation. They ask the agent for relevant materials:

```text
What materials do I have for Oral-B iO hygienist training?
Pull up the Gingivitis ER sell sheet.
Find assets for Crest Gum Detoxify.
```

The agent calls a Mediafly search action and responds with a short list:

```text
Here are the top Mediafly matches for "Oral-B iO hygienist training":

1. iO White Box Sampling Guide (PDF) - View in Mediafly: <mediafly-link>
2. Hygienist Integration Talking Points (PPT) - View in Mediafly: <mediafly-link>
3. Oral-B iO Patient Outcomes Video (MP4) - View in Mediafly: <mediafly-link>
```

The rep taps a link and opens the asset directly in Mediafly. If Mediafly requires user authentication to open the asset URL, the rep should be signed in to the Mediafly app or browser session as they normally would be during the sales day.

## Level 1 Architecture

```mermaid
flowchart LR
    Rep[Field Rep] --> Agentforce[PG Sales Companion]
    Agentforce --> AgentAction[Mediafly Search Action]
    AgentAction --> NamedCredential[Salesforce Named Credential]
    NamedCredential --> AccountsAPI[Mediafly Accounts API]
    AgentAction --> LaunchpadAPI[Mediafly Launchpad API]
    LaunchpadAPI --> MediaflyAssets[Mediafly Assets]
```

The Agentforce action is intentionally separate from the pre-visit brief. The pre-visit brief stays grounded in Salesforce account, visit, order, and sampling data. Mediafly search is a separate request when the rep wants content to share or review.

## What P&G Needs From Mediafly

Before implementation, confirm these values with the Mediafly team:

- A dedicated Mediafly service account for API access. Do not use an individual rep's account.
- Read access for that service account to the content library in scope for the pilot or rollout.
- The `productId` UUID for the P&G Mediafly environment. Launchpad API calls require it.
- Accounts API authentication details for the service account.
- Confirmation of how direct asset links behave for end users, especially whether links require the rep to already be authenticated in Mediafly.
- Any search filters P&G wants applied by default, such as folder, product family, language, region, or only externally shareable content.

Do not commit the service-account username, password, token, `productId`, tenant URL, or any other secret value to this repo.

## Mediafly API Notes

The public Launchpad OpenAPI definition describes Launchpad as Mediafly's content storage service.

For Level 1 search, the relevant endpoint is:

```text
/{version}/items/search
```

Use `version = 3` unless Mediafly instructs otherwise.

The endpoint requires `productId` as a query parameter. The public spec exposes two search shapes:

- `GET /{version}/items/search` with query parameters such as `Term`, `Limit`, `IsAISearch`, and `productId`.
- `POST /{version}/items/search` with a `SearchRequest` JSON body and `productId` as a query parameter.

For a simple Agentforce action, start with `GET`. If P&G needs richer filters later, move to `POST` with a `SearchRequest` body.

Useful search parameters:

```text
Term=<rep search phrase>
Limit=3
IsAISearch=true
productId=<MEDIAFLY_PRODUCT_ID>
```

The `SearchRequest` model includes equivalent lower-camel fields such as:

```json
{
  "term": "Oral-B iO hygienist training",
  "limit": 3,
  "isAISearch": true,
  "includeExplanations": true,
  "boostPromoted": true
}
```

Search responses include a wrapper with `success`, `message`, `response`, and `errorCode`. The response contains result items (`ItemModel`), total result count, offsets, optional facets, optional scoring explanations, and item-level search scoring fields. Item links are exposed through `link.href`.

What the search API returns — and what it does not:

- Each `ItemModel` carries a free-form `metadata` dictionary (title, description, and whatever custom attributes P&G configured), a `type`, a `link`/`href`, a `thumbnail`, an `asset` file reference, and relevance scores.
- The Launchpad search API does **not** return the text inside documents — there is no full-text, transcript, OCR, or extracted-content field, and no content-extraction endpoint anywhere in the public API.

This is the hard constraint behind the Level 1 scope: the agent can discover and link to assets and surface their metadata, but it cannot answer questions from inside a PDF, deck, or video without a separate content-ingestion workstream (see the Level 2 section). Keeping the integration at Level 1 is also exactly what avoids duplicating Mediafly content into Salesforce.

Launchpad calls use bearer-token security. The token is obtained through the Mediafly Accounts API or provided by a Mediafly customer representative. The customer thread described an Accounts API authentication flow that exchanges service-account credentials for a session token that is valid for one hour. Confirm the exact endpoint, request shape, and token field with the current Mediafly Accounts API documentation before implementation.

## Authentication Decision

Mediafly content APIs use a two-step, two-surface auth model:

```mermaid
flowchart LR
    Apex[Apex action] -->|"1. Basic Auth: username:password + Company Code"| Accounts[Mediafly Accounts API]
    Accounts -->|"Access Token (~1 hour)"| Apex
    Apex -->|"2. Bearer <token>"| Launchpad[Launchpad /items/search]
    Launchpad -->|ranked assets + link.href| Apex
```

1. A Mediafly **user's** username/password is sent as HTTP Basic Auth to the Accounts API, which returns an Access Token valid for about one hour.
2. That token is sent as `Authorization: Bearer <token>` on every Launchpad search call. Launchpad has no login endpoint of its own; it only consumes the token.

**Decision used for this pilot: a single dedicated Mediafly service-account identity.**

This is a deliberate choice, not just a default. Confirming P&G's preferred auth model up front was not feasible, so the integration is built on the option that the public Mediafly API actually supports for a server-side (Apex) integration:

- Mediafly has no separate "service account" API type. Every token is minted from a specific Mediafly **user's** credentials and is scoped to that user's content permissions. A "service account" here simply means a regular Mediafly user account dedicated to this integration.
- The public Launchpad and Accounts APIs expose **no OAuth, delegated, on-behalf-of, or token-exchange flow**, and no SCIM/user API. SAML SSO governs interactive login to the Mediafly app only; it does not mint per-user API tokens programmatically.
- True **per-rep** API auth would therefore require storing each rep's Mediafly username/password server-side (a security liability that also breaks on every password reset) or an interactive per-rep auth step the API does not support. Neither is viable for an Agentforce action.

**What this trade-off means:**

- All rep searches run under one Mediafly identity, so results reflect that account's content permissions, and Mediafly attributes all API search/engagement analytics to the service account (no per-rep attribution on the API side).
- The per-rep layer still exists at the click, not the query: when the rep taps a returned `link.href`, the asset opens under the rep's own Mediafly app/browser session (the interactive SSO surface), so content access on open can remain rep-scoped.

**Open questions to confirm with Mediafly when possible (non-blocking for Level 1):**

- Does Mediafly offer an enterprise OAuth or delegated-token option beyond the public docs that would allow rep-scoped tokens? If so, per-rep search becomes possible.
- Does P&G actually require per-rep content scoping or per-rep engagement attribution? If every pilot rep should see the same POH content library, the service-account model is the correct, simpler choice rather than a limitation.

## Salesforce Configuration Pattern

Use Salesforce-managed credentials. Do not hardcode Mediafly secrets in Apex, Agent Script, custom metadata, or prompt templates.

Recommended setup:

1. Create an External Credential or Named Credential for the Mediafly Accounts host.
2. Store the service-account username and password in the credential configuration.
3. Create a Named Credential for the Mediafly Launchpad host, such as `https://launchpadapi.mediafly.com`.
4. Implement token exchange and token caching in the Apex action or in an authentication helper, depending on the supported Named Credential pattern in the target org.
5. Keep `productId` in org-level configuration, such as custom metadata populated per environment or a secure deployment variable. Do not hardcode it in the action.

Suggested placeholder names:

```text
Named Credential: Mediafly_Accounts
Named Credential: Mediafly_Launchpad
Config key: MEDIAFLY_PRODUCT_ID
Service account username: <MEDIAFLY_SERVICE_ACCOUNT_USERNAME>
Service account password: <MEDIAFLY_SERVICE_ACCOUNT_PASSWORD>
```

The Mediafly access token should be reused until expiration. The customer thread described a one-hour token lifetime, so the implementation should refresh only when the token is missing, expired, or rejected by Launchpad.

## Reference Implementation In This Repo

This repo now includes a Level 1 reference implementation you can adapt in your own org:

- `apex/SearchMediaflyContentAction.cls` — the invocable search action wired to the `mediafly_content_search` subagent.
- `apex/MediaflyAuthService.cls` — the two-step service-account token helper (Basic → token → Bearer) with Platform Cache token reuse.
- `apex/MediaflyConfig.cls` — reads `Mediafly_Config__mdt` (Company Code, Product Id, API version) so no tenant values are hardcoded.
- `agent/PG_SalesCompanion.agent` — the `mediafly_content_search` subagent and the router's `go_to_mediafly_content` transition.

These are reference classes (no `-meta.xml`, no tests) meant to be copied into an SFDX project. The endpoint token path and token field name in `MediaflyAuthService` are marked `TODO` because they must be confirmed against the Mediafly Accounts API for the target tenant. Configure the `Mediafly_Accounts` and `Mediafly_Launchpad` credentials and the `Mediafly_Config__mdt` record before use. The contract below documents the action's shape.

## Invocable Action Contract

If P&G chooses to implement this phase, add one Apex invocable action that the agent can call.

Suggested class:

```text
SearchMediaflyContentAction
```

Suggested inputs:

```text
searchTerm: required string
    The product, topic, or asset name the rep asked for.

accountId: optional string
    Salesforce Account ID, if the agent has already resolved the dental practice.
    Level 1 does not require this, but it leaves room for account-aware search later.

limit: optional integer
    Maximum number of Mediafly results to return. Default to 3.
```

Suggested outputs:

```text
summary: string, displayable
    A concise ranked list of matching assets with Mediafly links.

results: list[string]
    Optional structured result strings for the agent to reference.

isSuccess: boolean
    Whether Mediafly search completed successfully.

errorMessage: string
    Friendly message for the rep. Never expose raw exceptions, tokens, stack traces, or HTTP response bodies.
```

Action behavior:

1. Validate `searchTerm`.
2. Resolve or refresh the Mediafly access token.
3. Call Launchpad search with AI search enabled.
4. Parse the top results.
5. Return a short displayable summary with title, content type when available, and `link.href`.
6. Return a friendly no-results message if Mediafly returns zero matches.
7. Return a friendly retry/admin message if authentication or search fails.

The action should not store Mediafly content in Salesforce. It should only return enough metadata for the rep to choose an asset and open it in Mediafly.

## Apex Pseudocode

This is not committed implementation code. It is the shape the Apex action should follow.

```apex
public with sharing class SearchMediaflyContentAction {
    public class Request {
        @InvocableVariable(required=true)
        public String searchTerm;

        @InvocableVariable
        public String accountId;

        @InvocableVariable
        public Integer limit;
    }

    public class Response {
        @InvocableVariable
        public String summary;

        @InvocableVariable
        public List<String> results;

        @InvocableVariable
        public Boolean isSuccess;

        @InvocableVariable
        public String errorMessage;
    }

    @InvocableMethod(
        label='Search Mediafly Content'
        description='Searches Mediafly for P&G sales materials. Call when the rep asks for sell sheets, training materials, videos, presentations, or other content assets. Do NOT call for account briefings or visit logging.'
        category='P&G Sales Companion'
    )
    public static List<Response> search(List<Request> requests) {
        // 1. Validate inputs
        // 2. Get Mediafly token via secure credential flow
        // 3. Call /3/items/search?productId=<configured>&Term=<encoded>&Limit=3&IsAISearch=true
        // 4. Parse top results and link.href values
        // 5. Return a displayable summary
    }
}
```

Keep the real implementation consistent with the current repo's invocable patterns:

- `public with sharing class`
- Inner `Request` and `Response` classes
- `@InvocableMethod` with a planner-friendly description
- `summary`, `isSuccess`, and `errorMessage` outputs
- Friendly error handling and `System.debug()` for internal diagnostics

## Agentforce Wiring

This repo implements the dedicated-subagent option: the former `product_qa` stub has been replaced with a `mediafly_content_search` subagent, and the router's `go_to_mediafly_content` transition sends content/asset requests to it. Keeping content search as its own subagent (rather than overloading a general product-Q&A topic) keeps the behavior deterministic and easy to demo: the subagent's only job is to search Mediafly and return links.

Suggested router rule:

```yaml
Use go_to_mediafly_content when the rep asks for sell sheets, training materials, videos, presentations, leave-behinds, or other content assets.
```

Suggested action target:

```yaml
search_mediafly_content:
    target: "apex://SearchMediaflyContentAction"
    description: "Searches Mediafly for relevant P&G sales materials and returns direct links"
    inputs:
        searchTerm: string
            description: "The asset topic, product, or title the rep asked for"
            is_required: True
        accountId: string
            description: "Optional Salesforce Account ID if already resolved"
        resultLimit: object
            description: "Maximum number of results to return (defaults to 3)"
            complex_data_type_name: "lightning__integerType"
    outputs:
        summary: string
            description: "Short ranked list of Mediafly assets with links"
            is_displayable: True
        results: list[string]
            description: "Structured result summaries"
            complex_data_type_name: "lightning__textType"
        isSuccess: boolean
        errorMessage: string
```

Suggested subagent behavior:

```text
1. Extract the search phrase from the rep's request.
2. Call search_mediafly_content.
3. Return the action summary exactly as provided.
4. If no results are found, ask the rep for a narrower product, topic, or asset name.
5. Do not invent asset titles, claims, or links.
```

## Test Prompts

Use these prompts during live-action preview after the Apex action and credentials are configured:

```text
What materials do I have for Oral-B iO hygienist training?
Pull up the Gingivitis ER sell sheet.
Find assets for Crest Gum Detoxify.
Do we have a video I can share about iO patient outcomes?
Show me the top three whitening leave-behinds.
```

Expected behavior:

- The router sends content requests to the Mediafly content subagent.
- The action receives a concise search term.
- The action returns no more than three to five ranked results.
- Each result includes a direct Mediafly link when available.
- The agent does not summarize document contents unless that content was returned by Mediafly metadata.
- The agent does not claim an asset exists unless it was returned by Mediafly.
- Auth failures produce a friendly retry/admin message.
- No-result searches ask the rep to refine the topic instead of inventing fallback content.

## Level 2 Option: Answering From Inside Assets

Level 1 only finds assets and links the rep back to Mediafly. It does not let Agentforce answer questions from inside PDFs, decks, videos, or training materials.

If P&G wants the agent to answer questions such as "What does the iO sell sheet say about battery life?" or "Summarize the key points from the Gingivitis ER training deck," the content needs to be indexed for retrieval. The clean Salesforce-native path is to ingest approved content into Data Cloud as a vector knowledge base and ground the agent on that indexed content.

That Level 2 design should be treated as a separate workstream because it introduces content ingestion, refresh cadence, access control, content chunking, retrieval quality, and governance decisions. Mediafly can remain the content source of truth, but the searchable text representation must be available to the agent.

## Implementation Checklist

Before building:

- Confirm Mediafly API access with the Mediafly team.
- Confirm the `productId`.
- Confirm service-account permissions.
- Confirm direct-link behavior for reps.
- Decide whether default search uses `GET` query parameters or `POST` `SearchRequest`.
- Decide whether `accountId` should influence search in phase two or remain unused.

During build:

- Configure credentials securely.
- Add `SearchMediaflyContentAction`.
- Add Apex tests with mocked Mediafly responses.
- Add permission-set Apex class access for the action.
- Wire the action into Agent Script.
- Validate with live-action preview.

After build:

- Test happy path, no-results path, auth failure, and Mediafly API failure.
- Confirm links open correctly for an authenticated rep.
- Confirm no Mediafly secrets are present in source control.
