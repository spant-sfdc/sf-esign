# SF-eSign Demo Script
## Nonprofit Grant Agreement — Electronic Signature Workflow

> **Format:** Silent screen recording with AI voiceover  
> **Runtime:** 5–7 minutes  
> **Scenario:** TechPulse Solutions processing a $75,000 grant agreement with Elevate Foundation  
> **Org:** Demo org with pre-configured data (see Pre-Demo Checklist)

---

## Pre-Demo Checklist

Before recording, verify the following in the demo org:

**Data:**
- [ ] Account: **Elevate Foundation** (`DON-2026-0041`, Donor Type: Foundation)
- [ ] Contact: **Marcus Williams** (linked to Elevate Foundation)
- [ ] Opportunity: **Elevate Foundation – 2026 Community Grant** ($75,000, Stage: Proposal/Price Quote)
- [ ] 3 Opportunity Line Items: Community Education Grant ($25K), Youth Outreach Program Support ($18K), Workforce Development & Training ($32K)
- [ ] Signed Signature Request **SR-0045** (Status: Signed, signed PDF attached)
- [ ] Pending Signature Request **SR-0046** (Status: Pending, invitation email sent)

**Configuration:**
- [ ] Branded sender `TechPulse Solutions <spant@techpulse.solutions>` OWA verified
- [ ] Custom label `ESign_Org_Display_Name` = `TechPulse Solutions`
- [ ] Custom label `ESign_Site_Base_URL` correct
- [ ] Signing URL for SR-0046 working (test in incognito browser)
- [ ] `pdfLib` and `html2canvas` static resources deployed (not placeholders)
- [ ] `eSignSignedPdfGenerator` LWC present on SR record page

**Browser:**
- [ ] Clean browser window, zoom at 100%, dark mode off
- [ ] Incognito window ready for the signer perspective
- [ ] No browser notifications or alerts

---

## Scene 1 — Introduction (0:00–0:30)

**Screen:** Salesforce home or org dashboard

**Narration:**
> "Managing grant agreements typically means chasing email threads, tracking down wet signatures, and filing paper documents. Today we're going to show you how SF-eSign eliminates all of that — a fully native Salesforce electronic signature platform that works entirely inside your CRM."

**Actions:** None — static overview shot of the Salesforce home.

---

## Scene 2 — The Grant Opportunity (0:30–1:15)

**Screen:** Opportunity record — *Elevate Foundation – 2026 Community Grant*

**Narration:**
> "Here's the grant opportunity we're working with — a $75,000 community development grant for Elevate Foundation. The opportunity is fully built out with line items — three program areas: Community Education, Youth Outreach, and Workforce Development."

**Actions:**
1. Navigate to the Opportunity record (`006dN00000DGGXZQA5`)
2. Scroll to show the Related Lists — highlight the Opportunity Products section showing all 3 line items with amounts
3. Scroll to show the Files section — highlight the original grant agreement PDF

**Narration:**
> "Our DocGen module generated this grant agreement document directly from the opportunity data — fully merged with the donor's information, program details, and financial summary. Now we need the executive director at Elevate Foundation to sign it."

---

## Scene 3 — Sending the Signature Request (1:15–2:30)

**Screen:** Opportunity record → eSignLauncher component

**Narration:**
> "We'll send the document for signature directly from this Opportunity record using the eSign Launcher."

**Actions:**
1. Scroll to the **eSignLauncher** component on the Opportunity page
2. Click **Send for Signature**
3. Fill in the form:
   - **Recipient Name:** Marcus Williams
   - **Recipient Email:** `shashankpant16@gmail.com` *(pre-filled)*
   - **Document:** select the grant agreement PDF
   - **Expiry Date:** 14 days from today
   - **Message:** *"Dear Marcus, please review and sign the attached 2026 Community Grant Agreement at your earliest convenience. Thank you."*
4. Click **Send**
5. Observe the success toast and the new Signature Request record opening

**Narration:**
> "The system creates a Signature Request record, generates a unique one-time signing token, and immediately sends a branded invitation email. The request is now in Pending status."

**Pause:** 2 seconds on the SR record showing Status = Pending.

---

## Scene 4 — The Invitation Email (2:30–3:15)

**Screen:** Email inbox (switch to email client or show screenshot)

**Narration:**
> "Marcus receives this email moments later — branded with the TechPulse Solutions sender identity and a clear one-click action button."

**Actions:**
1. Open email client (or show SR-0046's invitation email in inbox)
2. Highlight:
   - Branded sender: `TechPulse Solutions <spant@techpulse.solutions>`
   - Subject: `Action Required: Please sign your document — Elevate Foundation – 2026 Community Grant`
   - The **Review & Sign Document** button
   - The message from the sender
   - The expiry notice
3. Hover over the signing button to show the URL

**Narration:**
> "The link is secure, one-time, and expires automatically. Clicking it opens the signing experience — no app install, no Salesforce account needed."

---

## Scene 5 — Signer Experience (3:15–4:30)

**Screen:** Incognito browser → signing page

**Narration:**
> "This is what Marcus sees when he opens the link. The original grant agreement loads as a PDF preview, and the signing interface is clean and intuitive."

**Actions:**
1. Open incognito browser
2. Navigate to the SR-0046 signing URL
3. Show the document loading (PDF preview)
4. Click on **Sign** tab
5. Draw a signature in the signature pad
6. Click **Sign Document**
7. Show the confirmation screen

**Narration:**
> "Marcus applies his signature using the draw interface — or he could type or upload an image instead. One click submits the signature securely to Salesforce."

**Pause:** 2 seconds on the confirmation screen.

**Narration:**
> "The status updates in real time. The system now generates the signed PDF entirely client-side — no server rendering required — and sends the confirmation email automatically."

---

## Scene 6 — Back in Salesforce (4:30–5:30)

**Screen:** Switch back to the Salesforce SR record (SR-0045 — pre-signed for clean demo)

**Narration:**
> "Back in Salesforce, the Signature Request record tells the full story."

**Actions:**
1. Navigate to SR-0045 (the pre-signed record for clean demo display)
2. Point out:
   - **Status:** Signed
   - **Signed Date/Time:** timestamp
   - **Signer Email:** the confirmed email
   - **Signature Type:** Draw
   - **Signing IP:** recorded IP
   - **PDF Generation Status:** Complete
   - **Confirmation Email Status:** Sent
3. Scroll to the **Audit Timeline** component
4. Expand the timeline to show: Email Sent → Viewed → Signed → Confirmation Sent events
5. Scroll to **Files** — show the signed PDF attachment

**Narration:**
> "Every action is timestamped and logged in the audit trail — who opened it, when they signed, from which IP address. This creates a complete, defensible record of the signing event."

---

## Scene 7 — The Signed PDF (5:30–6:15)

**Screen:** Open the signed PDF from Files

**Narration:**
> "Let's open the signed document."

**Actions:**
1. Click on the signed PDF in the Files section
2. Show the document pages
3. Scroll to the last page — the **Signature Certificate**
4. Highlight:
   - Document name and reference
   - Signer name and email
   - Signing timestamp (UTC)
   - IP address
   - Signature image
   - Tamper-evidence statement

**Narration:**
> "The last page is the Signature Certificate — automatically generated by SF-eSign and appended to the original document. It captures every verifiable detail of the signing event."

---

## Scene 8 — Confirmation Email (6:15–6:45)

**Screen:** Email client — signer's inbox

**Narration:**
> "Marcus also receives a confirmation email with the signed PDF attached — his copy for his own records."

**Actions:**
1. Show the confirmation email in the inbox
2. Highlight:
   - Branded sender
   - Subject: `Document Signed Successfully`
   - Document name and timestamp in the email body
3. Open the attached PDF to show it's the complete signed document

---

## Scene 9 — Outro (6:45–7:00)

**Screen:** Return to Salesforce — Opportunity record or SF-eSign app home

**Narration:**
> "SF-eSign gives your team a complete, auditable, Salesforce-native signature workflow — from invitation to signed PDF — without leaving your CRM or relying on third-party vendors. Built for nonprofits. Ready for enterprise."

**Actions:** None — slow zoom out or fade to org home.

---

## Backup Notes

- If SR-0046 signing URL is expired, use SR-0045 as reference and narrate around live signing
- If PDF generation takes more than a few seconds during live recording, cut to the pre-signed SR-0045 to show the completed result
- The `eSignSignedPdfGenerator` LWC on the record page shows a progress spinner during generation — this is expected behavior; include it in the recording to show automation
