# Handoff — For the Accenture Team

This repo is a **reference kit** for the P&G Professional Oral Health Agentforce build, including a Level 1 **Mediafly content search** you can adapt into your own org. It is not a deployable SFDX package — copy the pieces you need.

## Start here

1. **`specs/Mediafly-Setup-Guide.md`** — the step-by-step runbook. Begin at **Phase 1**; it lists exactly what to request from Mediafly. **Do not skip Phase 3c** (External Credential Principal Access) — it is the most common reason callouts fail.
2. **`specs/Mediafly-Agent-Action-Walkthrough.md`** — the design rationale, API details, and the authentication decision (single service-account identity, and why).
3. **`README.md`** — overview of the whole agent (pre-visit briefing, post-visit logging, and the Mediafly content search).

## What the Mediafly integration does (and does not)

- **Does:** a rep asks for sales materials and the agent searches Mediafly's Launchpad API and returns direct links to matching assets. Mediafly stays the source of truth — no content is duplicated into Salesforce.
- **Does not:** answer questions from inside a PDF, deck, or video. Mediafly's search API returns asset metadata and links only, not document text.

## What only P&G / Mediafly can unblock (the real critical path)

The Salesforce side is reference-complete. Nothing runs until these are confirmed with Mediafly:

1. **API access** for a dedicated Mediafly **service account** (not a rep login).
2. The **`productId`**, **Company Code**, and the confirmed **token endpoint path + token field name** (the two `TODO`s in `MediaflyAuthService.cls`).
3. **Direct-link behavior** — whether reps must be signed into Mediafly for asset links to open.
4. **Least-privilege scoping** of the service account (all rep searches run under this one identity, so it should only see content appropriate for the pilot).

Chase these in parallel with the build. The setup guide's Phase 1 is written to gather exactly these values.
