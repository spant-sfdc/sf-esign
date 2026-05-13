# SF-eSign User Guide

> Salesforce-native electronic signature platform for nonprofit and enterprise organizations.

---

## Overview

SF-eSign is a fully native Salesforce electronic signature solution. It allows your team to send documents for signature, track signing status, and store signed PDFs — all without leaving Salesforce or relying on third-party integrations.

**Key benefits:**
- Signers receive a branded email with a secure one-click signing link
- The entire signing experience runs in the browser — no app installs or accounts needed
- Signed PDFs with a tamper-evident Signature Certificate are automatically stored in Salesforce Files
- A confirmation email with the signed PDF is automatically delivered to the signer
- Every action is recorded in an audit timeline on the Signature Request record

---

## A. Sending a Signature Request

### Prerequisites
- The document to be signed must be attached to a Salesforce record as a File (ContentDocument)
- The signer's name and email address must be available

### Steps

1. Navigate to the Salesforce record the document is associated with (e.g. an Opportunity, Contact, or Account).
2. Open the **eSign Launcher** component on the record page.
3. Click **Send for Signature**.
4. Fill in the signature request form:
   - **Recipient Name** — the signer's full name (shown in the email greeting)
   - **Recipient Email** — the email address the signing invitation is sent to
   - **Document** — select the file attached to this record
   - **Expiration Date** *(optional)* — after this date the signing link will no longer work
   - **Message to Signer** *(optional)* — a personal note shown in the invitation email
5. Click **Send**. The system:
   - Creates a `Signature_Request__c` record with Status = **Pending**
   - Generates a unique, one-time secure token
   - Sends a branded signing invitation email from your org's configured sender address

### What happens next
The signer receives an email with a **Review & Sign Document** button. The link is valid until the configured expiration date. After they sign, you will see the status update automatically on the record.

---

## B. Signer Experience

### Receiving the invitation

The signer receives a branded HTML email from your organization containing:
- A personalized greeting
- Any optional message you included
- A large **Review & Sign Document** button
- The link expiration date
- A **Raise a Support Case** link in case of questions

### Opening the signing page

Clicking the button opens a secure public webpage (hosted on your Salesforce Experience Cloud Site). No login is required. The page loads the original document as a PDF preview.

**Status progression on opening:**
`Pending` → `Viewed`

### Signing the document

The signer can apply their signature using one of three methods:
- **Draw** — draw a signature using a mouse, trackpad, or touchscreen
- **Type** — type a name and convert it to a signature font
- **Upload** — upload an image of a handwritten signature

After applying the signature the signer clicks **Sign Document**. The system:
1. Securely submits the signature to Salesforce
2. Updates the Signature Request status to **Signed**
3. Triggers automatic PDF generation (client-side, via PDF-LIB)
4. Sends a confirmation email with the signed PDF attached

**Status on signing:** `Viewed` → `Signed`

### Declining the request

If the signer does not want to sign, they can click **Decline** and provide:
- A reason (e.g. "Wrong recipient", "Document incorrect")
- An optional description

**Status on decline:** `Pending`/`Viewed` → `Declined`

### After signing

The signer sees a confirmation screen. Moments later they receive a **confirmation email** containing:
- The document name and signing timestamp
- The signed PDF with embedded Signature Certificate as an attachment

---

## C. Tracking in Salesforce

### Signature Request record

Every send creates a `Signature_Request__c` record. You can access it from:
- The record it was sent from (via the related list or component)
- The **eSignature** Lightning app

**Key fields on the record:**

| Field | Description |
|-------|-------------|
| Status | Current state: Pending, Viewed, Signed, Declined, Expired |
| Recipient Name / Email | Who the request was sent to |
| Signer Email | Email confirmed at the time of signing |
| Signed Date/Time | When the document was signed |
| Token Expiry | When the signing link expires |
| Message to Signer | Optional note included in the invitation |
| Signature Type | Draw, Type, or Upload |
| Signing IP | IP address recorded at signing |
| Signer User Agent | Browser/device information |
| PDF Generation Status | Pending, Processing, Complete, Failed |
| Confirmation Email Status | Pending, Sent, Failed |
| Confirmation Email Error | Error detail if confirmation email failed |

### Status lifecycle

```
[Created] → Pending → Viewed → Signed → [PDF Generated] → [Confirmation Email Sent]
                              ↘ Declined
                    (token expires) → Expired
```

### Audit timeline

Every action on a Signature Request is recorded in the **Audit Timeline** component on the record page. The timeline shows:
- Email sent / Reminder sent
- Document viewed (with IP and timestamp)
- Document signed (with IP, browser, signature type)
- Document declined (with reason)
- Errors logged

### Reminders

You can send a reminder email from the Signature Request record page. Reminders are rate-limited per the org configuration. Each reminder is logged in the audit timeline.

---

## D. Signed Documents

### Where signed PDFs are stored

After signing, SF-eSign automatically generates a merged PDF containing:
1. The original document pages
2. A Signature Certificate page showing signer name, email, timestamp, IP address, and signature type

This PDF is stored as a **Salesforce File** (ContentDocument) linked to:
- The Signature Request record
- The original source record (e.g. the Opportunity the request was created from)

### Signature Certificate

The last page of every signed PDF is a Signature Certificate that includes:
- Document name and reference ID
- Signer name and email
- Signing timestamp (UTC)
- IP address and user agent recorded at signing
- Signature image
- Verification statement

### Confirmation email

The signer automatically receives a confirmation email with:
- A summary of what was signed and when
- The signed PDF as an attachment

The confirmation email status is tracked on the Signature Request record under **Confirmation Email Status** (Pending / Sent / Failed). If delivery fails, the error is stored in **Confirmation Email Error**.

---

## E. Troubleshooting

### Signer says they didn't receive the email

1. Verify the **Recipient Email** field on the Signature Request record is correct.
2. Ask the signer to check their spam/junk folder.
3. In Salesforce Setup, go to **Email** → **Deliverability** and confirm it is set to **All Email**.
4. Check the audit timeline on the Signature Request — if `Email_Sent` is not present, the send may have failed. Check org-wide email address (OWA) configuration (see below).

### Org-wide email address (branded sender) not working

SF-eSign sends all emails from a branded OWA (e.g. `TechPulse Solutions <hello@example.com>`). If emails arrive from a generic Salesforce address:

1. Go to **Setup → Email → Organization-Wide Email Addresses**.
2. Verify an address exists with Display Name exactly matching the `ESign_Org_Display_Name` custom label value.
3. Confirm the address has been verified (green checkmark).

### Signing link shows "Expired" or "Invalid"

- The `Token_Expiry__c` date on the Signature Request record has passed. Create a new Signature Request for the same document.
- If the token was invalidated manually, check the Signature Request status.

### Signed PDF not generated

1. Check **PDF Generation Status** on the Signature Request record.
2. If it shows **Failed**, check **PDF Generation Error** for the error detail.
3. The `eSignSignedPdfGenerator` LWC on the record page shows a Retry button. Click it to re-attempt generation.
4. Ensure the `pdfLib` and `html2canvas` static resources are deployed and not placeholder files.

### Confirmation email failed

1. Check **Confirmation Email Status** on the Signature Request. If **Failed**, read **Confirmation Email Error** for the detail.
2. Verify the `Signed_Document_Id__c` field is populated (the ContentDocument ID of the signed PDF).
3. Check the OWA configuration (see above).

### Declined request — what to do

A declined request cannot be re-opened. Create a new Signature Request. Review the decline reason captured in `Decline_Reason__c` and `Decline_Description__c` to understand why the signer declined.

---

## F. Custom Labels Reference

The following Custom Labels control SF-eSign behavior and can be updated in **Setup → Custom Labels**:

| Label | Purpose |
|-------|---------|
| `ESign_Site_Base_URL` | Base URL of the Salesforce Experience Site (e.g. `https://org.my.salesforce-sites.com/esign`) |
| `ESign_Org_Display_Name` | Sender name for OWA lookup and email headers |
| `ESign_Support_Email` | Support email shown in email footers |
| `ESign_Max_Reminders` | Maximum number of reminder emails allowed per request |
| `ESign_Token_Expiry_Days` | Default number of days before a signing link expires |
