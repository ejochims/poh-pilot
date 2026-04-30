# POH Sales Companion — Demo Script
**P&G Professional Oral Health | Agentforce Pilot**

---

## Setup Checklist (Before the Demo)

| Step | Action | Status |
|------|--------|--------|
| 1 | Log in as admin@pgaf.demo in the demo org | ☐ |
| 2 | Navigate to **Accounts → Omega, Inc.** | ☐ |
| 3 | Confirm the account shows the POH Account Record Page (POH Practice Profile section visible) | ☐ |
| 4 | Open the **POH Sales Companion** agent panel (bottom-right of the page) | ☐ |
| 5 | Have `specs/POH_Sales_Agent-testSpec.yaml` open for reference | ☐ |

---

## Scene 1 — Pre-Call Brief (5 min)

**Talking point for audience:**
> "Imagine it's Monday morning. You have 8 stops today. You pull up the Omega Inc. account and ask the agent to brief you — just like you'd ask a colleague who knows the account inside out."

---

### Demo Step 1.1 — Open the Brief

**You say (or type into the agent):**
> "Brief me on this account"

**What happens:**
The agent calls four Apex actions in the background (account profile, visit history, order history, sampling history) and composes a narrative brief. Expected response structure:

```
Omega, Inc. is a [specialty] practice located at [address].
They have [N] dentists and [N] hygienists.
...
This office has been visited [N] times in the past 12 months...
...
They are on a [Manual/Auto] Ship Plan consisting of [products]...
...
Last iO sample was [date] — [STALE / within 2 years]...
...
Recommended Next Best Action: [AI Sales Companion recommendation]
```

**Proof points to call out:**
- The brief reads as narrative prose, not a raw data dump
- Visit count pulls ALL events (not capped at 5)
- Order history explicitly says "past 12 months" — no vague "recent"
- iO sample is flagged as stale if > 2 years (addresses customer issue #3)

---

### Demo Step 1.2 — Show All Contacts

**You say:**
> "Show me all contacts at this practice"

**What happens:**
`POHGetAllContacts` queries ALL contacts with no SOQL row cap. The agent displays all contacts with name, title, phone, and flags duplicate first names.

**Proof points:**
- This addresses **Customer Issue #1** (agent was capping at 5 contacts)
- Duplicate names are flagged with `[DUPLICATE FIRST NAME]` label

---

### Demo Step 1.3 — Probe the Brief

**You say:**
> "Do they have any whitespace opportunity for iO?"

**What happens:**
The agent interprets "whitespace" correctly (per POH glossary) and responds with context on iO adoption opportunity — without you ever defining the term.

**Proof points:**
- POH terminology training is working
- Agent never recommends Sonicare or other competitors

---

## Scene 2 — Post-Call Logging (5 min)

**Talking point for audience:**
> "It's now 3pm. You just walked out of Omega's office. You're in the parking lot, and instead of opening a laptop to log your call, you dictate to Siri, which feeds the agent."

---

### Demo Step 2.1 — Dictate the Call Narrative

**You say (simulate voice dictation — speak naturally):**
> "Today I visited Omega from two ten to two thirty PM. I saw Megan and Julie. We discussed how Power dispensing fits into patient instructions. I gave them ideas on how to better integrate Oral-B iO into hygiene conversations. They agreed to trial a Gingivitis system ship plan for one CS every month. I noticed they are also dispensing Colgate and added one hygienist, so now they have four. I left them twelve tubes of Crest Gum Detoxify toothpaste. They would like me to setup a teach and learn for their new hygienist."

**What happens:**
1. `collect_call_details` (`@utils.setVariables`) extracts structured data from the narrative
2. `find_contacts` resolves "Megan" and "Julie" to Contact IDs
3. Agent shows a **confirmation summary** before writing anything

**Expected confirmation summary:**
```
Here's what I'll log:

Visit: Today, 2:10 PM – 2:30 PM
Contacts: Megan [Last Name] (RDH), Julie [Last Name] (DDS)
Notes: [extracted discussion notes]
Samples Left: 12 tubes Crest Gum Detoxify
Follow-Up Task: Teach & Learn for new hygienist

Ready to log this? (yes/no)
```

**Proof points to call out:**
- Agent parsed ALL structured fields from a single voice narrative
- Nothing is written to Salesforce until confirmation
- Duplicate contact handling: if Megan appears twice, agent selects most recently modified and calls it out

---

### Demo Step 2.2 — Handle the Duplicate Contact (if seeded)

If Omega has a second "Megan" contact, the agent will say:
> "I found 2 contacts named Megan. I selected **Megan [Last Name]** (last updated [date]) as the most recently modified. The other is Megan [Other Name] (last updated [older date]). Is this correct?"

**Proof point:** This directly solves the duplicate-contact handling requirement from the use case.

---

### Demo Step 2.3 — Confirm and Log

**You say:**
> "Yes, log it"

**What happens:**
1. `log_visit_event` creates the Event (Logged_via_Agentforce__c = true)
2. `log_samples_left` creates an Order_Item__c with Ship_Plan_Type__c = 'Sample Drop'
3. `create_followup_task` creates a Task: "Teach & Learn for new hygienist" due 14 days out
4. Agent confirms: "Your visit has been logged. Event ID: [ID]. Task created for Teach & Learn, due [date]."

**Proof points:**
- Confirm agent logged correctly: go to Activity Timeline on Omega Inc. and show the new Event
- Show `Logged_via_Agentforce__c = true` on the Event
- Show the Task in the related list

---

### Demo Step 2.4 — Account Attribute Update

**You say:**
> "Update the account — they are now dispensing Colgate Electric, so add that as a competitor brand. And change their RDH count to 4."

**What happens:**
`update_account_attributes` fires with `competitorBrands = "Colgate"` and `numRDH = "4"`. The Account record updates immediately.

**Proof point:** Real-time account attribute updates from a natural language command.

---

## Scene 3 — Guardrail Demonstration (2 min)

**Talking point:**
> "The customer was concerned about the agent recommending competitor products or making things up. Let's test that."

---

### Demo Step 3.1 — No Competitor Recommendation

**You say:**
> "What brushes should I suggest they switch to for better patient outcomes?"

**Expected:** Agent recommends Oral-B iO or other Oral-B products. Never mentions Sonicare or Colgate.

---

### Demo Step 3.2 — No Data Fabrication

**You say:**
> "Can you tell me more about their Q3 2023 orders?"

**Expected:** Agent uses only data from `get_order_history`. If no Q3 2023 data exists, it says so — it never invents numbers.

---

### Demo Step 3.3 — Off-Topic Guardrail

**You say:**
> "Can you help me write a LinkedIn post?"

**Expected:** Agent redirects to POH use cases without engaging with the off-topic request.

---

## Scene 4 — Mobile / Siri Integration Story (1 min, verbal only)

**Talking point (no demo required):**
> "Everything you just saw works on the Salesforce Mobile App. The rep uses Siri for on-device voice dictation — long-pressing the microphone on iOS — and the transcript goes directly into the agent chat. There's no custom STT or TTS integration needed; Siri handles dictation natively and the agent handles the rest."

---

## Wrap-Up Talking Points

| Customer Issue | How POH Sales Companion Solves It |
|---------------|-----------------------------------|
| Contacts capped at 5 | `POHGetAllContacts` Apex uses no row cap — all contacts returned |
| "No recent activities" bug | Explicit `lookbackDays = 365` parameter; NEVER uses vague "recent" |
| Inconsistent OOTB vs. custom topic responses | 100% Agent Script; no OOTB topics mixed in |

| Success Measure | How to Track It |
|-----------------|-----------------|
| Time saved per rep per day | Qualitative survey + compare pre/post time-to-log |
| # Usage by user | `Logged_via_Agentforce__c = true` report on Events + Tasks |
| Accuracy satisfaction | Post-call survey: "Did the agent accurately capture your call?" |
| Increase in sales calls | Territory reporting before/after pilot |

---

## Troubleshooting During Demo

| Symptom | Fix |
|---------|-----|
| Agent says "no account in context" | Ensure you're on the Omega Inc. Account page (not a list view) |
| Agent says "unexpected error" | Check Setup → Agentforce Settings → verify Einstein is enabled |
| Contacts not appearing | Run `scripts/apex/seed_poh_data.apex` to re-seed |
| Action not found during validate | Re-run `sf project deploy start --metadata ApexClass:POH*` |
| AiAuthoringBundle deploy warnings | Use `--ignore-warnings` — warnings are about action discovery, not errors |
