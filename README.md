# POH Sales Agent — Agentforce Pilot

An Agentforce Employee Agent for P&G Professional Oral Health (POH) sales representatives. The agent lives on the Account record page and does two things:

1. **Pre-Call Planning** — generates a complete, grounded account brief in a single AI call before a dental practice visit
2. **Post-Call Logging** — lets reps log a completed visit via natural language (or Siri dictation), parsing the narrative and writing back to Salesforce

---

## Architecture

### Pre-Call Planning — Grounded Prompt Template

The pre-call brief is powered by a **Flex Prompt Template with an Apex data provider**. When the rep says "brief me," the agent makes one call to the `POH_Pre_Call_Brief` prompt template. The template internally runs the `POHPreCallBriefData` Apex class to fetch all account data from Salesforce before the LLM ever generates a word. This means:

- The LLM only synthesizes — it never guesses or fabricates
- The full brief returns in a single conversational turn
- No multi-step back-and-forth between the agent and Apex

```
Rep: "Brief me"
  └─► Agent calls generatePromptResponse://POH_Pre_Call_Brief
        └─► Prompt Template runs POHPreCallBriefData (Apex data provider)
              ├─► POHGetAccountBrief     → practice profile
              ├─► POHGetVisitHistory     → 12-month visit history
              ├─► POHGetOrderHistory     → orders + ship plan
              └─► POHGetSamplingHistory  → iO sample history
        └─► LLM synthesizes one grounded brief
  └─► Rep sees complete brief
```

### Post-Call Logging

The agent accepts a free-form narrative ("Today I visited from 2–2:30, saw Megan and Julie, left 12 tubes of Crest Gum Detoxify, they want a Teach and Learn"), extracts the structured data using slot-filling, confirms with the rep, and then writes back to Salesforce.

---

## Apex Classes

### Data Provider (Prompt Template Grounding)

#### `POHPreCallBriefData`
The **consolidated data provider** for the `POH_Pre_Call_Brief` prompt template. This is the class registered as a `templateDataProvider` inside the Flex template XML. When the template executes, Salesforce calls this class with the `accountId`, it fetches all four data sections by calling the individual fetcher classes below, and returns everything as a single structured string that the LLM uses as grounding context.

- **Input:** `accountId` (Salesforce Account ID)
- **Output:** `Prompt` (structured text block with all four data sections)
- **Called by:** `POH_Pre_Call_Brief` prompt template — not called directly by the agent

---

### Individual Data Fetchers (also usable as standalone agent actions)

Each of these classes is an `@InvocableMethod` — callable both as a direct agent action and from `POHPreCallBriefData`.

#### `POHGetAccountBrief`
Fetches the practice profile from the Account record.
- Returns: practice name, billing address, specialty, DDS count, RDH count, dispensing/recommending status (Power and Manual), competitor brands seen, last iO sample date, and the AI Sales Companion recommendation field

#### `POHGetVisitHistory`
Returns all Events linked to the Account within a configurable lookback window (default 365 days). No row cap — returns every visit.
- Returns: total visit count, most recent visit details (date, duration, attendees pulled from WhoId and EventRelation, notes, samples left), and a summary of all previous visits
- Attendees are resolved by joining both the primary `WhoId` contact and any additional `EventRelation` invitees

#### `POHGetOrderHistory`
Returns all `Order_Item__c` records for the Account covering the past 12 months and any future ship plan orders.
- Returns: past orders grouped by product family and ship plan type with unit totals, ship plan type detection, and a line-by-line list of upcoming ship plan orders
- Flags accounts with no active ship plan as a potential recommendation opportunity

#### `POHGetSamplingHistory`
Returns `Order_Item__c` records where `Ship_Plan_Type__c = 'Sample Drop'` for the past 24 months.
- Returns: chronological list of sample drops by product and quantity, last Oral-B iO sample date, and a staleness flag if the last iO sample was more than 2 years ago (with a recommendation to re-sample)

---

### Post-Call Write Actions

#### `POHFindContactsByName`
Looks up contacts on the Account by first name. Handles duplicates by selecting the most recently modified contact and surfacing both to the rep for confirmation.
- Input: comma-separated first names, Account ID
- Output: resolved Contact IDs, human-readable summary with duplicate warnings

#### `POHLogVisitEvent`
Creates a Salesforce Event for the completed visit. Links contacts via `EventRelation`, populates `Visit_Notes__c` and `Samples_Left_Summary__c`, and sets `Logged_via_Agentforce__c = true`. Requires rep confirmation before executing.
- Input: Account ID, contact IDs, start/end datetime, subject, notes, samples summary
- Output: Event ID, success flag, confirmation message

#### `POHLogSamplesLeft`
Creates `Order_Item__c` records with `Ship_Plan_Type__c = 'Sample Drop'` for each product and quantity mentioned by the rep. Updates `Last_iO_Sample_Date__c` on the Account if an Oral-B iO product was dropped.
- Input: Account ID, natural language samples summary, visit date
- Output: confirmation of what was logged

#### `POHUpdateAccountAttributes`
Updates Account custom fields the rep explicitly observed during the visit: dispensing/recommending status, DDS/RDH counts, competitor brands.
- Input: Account ID + any combination of the 7 optional attribute fields
- Output: summary of what was updated

#### `POHGetAllContacts`
Returns every contact on the Account with no row cap. Used when the rep asks to see who is at a practice before a visit.
- Input: Account ID
- Output: full contact list (name, title, phone, email, last modified date), total count, duplicate first-name flags

---

## Key Metadata

| File | What it is |
|------|-----------|
| `force-app/main/default/genAiPromptTemplates/POH_Pre_Call_Brief.genAiPromptTemplate-meta.xml` | Flex Prompt Template with Apex grounding |
| `force-app/main/default/aiAuthoringBundles/POH_Sales_Agent/POH_Sales_Agent.agent` | Agent Script defining all topics and actions |
| `force-app/main/default/objects/Order_Item__c/` | Custom object representing orders and sample drops |
| `force-app/main/default/objects/Account/fields/` | Custom fields added to Account (specialty, DDS/RDH counts, dispensing flags, etc.) |
| `force-app/main/default/flows/POH_Create_Followup_Task.flow-meta.xml` | Flow action for creating follow-up Tasks |
| `scripts/apex/seed_poh_data.apex` | Seeds the Omega Inc demo account with products, contacts, events, and order items |

---

## Deployment

```bash
# Authenticate to your org
sf org login web --alias my-org --set-default

# Deploy schema and Apex first
sf project deploy start --source-dir force-app/main/default/objects
sf project deploy start --source-dir force-app/main/default/classes

# Deploy the Prompt Template (requires Apex to exist first)
sf project deploy start --source-dir force-app/main/default/genAiPromptTemplates

# Deploy the agent and remaining metadata
sf project deploy start --source-dir force-app/main/default

# Publish and activate the agent
sf agent publish authoring-bundle -n POH_Sales_Agent
sf agent activate -n POH_Sales_Agent --version 1
```
