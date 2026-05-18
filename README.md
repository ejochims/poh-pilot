# P&G Sales Companion — Agentforce Reference Implementation

This repo contains the Apex classes, Prompt Template, and Agent Script source that power a complete **P&G Professional Oral Health (POH) Sales Companion** built on Agentforce. It covers two live flows:

- **Pre-visit briefing** — the rep asks to be briefed on a dental practice before walking in; the agent returns a grounded 6-section narrative with no hallucination risk
- **Post-visit logging** — the rep dictates a paragraph after leaving a practice; the agent resolves the account, logs the Event, links attendees, updates Account intelligence, and creates follow-up Tasks in one conversational turn

A third flow (Product Q&A) is stubbed and ready to wire. For a phase-two content-search option, see `specs/Mediafly-Agent-Action-Walkthrough.md`, which describes how to connect Mediafly's Launchpad API to a separate Agentforce action that returns direct links to sales assets without duplicating content in Salesforce.

---

## What This Is Built On

This implementation uses **Agentforce Agent Script**, the source-code authoring format for Agentforce agents. Rather than configuring agents through the Agent Builder UI, the entire agent — router, subagents, actions, instructions, and variable wiring — lives in a single `.agent` file that deploys through the standard Salesforce CLI metadata pipeline.

The `.agent` file is the authoritative definition of how the agent behaves. The UI reflects what the file contains; the file is the source of truth. This matters for production implementations: it means the agent can be version-controlled, code-reviewed, and deployed the same way everything else is.

The CLI command to publish changes is:

```bash
sf agent publish authoring-bundle --api-name PG_SalesCompanion --target-org <alias>
```

---

## Architecture Overview

The agent uses a **hub-and-spoke** pattern. A stateless router receives every message and transitions to the correct specialist subagent. Each subagent owns its own actions, instructions, and variable state.

```
User message
    │
    ▼
agent_router (start_agent)
    │
    ├──► pre_visit_briefing
    │         │
    │         ├── find_practice (apex://FindAccountAction)
    │         └── get_pre_call_brief (generatePromptResponse://POH_Pre_Call_Brief)
    │
    ├──► post_visit_logger
    │         │
    │         ├── find_account (apex://FindAccountAction)
    │         ├── log_visit (apex://LogOfficeVisitAction)
    │         ├── upsert_contacts (apex://UpsertVisitContactsAction)
    │         ├── update_attributes (apex://UpdateAccountAttributesAction)
    │         ├── create_follow_up (apex://CreateFollowUpTaskAction)
    │         └── link_attendees (apex://LinkVisitAttendeesAction)
    │
    └──► product_qa (stub)
```

**Key architectural points:**

- The router does zero work. It does not answer questions or call actions. It routes and transitions.
- Account resolution happens first in every subagent before any write actions fire.
- The agent manages `accountId`, `eventId`, and `contactIds` as mutable variables in the `.agent` file. Actions set these variables via `set @variables.x = @outputs.y` bindings.
- `link_attendees` is sequenced after both `log_visit` and `upsert_contacts` because it depends on outputs from both. The agent's `available when` guard enforces this.

---

## Part 1: Pre-Visit Briefing

### How it works

The briefing is grounded entirely in live CRM data. The design goal is zero hallucination risk: by the time the LLM writes a single word, every fact about the practice is already present in the prompt as structured plain text.

```
Agent → generatePromptResponse://POH_Pre_Call_Brief
              │
              │  [Before LLM is invoked, Salesforce calls the data provider]
              │
              └─► POHPreCallBriefData (Apex templateDataProvider)
                        │
                        ├─► POHGetAccountBrief     → practice profile, demographics,
                        │                             dispensing/recommending (multi-select),
                        │                             competitor brands, last iO sample date,
                        │                             AI Sales Companion recommendation
                        │
                        ├─► POHGetVisitHistory     → Events past 12 months, attendees
                        │                             from WhoId + EventRelation, visit notes,
                        │                             samples left (count + product)
                        │
                        ├─► POHGetOrderHistory     → Order_Item__c past 12 months + future
                        │                             ship plan orders, grouped by product family
                        │
                        └─► POHGetSamplingHistory  → Sample drops past 24 months,
                                                      last iO sample date, stale flag if > 2 years
                        │
                        └─► Returns one structured plain-text string
              │
              └─► LLM writes a 6-section brief from the grounded data
```

The full call chain is documented in detail in the original `poh-pilot` README sections 1–6. The schema for `POHGetAccountBrief` has been updated in this implementation to match the current multi-select Account field design — see the Data Model section below.

### Account schema changes from the original poh-pilot

The original implementation used boolean (checkbox) fields for dispensing and recommending:

```
Dispenses_Power__c    (Checkbox)
Dispenses_Manual__c   (Checkbox)
Recommends_Power__c   (Checkbox)
Recommends_Manual__c  (Checkbox)
```

This implementation replaces those with multi-select picklists covering the full product range the customer tracks:

```
Office_Dispense_Power__c        (Multi-select: Does Not Dispense; Oral B; Sonicare; Other; Unknown)
Office_Dispense_Manual__c       (Multi-select: Does Not Dispense; Oral B; Colgate; Butler; Other; Unknown)
Office_Dispense_Paste__c        (Multi-select: Does Not Dispense; Crest; Colgate; Sensodyne; Other; Unknown)
Office_Dispense_Whitening__c    (Multi-select: Does Not Dispense; White Strips; Daily Serum; Opalescence; Zoom; Other; Unknown)
Office_Dispense_Waterflosser__c (Multi-select: Does Not Dispense; Oral B; Waterpik; Other; Unknown)
Office_Recommends_Whitening__c  (Multi-select: White Strips; Daily Serum; Opalescence; Zoom; Other; Unknown)
Office_Recommends_Waterflosser__c (Multi-select: Oral B; Waterpik; Other; Unknown)
```

`POHGetAccountBrief.cls` reads these as string fields and formats them into labeled lines. The LLM instructions reference the full list including competitor values (e.g., "Sonicare in the Power slot") as signals for the next-best-action recommendation.

The demographic fields were also renamed:

| poh-pilot | This implementation |
|---|---|
| `Number_of_DDS__c` | `Number_of_Dentists__c` |
| `Number_of_RDH__c` | `Number_of_Hygienists__c` |

Three new demographic fields were added: `Number_of_Ortho_Pedo__c`, `Number_of_Weekly_Patients__c`, and a ship plan group (`Ship_Plan_Status__c`, `Ship_Plan_Product__c`, `Ship_Plan_Cadence__c`).

### Event schema changes from the original poh-pilot

The original `Samples_Left_Summary__c` (free text) has been replaced with two structured fields:

| poh-pilot | This implementation |
|---|---|
| `Samples_Left_Summary__c` (Text) | `Samples_Left_Count__c` (Number) + `Samples_Left_Product__c` (Text) |

`POHGetVisitHistory` reads both: it formats them as `"X units of Product"` for the brief. If `Samples_Left_Count__c` is null, it falls back to the old `Description` field for seeded historical data.

A fourth field, `Prescheduled__c` (Checkbox), was also added to track whether visits were drop-ins or scheduled in advance.

---

## Part 2: Post-Visit Logging

This is the new flow added in this implementation. The rep speaks one paragraph after leaving a dental office. The agent resolves the account, then fires up to five actions to capture everything the rep mentioned — and skips any action for which the rep didn't provide relevant input.

### The hero utterance

> "Just left Smile Dental. Was there from 2 to 2:30. Saw Megan and Kristy. Talked about the iO Series 9 — they're very interested. Left 8 brushes. They want a Teach and Learn for their new hygienist next month."

From this single message, the planner:
1. Resolves "Smile Dental" to a Salesforce Account ID
2. Creates a Face-to-Face Event with the time, notes, and sample count/product
3. Matches "Megan" and "Kristy" to existing Contacts on the Account by first name
4. Creates a follow-up Task: "Schedule Teach and Learn for new hygienist"
5. Links both contacts to the Event as invitees

### Action sequence and conditional firing

```
Turn 1:  find_account          (always — resolve Account ID before anything else)

Turn 2:  log_visit             (always — if a visit occurred)
         upsert_contacts       (conditional — only if names were mentioned)
         update_attributes     (conditional — only if new office info was stated)
         create_follow_up      (conditional — only if a follow-up was explicitly mentioned)

Turn 3:  link_attendees        (sequential — after log_visit AND upsert_contacts)
```

Turns 2 and 3 are enforced by the `available when` guards in the `.agent` file. `link_attendees` is gated on `@variables.eventId != ""`, which is only set after `log_visit` completes.

### Action: `FindAccountAction`

Resolves a dental practice name to its Salesforce Account ID using a `LIKE '%name%'` query.

**Note on `IdentifyRecordByName`:** The standard `standardInvocableAction://IdentifyRecordByName` action is the preferred approach for account resolution and would avoid this custom class entirely. In this implementation, a known org-level issue prevented it from registering during bundle creation, which is why `FindAccountAction` exists as a workaround. In a production org, attempt `IdentifyRecordByName` first; fall back to this class only if the publish step fails during `GenAiFunctionDefinition` creation.

`FindAccountAction` returns `accountId`, `accountName`, `matchCount`, and a `candidateNames` list so the agent can present disambiguation options when multiple accounts match. The agent's instructions handle disambiguation conversationally — no Apex needed for that logic.

### Action: `LogOfficeVisitAction`

Creates an `Event` record on the Account for the visit.

**Required input:** `accountId`

**Optional inputs:** `startDateTime`, `endDateTime`, `eventType` (Face to Face or Teach & Learn), `visitNotes`, `samplesLeftCount`, `samplesLeftProduct`, `prescheduled`

**Defaults when omitted:** `startDateTime = now()`, `endDateTime = start + 20 minutes`, `eventType = Face to Face`

The record is assigned the `Office_Visit` record type at runtime via `Event.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName()`. If the record type is unavailable, the Event is still created without it — the action degrades gracefully rather than failing.

`visitNotes` is written to both `Visit_Notes__c` (the structured custom field) and the standard `Description` field. This ensures briefings that read `Description` as a fallback still pick up post-call notes if the custom field isn't populated.

**Output:** `eventId` (passed to `link_attendees`), `summary`

### Action: `UpsertVisitContactsAction`

Matches attendee first names to existing Contacts on the Account. Creates stub Contact records for anyone new.

**Required input:** `accountId`

**Input:** `attendees` — a `list[string]` of first names exactly as the rep mentioned them (e.g., `["Megan", "Kristy"]`)

**Resolution logic per name:**
1. Query all Contacts where `AccountId = :accountId`
2. Build a case-insensitive first-name map, with real contacts (LastName ≠ "(Unknown)") inserted before any stub contacts so real matches always win on collision
3. For each name: single first-name match → link it; multiple matches → take the first, note it in the summary; zero matches → create a new Contact with `LastName = '(Unknown)'`

**Important platform note on `list[string]` inputs:** When passing a `list[string]` through the `lightning__textType` complex data type in Agent Script, the platform can append pipe (`|`) characters to list items during serialization. The action sanitizes incoming names by stripping all pipe characters before matching: `name.trim().replaceAll('\\|', '').trim()`. This is not documented behavior — add this sanitization to any action that accepts `list[string]` inputs.

**Output:** `contactIds` (passed to `link_attendees`), `resolutionSummary`

### Action: `UpdateAccountAttributesAction`

Updates intelligence fields on the Account. Only non-null inputs produce DML — if the rep didn't mention an attribute, that field is not touched.

**Required input:** `accountId`

**Optional inputs:** All Account intelligence fields (demographics, all 7 multi-select dispense/recommend fields, ship plan fields, competitor brands)

**Multi-select append vs. replace:** The `replaceMulitSelect` boolean (default `false`) controls whether new values are appended to existing multi-select field values or overwrite them. When appending, the action queries the existing field values, merges the incoming values into the set, deduplicates, and sorts before writing. This prevents the common pattern where repeated agent calls accumulate duplicate entries.

**The inclusion/exclusion rule in the action description matters:** The `@InvocableMethod` description explicitly says "Call ONLY when the rep states a CHANGE or NEW data point about the office. Do NOT call when the rep is restating known information or describing what was discussed in a visit." This sharp boundary prevents the planner from calling `update_attributes` for visit narrative content that belongs in `log_visit`.

**Output:** `changedFields` (list of field labels that changed), `summary`

### Action: `CreateFollowUpTaskAction`

Creates a Task on the Account.

**Required inputs:** `accountId`, `subject`

**Optional inputs:** `dueInDays` (default 7), `priority` (default Normal)

The Task is owned by the running user (`OwnerId = UserInfo.getUserId()`), linked to the Account via `WhatId`, and created with `Status = 'Not Started'`.

**Output:** `taskId`, `summary`

### Action: `LinkVisitAttendeesAction`

Creates `EventRelation` records linking the Contact attendees to the visit Event as invitees.

**Required input:** `eventId`

**Input:** `contactIds` — the list of Contact IDs returned by `UpsertVisitContactsAction`

This action is called in a separate sequential step after both `log_visit` and `upsert_contacts` have completed. The `available when @variables.eventId != ""` guard in the `.agent` file enforces this sequence.

If `contactIds` is empty or null (no attendees were mentioned), the action returns a clean no-op success rather than failing. The agent always calls `link_attendees` after a visit — it doesn't need to decide whether to skip it based on whether attendees were mentioned.

**Output:** `count`, `summary`

---

## The Agent Script File

The full agent definition lives at `force-app/main/default/aiAuthoringBundles/PG_SalesCompanion/PG_SalesCompanion.agent`.

### File structure overview

```yaml
system:
    instructions: "..."   # global persona and guardrails
    messages:
        welcome: "..."
        error: "..."

config:
    developer_name: "PG_SalesCompanion"
    agent_type: "AgentforceEmployeeAgent"

variables:                # mutable state passed between actions
    accountId: mutable string = ""
    eventId:   mutable string = ""
    contactIds: mutable list[string] = []

start_agent agent_router:
    reasoning:
        instructions: |   # routing rules, explicit suppression of narration
        actions:
            go_to_briefing: @utils.transition to @subagent.pre_visit_briefing
            go_to_logger:   @utils.transition to @subagent.post_visit_logger

subagent pre_visit_briefing:
    reasoning:
        instructions: |   # step-by-step instructions for the planner
        actions:
            find_practice:    @actions.find_practice
                with accountName = ...
                set @variables.accountId = @outputs.accountId
            get_pre_call_brief: @actions.get_pre_call_brief
                with "Input:accountId" = @variables.accountId
                available when @variables.accountId != ""

    actions:
        find_practice:
            target: "apex://FindAccountAction"
            inputs: ...
            outputs: ...
        get_pre_call_brief:
            target: "generatePromptResponse://POH_Pre_Call_Brief"
            inputs: ...
            outputs: ...

subagent post_visit_logger:
    # same pattern — reasoning block + actions block
```

### Key conventions

**Action targets:**
- `apex://ClassName` — calls an `@InvocableMethod` on the named Apex class
- `generatePromptResponse://TemplateName` — invokes a Prompt Template by API name
- `standardInvocableAction://ActionName` — invokes a standard platform action (e.g., `IdentifyRecordByName`)

**Variable wiring:**
```yaml
set @variables.accountId = @outputs.accountId
```
This binds an action output to an agent-level variable, making it available to subsequent actions in the same subagent.

**Conditional availability:**
```yaml
available when @variables.accountId != ""
```
This guard prevents an action from being offered to the planner until its dependency is satisfied. Without it, the planner may attempt to call `log_visit` before account resolution completes.

**List types:**
Use `list[string]` for string lists. The `complex_data_type_name: "lightning__textType"` annotation is required for any `list[string]` input or output:
```yaml
attendees: list[string]
    description: "..."
    complex_data_type_name: "lightning__textType"
```
Without `complex_data_type_name`, the bundle will fail to publish with a schema validation error.

**Routing narration:** The router's instructions must explicitly say the agent should never announce its routing decision. Without this instruction, the LLM will narrate transitions ("Routing you to the post-visit logger...") rather than transitioning silently.

---

## Data Model Reference

### Custom Object: `Order_Item__c`

| Field | Type | Purpose |
|---|---|---|
| `Account__c` | Lookup(Account) | Links the order to the dental practice |
| `Product__c` | Lookup(Product2) | Optional catalog link |
| `Product_Name__c` | Text 255 | Denormalized product name (preferred for display) |
| `Product_Family__c` | Picklist | Power; Manual; Paste; Floss; Whitening; Waterflosser |
| `Quantity__c` | Number(10,0) | Units ordered |
| `Order_Date__c` | Date | Order or scheduled delivery date |
| `Ship_Plan_Type__c` | Picklist | Manual Ship Plan; Auto Ship Plan; Sample Drop; One-Time |
| `Is_Future_Order__c` | Checkbox | True for upcoming ship plan orders not yet fulfilled |

### Custom Fields on `Account`

**Demographics**

| Field | Type |
|---|---|
| `Practice_Specialty__c` | Picklist (General Practice; Pediatric; Periodontal; Orthodontic; Endodontic; Other) |
| `Number_of_Dentists__c` | Number(3,0) |
| `Number_of_Hygienists__c` | Number(3,0) |
| `Number_of_Ortho_Pedo__c` | Number(3,0) |
| `Number_of_Weekly_Patients__c` | Number(5,0) |

**Office Dispense (multi-select picklists)**

| Field | Values |
|---|---|
| `Office_Dispense_Power__c` | Does Not Dispense; Oral B; Sonicare; Other; Unknown |
| `Office_Dispense_Manual__c` | Does Not Dispense; Oral B; Colgate; Butler; Other; Unknown |
| `Office_Dispense_Paste__c` | Does Not Dispense; Crest; Colgate; Sensodyne; Other; Unknown |
| `Office_Dispense_Whitening__c` | Does Not Dispense; White Strips; Daily Serum; Opalescence; Zoom; Other; Unknown |
| `Office_Dispense_Waterflosser__c` | Does Not Dispense; Oral B; Waterpik; Other; Unknown |

**Office Recommends (multi-select picklists)**

| Field | Values |
|---|---|
| `Office_Recommends_Whitening__c` | White Strips; Daily Serum; Opalescence; Zoom; Other; Unknown |
| `Office_Recommends_Waterflosser__c` | Oral B; Waterpik; Other; Unknown |

**Ship Plan**

| Field | Type |
|---|---|
| `Ship_Plan_Status__c` | Picklist (Not Enrolled; Pending; Active; Cancelled) |
| `Ship_Plan_Product__c` | Text 255 |
| `Ship_Plan_Cadence__c` | Text 80 |

**Briefing fields**

| Field | Type |
|---|---|
| `Competitor_Brands_Seen__c` | Long Text 1000 |
| `Last_iO_Sample_Date__c` | Date |
| `AI_Sales_Companion_Recommendation__c` | Long Text 32768 |

### Custom Fields on `Activity` (Event/Task)

These fields must be deployed against the `Activity` object in the metadata, not `Event` directly. The file path is `force-app/main/default/objects/Activity/fields/`, and the `<fullName>` in each XML file contains only the field name (e.g., `Visit_Notes__c`), not a qualified prefix.

| Field | Type | Purpose |
|---|---|---|
| `Visit_Notes__c` | Long Text 32768 | Full narrative notes from the visit |
| `Samples_Left_Count__c` | Number(5,0) | Units of product left at the office |
| `Samples_Left_Product__c` | Text 255 | Product name of samples left |
| `Prescheduled__c` | Checkbox | True if the visit was scheduled in advance |

**Event Record Type:** `Office_Visit` — assign this record type in `LogOfficeVisitAction`. Create a dedicated page layout (`Event-Office Visit Layout`) and assign it to this record type for each profile in scope. Without the page layout assignment, events open on the default calendar layout which doesn't show the custom fields.

---

## Deployment Order

```
1.  Deploy Account custom fields
2.  Deploy Activity (Event) custom fields
3.  Deploy Order_Item__c custom object and fields
4.  Deploy Event record type (Office_Visit) and page layout
5.  Deploy all Apex classes (pre-call data providers + post-call actions)
6.  Deploy the POH_Pre_Call_Brief Prompt Template
7.  Deploy the PG_Sales_Companion_User permission set
8.  Generate and publish the authoring bundle:
        sf agent publish authoring-bundle --api-name PG_SalesCompanion --target-org <alias>
```

The Prompt Template has a hard compile-time dependency on the Apex data provider. Deploy the Apex before the template.

The permission set must grant:
- Read + Edit FLS on all custom Account, Activity (Event), and Order_Item__c fields
- CRUD on `Order_Item__c`
- Apex class access on all 10 invocable classes and `POHPreCallBriefData`
- Visibility on the published agent (the `GenAiPlugin` and `GenAiPlanner` records created at publish time)

---

## Known Platform Considerations

**Activity field deployment path.** Custom fields for `Event` must be deployed under the `Activity` object path, not `Event` directly. Use `force-app/main/default/objects/Activity/fields/`. Deploying under `Event/fields/` will fail with a restricted picklist error.

**`IdentifyRecordByName` availability.** The standard account resolution action may fail to register during authoring bundle creation in some orgs (the error surfaces during `GenAiFunctionDefinition` creation at publish time). If this happens, `FindAccountAction` is a drop-in replacement. The action description, inputs, and outputs are designed so the agent's reasoning instructions require no changes — just swap the `target`.

**`list[string]` encoding.** When the LLM passes a `list[string]` value through `lightning__textType`, pipe characters may appear appended to list items (e.g., `"Megan||"` instead of `"Megan"`). Sanitize all `list[string]` inputs in Apex before processing: `name.trim().replaceAll('\\|', '').trim()`.

**Multi-select picklist fields in compact layouts.** Multi-select picklist fields cannot be added to compact layouts. The Salesforce platform will return a validation error during deployment if one is included. Compact layout fields must be simple text, number, picklist, date, or checkbox types.

**Event record type + page layout assignment.** Creating a new Event record type requires a corresponding page layout and an explicit assignment of that layout to the record type for each profile in scope. This is done via the `layoutAssignments` block in the profile metadata file:
```xml
<layoutAssignments>
    <layout>Event-Office Visit Layout</layout>
    <recordType>Event.Office_Visit</recordType>
</layoutAssignments>
```
Without this, the record type is active but events open on the default calendar layout.

---

## Adapting to a Different Data Schema

**Pre-call briefing:** Modify `POHGetAccountBrief.cls` (Account field SOQL + output formatting), `POHGetVisitHistory.cls` (Event field SOQL), `POHGetOrderHistory.cls` and `POHGetSamplingHistory.cls` (Order_Item__c SOQL). The orchestrator (`POHPreCallBriefData`) and section structure are stable — only the SOQL queries and field mappings inside each class need to change.

**Post-call logging:** Each action is a single class with its SOQL and DML inline. The `UpdateAccountAttributesAction` is the most likely to need updates — add or remove `@InvocableVariable` fields and corresponding `if (input != null)` blocks to match the actual Account field schema. The `replaceMulitSelect` / `mergeMultiSelect` pattern is reusable as-is for any multi-select picklist field.

**Prompt Template version identifier:** The `versionIdentifier` and `activeVersionIdentifier` fields require a Base64-encoded SHA-256 hash followed by `_1`. When creating or significantly modifying the template:
```bash
python3 -c "import base64, hashlib; h = hashlib.sha256(b'your-unique-string').digest(); print(base64.b64encode(h).decode() + '_1')"
```
Use the template's developer name or any stable unique string as input.
