# POH Pre-Call Brief — Agentforce Prompt Template + Apex

This repo contains the Apex classes and Prompt Template that power the **pre-call planning brief** for the P&G Professional Oral Health (POH) Agentforce pilot. The implementation partner can use this as the reference for building the grounded Prompt Template in the customer's production org.

---

## Architecture Overview

The core design goal was a single, grounded AI response with no hallucination risk. The way Agentforce works by default, if you ask it to "brief me on an account," it will try to figure out what to do, call actions one at a time, and synthesize across multiple back-and-forth LLM turns. That creates opportunities for the model to make things up between steps.

The solution here flips that model. Instead of the agent gathering data and then asking the LLM to summarize it, the **Prompt Template itself fetches all the data first** using an Apex class registered as a `templateDataProvider`. By the time the LLM sees any text, every field, every visit, every order line is already sitting in the prompt as structured plain text. The LLM's only job is to write prose from that grounded data — it cannot invent numbers or dates because the actual data is already there.

The full call chain:

```
Agentforce agent
  └─► generatePromptResponse://POH_Pre_Call_Brief
        │
        │  [Before LLM sees anything, Salesforce calls the data provider]
        │
        └─► POHPreCallBriefData (Apex — runs inside the template as a data provider)
              │
              ├─► POHGetAccountBrief     → practice name, address, specialty, DDS/RDH counts,
              │                            dispensing/recommending status, competitor brands,
              │                            last iO sample date, AI Sales Companion recommendation
              │
              ├─► POHGetVisitHistory     → all Events on the Account in the past 12 months,
              │                            attendees resolved from WhoId + EventRelation,
              │                            visit notes, samples left summary
              │
              ├─► POHGetOrderHistory     → all Order_Item__c records past 12 months + future
              │                            ship plan orders, grouped by product family,
              │                            ship plan type detection
              │
              └─► POHGetSamplingHistory  → sample drops past 24 months, last Oral-B iO
                                           sample date, stale flag if > 2 years
              │
              └─► Returns one big structured plain-text string
        │
        │  [That string is injected into the prompt at {!$Apex:POHPreCallBriefData.Prompt}]
        │
        └─► LLM synthesizes a complete 6-section brief using only the grounded data
```

---

## How the Code Works — A Full Walkthrough

### 1. The Prompt Template (`POH_Pre_Call_Brief.genAiPromptTemplate-meta.xml`)

The template is the entry point. When the agent calls `generatePromptResponse://POH_Pre_Call_Brief`, Salesforce does three things in order:

**Step 1 — Resolve the input.** The template declares one input, `accountId` (referenced as `Input:accountId`). The agent passes the Salesforce Account ID here.

**Step 2 — Run the data provider.** Before the LLM is invoked at all, Salesforce calls the Apex class registered under `templateDataProviders`. That registration looks like this in the XML:

```xml
<templateDataProviders>
    <definition>apex://POHPreCallBriefData</definition>
    <parameters>
        <parameterName>accountId</parameterName>
        <valueExpression>{!$Input:accountId}</valueExpression>
    </parameters>
    <referenceName>Apex:POHPreCallBriefData</referenceName>
</templateDataProviders>
```

This tells Salesforce: run `POHPreCallBriefData`, pass it the `accountId` from the template input, and make the result available as `Apex:POHPreCallBriefData`.

**Step 3 — Inject and generate.** The template content contains this merge field:

```
{!$Apex:POHPreCallBriefData.Prompt}
```

That resolves to the `Prompt` output variable from `POHPreCallBriefData`. The entire structured data string gets embedded into the prompt text, and the LLM is invoked exactly once on the fully grounded prompt.

The template also contains explicit LLM instructions — what sections to write, what order, and a hard rule not to fabricate anything not present in the grounded data. That instruction is what prevents hallucination.

---

### 2. `POHPreCallBriefData.cls` — The Data Provider (the orchestrator)

This is the class that the Prompt Template calls. Its job is to coordinate all four data fetchers and combine their output into a single structured string.

**Why a separate orchestrator class?**
A `templateDataProvider` can only be one Apex class and can only return one output variable. Rather than trying to register four separate data providers and stitch them together in the template, this class acts as a single facade — it calls all four fetchers internally, then assembles the results into one clean block of text.

**The Request/Response pattern:**
Every Apex class in this set follows the same pattern. It declares inner `Request` and `Response` classes using `@InvocableVariable`, and an `@InvocableMethod` that takes `List<Request>` and returns `List<Response>`. This is required for both direct agent actions and for data providers. The list-in, list-out signature is a Salesforce platform requirement — even when you only ever call it with one item.

```apex
public class Request {
    @InvocableVariable(required=true)
    public String accountId;
}

public class Response {
    @InvocableVariable
    public String Prompt;   // This is what {!$Apex:POHPreCallBriefData.Prompt} resolves to
}
```

The `Prompt` field name on `Response` matters — it must match the field name referenced in the merge field in the template content.

**The `getBriefData` method:**
This is the `@InvocableMethod` the platform calls. It loops through requests (in practice, always one), delegates to `buildAllData`, and packages the result.

**The `buildAllData` method — the heart of the orchestrator:**

```apex
private static String buildAllData(String accountId) {
    // 1. Create a Request for POHGetAccountBrief and call it
    POHGetAccountBrief.Request briefReq = new POHGetAccountBrief.Request();
    briefReq.accountId = accountId;
    List<POHGetAccountBrief.Response> briefResults = POHGetAccountBrief.getAccountBrief(
        new List<POHGetAccountBrief.Request>{ briefReq }
    );

    // 2. Same pattern for visit history, order history, sampling history
    // ...

    // 3. Stitch all four outputs into labeled sections
    List<String> sections = new List<String>{
        'ACCOUNT: ' + accountName + ' (ID: ' + accountId + ')',
        '',
        '=== PRACTICE PROFILE ===',
        accountData,
        '',
        '=== VISIT HISTORY — PAST 12 MONTHS ===',
        visitData,
        // ...
    };

    return String.join(sections, '\n');
}
```

Each sub-class is called directly as a normal Apex static method — not via the Flow/agent invocable path. This is intentional: it avoids the overhead of the invocable framework for internal calls and keeps everything in a single synchronous transaction. The sub-classes are still decorated with `@InvocableMethod` so they can also be used as standalone agent actions if needed, but `POHPreCallBriefData` bypasses that and calls them directly.

The output of `buildAllData` is a plain text block with labeled section headers. Those headers (`=== PRACTICE PROFILE ===`, `=== VISIT HISTORY ===`, etc.) are what the LLM's instructions reference when it's told to write "Section 2: Visit Summary."

---

### 3. `POHGetAccountBrief.cls` — Practice Profile Fetcher

This class queries the `Account` object and formats the core practice attributes into labeled lines.

**The SOQL query:**

```apex
SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode,
       Phone, Website,
       Practice_Specialty__c,
       Number_of_DDS__c, Number_of_RDH__c,
       Dispenses_Power__c, Dispenses_Manual__c,
       Recommends_Power__c, Recommends_Manual__c,
       Competitor_Brands_Seen__c,
       Last_iO_Sample_Date__c,
       AI_Sales_Companion_Recommendation__c
FROM Account
WHERE Id IN :accountIds
```

The method collects all incoming `accountId` values into a `Set<Id>` first, then runs a single query for all of them at once. This is intentional: `@InvocableMethod` is designed to be bulkified, meaning Salesforce may batch multiple records through the same call. By querying once with `WHERE Id IN :accountIds`, the class handles bulk execution correctly and avoids SOQL-in-a-loop issues.

**Address formatting:**
The billing address parts are conditionally built. Each field is only added if it's not blank, then joined with commas. This avoids output like `Address: , Loveland, , 45140` when partial address data exists.

**Dispensing/recommending — the helper method:**
Power and Manual dispensing/recommending each come from separate boolean fields. Rather than repeating the same conditional logic four times, a private helper `buildDispenseRecommendLine(Boolean power, Boolean manual)` handles both cases:

```apex
private static String buildDispenseRecommendLine(Boolean power, Boolean manual) {
    List<String> items = new List<String>();
    if (power == true)  items.add('Oral-B Power');
    if (manual == true) items.add('Oral-B Manual');
    return items.isEmpty() ? 'Neither Power nor Manual' : String.join(items, ', ');
}
```

The explicit `== true` check is important in Apex — checkbox fields can be `null` on unconfigured records, and `null == true` evaluates to `false`, so this is safe. But checking `if (power)` when `power` is `null` would throw an exception in some contexts.

**Output:**
A newline-joined block like:
```
Address: 8974 Columbia Rd, Loveland, OH, 45140
Specialty: General Practice
Dentists (DDS): 2
Hygienists (RDH): 3
Dispenses: Oral-B Power, Oral-B Manual
Recommends: Oral-B Power
Competitor Brands Seen: Sonicare
Last iO Sample Date: 2/23/2022
AI Sales Companion Recommendation: Focus on iO conversion...
```

---

### 4. `POHGetVisitHistory.cls` — Visit History Fetcher

This is the most complex of the four fetchers because attendee resolution requires two separate queries.

**The main Event query:**

```apex
SELECT Id, Subject, StartDateTime, EndDateTime, Description,
       Visit_Notes__c, Samples_Left_Summary__c, WhoId
FROM Event
WHERE WhatId = :accountId
AND StartDateTime >= :cutoffDT
ORDER BY StartDateTime DESC
```

`WhatId` links the Event to the Account. `WhoId` is the "primary contact" — the one contact directly entered on the event record. But a sales rep typically sees multiple people at a visit. Those additional attendees are not on the Event record itself; they're in a separate object called `EventRelation`.

**The EventRelation query — resolving all attendees:**

```apex
List<EventRelation> relations = [
    SELECT EventId, RelationId
    FROM EventRelation
    WHERE EventId IN :eventIds
    AND IsInvitee = true
    AND RelationId != null
];
```

`EventRelation` is a junction object between Events and Contacts/Leads. `IsInvitee = true` filters to the added attendees (as opposed to the event owner or other non-invitee relations). The result is built into a `Map<Id, List<Id>>` — event ID to a list of additional contact IDs — so that when formatting the most recent visit, the code can look up all attendees by event.

All contact IDs (from both `WhoId` and `EventRelation`) are accumulated in a single `Set<Id>` and resolved with one Contact query. Contact names are then formatted as `First Last (Title)` where a title exists.

**Output structure:**
The most recent visit gets a detailed block — date, duration, full attendee list with titles, notes from `Visit_Notes__c` (falling back to the standard `Description` field if the custom field is blank), and samples left. Every prior visit gets a compact single line with date and a truncated note excerpt.

```
Total visits in window: 4
Lookback window: past 365 days (since 4/30/2025)

MOST RECENT VISIT:
  Date: 3/3/2026 2:10 PM
  Duration: 3/3/2026 2:10 PM to 3/3/2026 2:30 PM (20 min)
  Attendees: Megan Smith (RDH), Kristy Jones, Julie Brown (DDS)
  Notes: Discussed power dispensing and iO integration into hygiene instructions.
  Samples left: 12 tubes Crest Gum Detoxify

PREVIOUS VISITS (3):
  - 12/15/2025: Reviewed ship plan renewal and whitespace promo.
  - 9/4/2025: iO demo with new hygienist.
  - 6/18/2025: Routine check-in, no notes recorded.
```

**The `lookbackDays` parameter:**
`POHPreCallBriefData` passes `lookbackDays = 365` when calling this class. The parameter exists so the class can be reused for other windows (e.g., a 90-day "recent activity" call) without modifying the code.

---

### 5. `POHGetOrderHistory.cls` — Order and Ship Plan History Fetcher

This class queries the custom `Order_Item__c` object and produces two sections: a grouped summary of the past 12 months of orders, and a line-by-line list of upcoming ship plan orders.

**The query window:**

```apex
Date pastCutoff   = Date.today().addDays(-365);
Date futureCutoff = Date.today().addDays(365);

SELECT ... FROM Order_Item__c
WHERE Account__c = :accountId
AND Order_Date__c >= :pastCutoff
AND Order_Date__c <= :futureCutoff
```

Both past and future records are pulled in a single query. They're split after retrieval using `Is_Future_Order__c` — a checkbox on the object that marks planned ship plan deliveries that haven't happened yet.

**Grouping past orders by product family and ship plan type:**
Rather than listing every individual order line (which could be dozens), past orders are aggregated into a nested map:

```
Map<String, Map<String, Decimal>>
     │               │         └─ total quantity
     │               └─ ship plan type (e.g., "Manual Ship Plan")
     └─ product family (e.g., "Power", "Manual", "Paste")
```

This produces output like:
```
  Power | Manual Ship Plan: 3744 units
  Paste | One-Time: 48 units
  Floss | Manual Ship Plan: 240 units
```

**Ship plan detection:**
After grouping, the code does a separate pass to check whether any past order has `Ship_Plan_Type__c` of `'Manual Ship Plan'` or `'Auto Ship Plan'`. If found, it surfaces the plan type. If not found, it flags that no active ship plan was detected — which is information the LLM is instructed to call out as a recommendation opportunity.

**Future orders:**
Each future order item is listed individually with date, product name, quantity, and plan type. The product name resolution prioritizes `Product_Name__c` (the denormalized text field) over the lookup to `Product2.Name` — this handles cases where the product name was entered as free text and isn't linked to a catalog record.

---

### 6. `POHGetSamplingHistory.cls` — Sampling History Fetcher

This class queries the same `Order_Item__c` object as the order history fetcher, but filters to records where `Ship_Plan_Type__c = 'Sample Drop'` within the past 24 months. The longer lookback window (730 days vs 365 days for orders) reflects the customer's specific business rule: an Oral-B iO sample drop is considered stale if it hasn't happened within two years.

**The iO stale detection logic:**

```apex
Date lastIODate = null;

for (Order_Item__c s : samples) {
    // Track the most recent Power-family sample drop
    if (family == 'Power' && s.Order_Date__c != null) {
        if (lastIODate == null || s.Order_Date__c > lastIODate) {
            lastIODate = s.Order_Date__c;
        }
    }
}

// After the loop, evaluate staleness
Integer daysSince = lastIODate.daysBetween(Date.today());
Boolean isStale = daysSince > 730;
```

The `Power` family is used as the proxy for Oral-B iO samples because iO is the Power flagship product. If the last Power-family sample drop was more than 730 days ago, a warning is included in the output:

```
WARNING — iO sample is STALE (over 2 years ago). Recommend re-sampling any hygienists
hired since then or reps whose iO battery may no longer hold charge.
```

This warning is then picked up by the LLM in Section 4 of the brief, which is instructed to explicitly flag stale iO sampling opportunities and suggest targeting new hygienists or those with aging battery life.

If no Power-family sample drop exists at all in the 24-month window, the output says the iO has not been sampled in the recorded window — also surfaced as a flag.

---

## Data Model Reference

### Custom Object: `Order_Item__c`

This object represents individual product line items for both historical orders and future ship plan deliveries.

| Field | Type | Purpose |
|-------|------|---------|
| `Account__c` | Lookup(Account) | Links the order to the dental practice |
| `Product__c` | Lookup(Product2) | Optional link to the product catalog |
| `Product_Name__c` | Text | Denormalized product name for display (preferred over the lookup) |
| `Product_Family__c` | Text | Product family: Power, Manual, Paste, Floss, etc. |
| `Quantity__c` | Number | Units ordered or planned |
| `Order_Date__c` | Date | Date of the order or scheduled ship plan delivery |
| `Ship_Plan_Type__c` | Picklist | Manual Ship Plan, Auto Ship Plan, Sample Drop, One-Time |
| `Is_Future_Order__c` | Checkbox | True for upcoming ship plan orders not yet fulfilled |

### Custom Fields on `Account`

| Field | Type | Purpose |
|-------|------|---------|
| `Practice_Specialty__c` | Text | GP, Pediatric, Periodontal, etc. |
| `Number_of_DDS__c` | Number | Count of dentists at the practice |
| `Number_of_RDH__c` | Number | Count of hygienists at the practice |
| `Dispenses_Power__c` | Checkbox | Practice sells Oral-B Power brushes to patients |
| `Dispenses_Manual__c` | Checkbox | Practice sells Oral-B Manual brushes to patients |
| `Recommends_Power__c` | Checkbox | Practice recommends Oral-B Power to patients |
| `Recommends_Manual__c` | Checkbox | Practice recommends Oral-B Manual to patients |
| `Competitor_Brands_Seen__c` | Text | Competitor brands observed in the office (e.g., Sonicare) |
| `Last_iO_Sample_Date__c` | Date | Date of the most recent Oral-B iO sample drop |
| `AI_Sales_Companion_Recommendation__c` | Long Text | Pre-populated AI-generated recommendation field |

### Custom Fields on `Activity` (Event/Task)

| Field | Type | Purpose |
|-------|------|---------|
| `Visit_Notes__c` | Long Text | Detailed notes from the sales call |
| `Samples_Left_Summary__c` | Text | Free-text description of samples left (e.g., "12 tubes Crest Gum Detoxify") |

---

## Implementation Notes for the Partner

### Deployment Order

The Prompt Template has a hard dependency on the Apex data provider. Always deploy in this sequence:

```
1. Create the Order_Item__c object and all custom fields
2. Deploy all five Apex classes
3. Deploy the Prompt Template
4. Wire the Prompt Template as an action in your agent topic
```

### Wiring the Prompt Template as an Agent Action

In your agent's pre-call topic, define the action using this exact syntax:

```
actions:
    get_pre_call_brief:
        description: "Generates a complete pre-call account brief. Call this when the rep
                       asks to be briefed, prepped, or wants an account summary."
        inputs:
            "Input:accountId": string
                description: "Salesforce Account ID of the target practice"
                is_required: True
        outputs:
            promptResponse: string
                is_used_by_planner: True
                is_displayable: True
        target: "generatePromptResponse://POH_Pre_Call_Brief"
```

The `Input:accountId` naming convention is required — Prompt Template inputs are always referenced as `Input:<fieldApiName>` in Agent Script. The `promptResponse` output variable is what Agentforce surfaces to the user.

### Adapting to a Different Data Schema

If the customer tracks orders differently than the `Order_Item__c` model above, the two classes that need updating are `POHGetOrderHistory.cls` and `POHGetSamplingHistory.cls`. The SOQL queries and field references in `buildSummary()` in both classes are the only things that need to change — the output string format, the section headers, and the rest of the orchestration in `POHPreCallBriefData` can stay as-is.

For account custom fields, update the SOQL in `POHGetAccountBrief.cls` and the corresponding output lines in the same class.

### Prompt Template Version Identifier

The `versionIdentifier` and `activeVersionIdentifier` fields in the XML must use a specific Base64-encoded SHA-256 hash format followed by `_1`. If you recreate or modify the template and need to generate a new identifier:

```bash
python3 -c "import base64, hashlib; h = hashlib.sha256(b'your-unique-string').digest(); print(base64.b64encode(h).decode() + '_1')"
```

Use any unique string as the input — the developer name of the template is a good choice.
