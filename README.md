# POH Pre-Call Brief — Agentforce Prompt Template + Apex

This repo contains the Apex classes and Prompt Template that power the **pre-call planning brief** for the P&G Professional Oral Health (POH) Agentforce pilot. The implementation partner can use this as the reference for building the grounded Prompt Template in the customer's production org.

---

## What This Does

When a sales rep asks the Agentforce agent to brief them on a dental practice account, the agent calls the `POH_Pre_Call_Brief` Prompt Template. The template uses `POHPreCallBriefData` as an **Apex data provider** — meaning Salesforce fetches live account data *before* the LLM generates a single word. The LLM then synthesizes everything into one clean, grounded brief with no hallucination risk.

The full call chain looks like this:

```
Agent calls generatePromptResponse://POH_Pre_Call_Brief
  └─► POH_Pre_Call_Brief (Flex Prompt Template)
        └─► POHPreCallBriefData (Apex data provider — runs inside the template)
              ├─► POHGetAccountBrief     — practice name, address, specialty, DDS/RDH counts,
              │                             dispensing/recommending status, competitor brands,
              │                             last iO sample date, AI Sales Companion recommendation
              ├─► POHGetVisitHistory     — all Events in past 12 months, last visit details,
              │                             attendees, notes, samples left
              ├─► POHGetOrderHistory     — all Order_Item__c records past 12 months + future
              │                             ship plan, grouped by product family
              └─► POHGetSamplingHistory  — sample drops past 24 months, last iO sample date,
                                           staleness flag if > 2 years
        └─► LLM synthesizes one grounded brief using only the fetched data
```

---

## Files

```
apex/
  POHPreCallBriefData.cls       The data provider. Registered in the Prompt Template as a
                                templateDataProvider. Calls the four fetchers below and returns
                                everything as a single structured string.

  POHGetAccountBrief.cls        Fetches the Account record fields — specialty, DDS/RDH counts,
                                dispensing/recommending flags, competitor brands, last iO sample
                                date, and AI Sales Companion recommendation text.

  POHGetVisitHistory.cls        Queries all Events on the Account within a lookback window
                                (default 365 days). Resolves attendee names from both the primary
                                WhoId contact and EventRelation invitees. No row cap.

  POHGetOrderHistory.cls        Queries all Order_Item__c records on the Account for the past
                                12 months and any future ship plan orders. Groups totals by
                                product family and ship plan type.

  POHGetSamplingHistory.cls     Queries Order_Item__c records where Ship_Plan_Type__c =
                                'Sample Drop' for the past 24 months. Flags the last Oral-B iO
                                sample date and marks it stale if over 2 years ago.

prompt-template/
  POH_Pre_Call_Brief.genAiPromptTemplate-meta.xml
                                The Flex Prompt Template metadata. Takes accountId as input,
                                calls POHPreCallBriefData via templateDataProviders, and
                                instructs the LLM to write a structured pre-call brief using
                                only the grounded data.
```

---

## Key Implementation Notes for the Partner

### 1. Custom Object Dependency

`POHGetOrderHistory` and `POHGetSamplingHistory` query a custom object called `Order_Item__c`. You will need to create this object (or map to whatever equivalent exists in the customer's org) with these fields:

| Field | Type | Notes |
|-------|------|-------|
| `Account__c` | Lookup(Account) | Links the order to the account |
| `Product__c` | Lookup(Product2) | The product ordered |
| `Product_Name__c` | Text | Denormalized product name for display |
| `Product_Family__c` | Text | Product family (e.g., Power, Manual, Paste) |
| `Quantity__c` | Number | Units ordered |
| `Order_Date__c` | Date | Date of the order or ship plan delivery |
| `Ship_Plan_Type__c` | Picklist | Manual Ship Plan, Auto Ship Plan, Sample Drop, One-Time |
| `Is_Future_Order__c` | Checkbox | True for upcoming ship plan orders |

If the customer already tracks orders differently, update the SOQL in `POHGetOrderHistory.cls` and `POHGetSamplingHistory.cls` to match their schema.

### 2. Account Custom Fields

`POHGetAccountBrief` reads several custom fields on Account:

| Field | Type |
|-------|------|
| `Practice_Specialty__c` | Text |
| `Number_of_DDS__c` | Number |
| `Number_of_RDH__c` | Number |
| `Dispenses_Power__c` | Checkbox |
| `Dispenses_Manual__c` | Checkbox |
| `Recommends_Power__c` | Checkbox |
| `Recommends_Manual__c` | Checkbox |
| `Competitor_Brands_Seen__c` | Text |
| `Last_iO_Sample_Date__c` | Date |
| `AI_Sales_Companion_Recommendation__c` | Long Text |

Update the field API names in `POHGetAccountBrief.cls` if the customer uses different names.

### 3. Deployment Order

The Prompt Template has a hard dependency on the Apex data provider class. Always deploy in this order:

```
1. Deploy all Apex classes
2. Deploy the Prompt Template
3. Wire the Prompt Template as an action in your agent
```

### 4. Wiring the Prompt Template as an Agent Action

In your agent's pre-call topic, define the action like this:

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

The `Input:accountId` naming convention is required — Prompt Template inputs are always referenced as `Input:<fieldApiName>` in Agent Script.

### 5. Prompt Template Version Identifier

The `versionIdentifier` and `activeVersionIdentifier` in the XML must be a Base64-encoded SHA-256 hash followed by `_1`. If you redeploy or modify the template, generate a new one:

```bash
python3 -c "import base64, hashlib; h = hashlib.sha256(b'your-unique-string').digest(); print(base64.b64encode(h).decode() + '_1')"
```
