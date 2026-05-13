# SF-eSign Developer Guide

> Technical reference for the Salesforce-native eSignature platform.

---

## A. Architecture Overview

SF-eSign is a fully Salesforce-native electronic signature platform. It has no external dependencies for core signing logic — PDF generation and signature capture run entirely client-side in the browser using PDF-LIB and html2canvas, while all state management and email orchestration happen server-side in Apex.

### High-level flow

```
[Salesforce User]
    │  Launches eSignLauncher LWC → calls ESignService.createRequest()
    │  Triggers ESignEmailService.sendSigningRequest()
    ▼
[Signer receives email]
    │  Clicks signing link → opens public Experience Site page
    │  ESignDocumentController (VF controller) validates token, renders doc
    │  Signer applies signature → submits form
    │  ESignDocumentController enqueues ESignSigningQueueable
    ▼
[ESignSigningQueueable — async, SYSTEM_MODE]
    │  Validates token, updates Status__c = 'Signed'
    │  Sets PDF_Generation_Status__c = 'Pending'
    │  Writes Signature_Audit__c record
    ▼
[SignatureRequestAfterUpdate trigger fires]
    │  Status → Signed  → ESignSignedDocumentService → ESignDocumentGenerationQueueable (stub)
    │  Signed_Document_Id__c → populated → ESignConfirmationEmailService → ESignConfirmationEmailQueueable
    ▼
[eSignSignedPdfGenerator LWC — on record page]
    │  Detects Status=Signed, no Signed_Document_Id__c
    │  Fetches original document bytes (PdfGenerationController)
    │  Generates merged PDF client-side (PDF-LIB + html2canvas)
    │  Saves PDF via PdfGenerationController.savePdfWithLinks
    │  Updates Signed_Document_Id__c via PdfGenerationController.updateSignedDocumentId
    ▼
[SignatureRequestAfterUpdate trigger fires again]
    │  Signed_Document_Id__c null→populated → ESignConfirmationEmailService enqueues queueable
    ▼
[ESignConfirmationEmailQueueable — async]
    │  Fetches signed PDF bytes from ContentVersion
    │  Calls ESignEmailService.sendSignedConfirmation()
    │  Updates Confirmation_Email_Status__c = 'Sent' / 'Failed'
```

---

## B. Signing Flow — State Machine

### Signature_Request__c Status values

| Status | Meaning |
|--------|---------|
| `Pending` | Request created, invitation email sent, not yet opened |
| `Viewed` | Signer opened the signing page |
| `Signed` | Signer submitted their signature |
| `Declined` | Signer explicitly declined |
| `Expired` | Token expiry date passed; set by `ESignExpiryScheduler` |

### Token lifecycle

Tokens are generated as: `'esign_' + EncodingUtil.convertToHex(Crypto.generateAesKey(256)).substring(0, 40)`

This produces a 45-character URL-safe string unique per request. Tokens are stored in `Secure_Token__c` and validated by `ESignTokenService.validateAndFetch()` which:
1. Looks up the record by token
2. Checks `Status__c` is `Pending` or `Viewed`
3. Checks `Token_Expiry__c` has not passed
4. Enforces rate limiting via Platform Cache (max attempts per token)

### Signed_Document_Id__c lifecycle

This field stores the ContentDocument ID of the final merged signed PDF. It is:
- `null` until the client-side PDF generation completes
- Populated by `PdfGenerationController.updateSignedDocumentId()` after a successful upload
- The trigger guards against re-triggering the confirmation email: `old.Signed_Document_Id__c == null && new.Signed_Document_Id__c != null`

---

## C. PDF Generation

PDF generation is entirely client-side using two static resources:

| Resource | Purpose |
|----------|---------|
| `pdfLib` | [PDF-LIB](https://pdf-lib.js.org/) — create and modify PDFs in the browser |
| `html2canvas` | Render HTML DOM to canvas for PDF page content |

### eSignSignedPdfGenerator LWC

This LWC auto-runs on the `Signature_Request__c` record page when:
- `Status__c == 'Signed'`
- `Signed_Document_Id__c` is null (no PDF yet)

**Generation steps:**
1. `PdfGenerationController.getSignatureRequestData` — fetches all signing metadata
2. `PdfGenerationController.getSigningDocumentData` — returns original document as base64
3. Original normalization:
   - PDF → used as-is
   - HTML → rendered to canvas via html2canvas, then embedded in PDF-LIB
   - Other/missing → stub single-page PDF
4. `createSignedPdf()` — appends a Signature Certificate page via PDF-LIB
5. `PdfGenerationController.savePdfWithLinks` — saves the blob as a ContentVersion, creates ContentDocumentLinks to both the Signature Request and the related source record
6. `PdfGenerationController.updateSignedDocumentId` — writes the ContentDocument ID back to `Signed_Document_Id__c`

### Signature Certificate page

The certificate page is rendered as an HTML string and converted to canvas before embedding. It contains:
- Document name and request reference ID
- Signer name, email, IP address, and user agent
- Signing timestamp (ISO 8601)
- Signature image (embedded as base64)
- A tamper-evidence statement

### PdfGenerationController (Apex)

Key methods:

| Method | Description |
|--------|-------------|
| `getSignatureRequestData(requestId)` | Returns all fields needed for PDF generation |
| `getSigningDocumentData(contentVersionId)` | Returns original document base64 and file type |
| `savePdfWithLinks(requestId, relatedRecordId, base64Pdf, fileName)` | Inserts ContentVersion + 2 ContentDocumentLinks |
| `updateSignedDocumentId(requestId, contentDocumentId)` | Updates `Signed_Document_Id__c` |

All DML in `PdfGenerationController` uses `AccessLevel.SYSTEM_MODE` to bypass FLS.

---

## D. Email Orchestration

### Three email types

| Email | Trigger | Class |
|-------|---------|-------|
| Signing invitation | `ESignService.createRequest()` | `ESignEmailService.sendSigningRequest()` |
| Reminder | Manual (from record page) | `ESignEmailService.sendReminder()` |
| Signed confirmation | `ESignConfirmationEmailQueueable` | `ESignEmailService.sendSignedConfirmation()` |

### Org-wide email address (OWA)

All emails are sent from a branded OWA. `ESignEmailService.applyOwa()` queries:
```apex
SELECT Id FROM OrgWideEmailAddress
WHERE DisplayName = :System.Label.ESign_Org_Display_Name
LIMIT 1
```

If no OWA is found, the email sends from the default org email. The `ESign_Org_Display_Name` label value **must exactly match** the Display Name configured in Setup → Email → Organization-Wide Email Addresses.

### Confirmation email flow

```
SignatureRequestAfterUpdate trigger
  → Signed_Document_Id__c null→populated
  → ESignConfirmationEmailService.enqueueConfirmationEmails()
      Sets Confirmation_Email_Status__c = 'Pending'
      System.enqueueJob(new ESignConfirmationEmailQueueable(reqId, contentDocId))
  → ESignConfirmationEmailQueueable.execute()
      Queries Signature_Request__c fields
      Queries ContentVersion (VersionData, ORDER BY VersionNumber DESC LIMIT 1)
      Guards: isEmpty() || blobBytes == 0 → markFailed()
      Calls ESignEmailService.sendSignedConfirmation(req, pdfBlob, fileName)
      Sets Confirmation_Email_Status__c = 'Sent'
      On any exception → markFailed() → sets 'Failed' + error detail
```

`ESignConfirmationEmailService` also guards against duplicate enqueue within the same transaction using a `static Set<Id> processedIds`.

### Rate limiting (reminders)

`ESignEmailService.sendReminder()` checks `Reminder_Sent_Count__c` against `System.Label.ESign_Max_Reminders` before sending. After a successful send it increments the count and sets `Last_Reminder_Sent__c`.

---

## E. Component Inventory

### Apex Classes

| Class | Role |
|-------|------|
| `ESignService` | Core service: create request, expiry, field validation |
| `ESignEmailService` | All email sending: invitation, reminder, confirmation |
| `ESignDocumentController` | VF page controller for the public signing page |
| `ESignDocumentService` | ContentDocument/ContentVersion CRUD, document retrieval |
| `ESignSigningQueueable` | Async worker for Sign / Viewed / Decline actions |
| `ESignSignedDocumentService` | Trigger-facing service; enqueues PDF generation queueable |
| `ESignDocumentGenerationQueueable` | Stub queueable (PDF generation moved to LWC) |
| `ESignConfirmationEmailService` | Trigger-facing service; enqueues confirmation email queueable |
| `ESignConfirmationEmailQueueable` | Async worker: fetches PDF, calls sendSignedConfirmation |
| `ESignTokenService` | Token generation, validation, masking, rate limiting |
| `ESignAuditService` | Write `Signature_Audit__c` records; `log()` and `logError()` |
| `ESignAuditTimelineController` | LWC wire adapter controller for audit timeline |
| `ESignRequestSelector` | SOQL selector for `Signature_Request__c` |
| `ESignRequest` | Domain wrapper |
| `ESignResult` | Service result DTO |
| `ESignException` | Custom exception class |
| `ESignExpiryScheduler` | Schedulable: marks expired Signature Requests |
| `ESignRestAPI` | REST endpoint for external integrations |
| `PdfGenerationController` | Apex controller for client-side PDF save operations |

### LWC Components

| Component | Purpose | Placement |
|-----------|---------|-----------|
| `eSignLauncher` | Send signature request wizard | Source record page |
| `eSignStatusBadge` | Displays current status with color coding | Signature_Request__c record page |
| `eSignAuditTimeline` | Renders audit event history | Signature_Request__c record page |
| `eSignSignedPdfGenerator` | Auto-generates signed PDF after signing | Signature_Request__c record page |
| `eSignPdfStatusPanel` | Shows PDF generation status with retry | Signature_Request__c record page |
| `eSignButton` | Utility button component used by launcher | Internal (used by eSignLauncher) |

### Static Resources

| Resource | Contents |
|----------|---------|
| `pdfLib` | PDF-LIB minified bundle (`pdf-lib.min.js`) |
| `html2canvas` | html2canvas minified bundle (`html2canvas.min.js`) |
| `ESign_Assets` | Branded assets (logo, icons) used in email templates and signing page |

> **Important:** `pdfLib.js` and `html2canvas.js` are placeholder files in this repository. Replace them with the actual minified bundles before deploying. See [Deployment Notes](#g-deployment-notes).

### Triggers

| Trigger | Object | Events | Purpose |
|---------|--------|--------|---------|
| `ESignAuditTrigger` | `Signature_Request__c` | after insert, after update | Writes audit records on status change |
| `SignatureRequestAfterUpdate` | `Signature_Request__c` | after update | Fires PDF generation and confirmation email queueables |

### Key Custom Fields on Signature_Request__c

| Field | Type | Purpose |
|-------|------|---------|
| `Status__c` | Picklist | Current signing state |
| `Secure_Token__c` | Text | Unique signing token |
| `Token_Expiry__c` | DateTime | Link expiry |
| `Content_Version_Id__c` | Text | ContentVersion ID of original document |
| `Signed_Document_Id__c` | Text | ContentDocument ID of merged signed PDF |
| `Signature_Image_Id__c` | Text | ContentDocument ID of signature image |
| `PDF_Generation_Status__c` | Picklist | Pending / Processing / Complete / Failed |
| `PDF_Generation_Error__c` | LongTextArea | PDF generation error detail |
| `Confirmation_Email_Status__c` | Picklist | Pending / Sent / Failed |
| `Confirmation_Email_Error__c` | LongTextArea | Confirmation email error detail |
| `Signed_DateTime__c` | DateTime | When signing occurred |
| `Signer_Email__c` | Email | Confirmed at signing |
| `Signing_IP__c` | Text | Signer's IP address |
| `Signer_User_Agent__c` | Text | Signer's browser/device |
| `Decline_Reason__c` | Picklist | Why signer declined |
| `Decline_Description__c` | LongTextArea | Free-text decline explanation |

---

## F. Security & Audit

### Token-based access

The signing page is publicly accessible (no Salesforce login required). Access is controlled entirely by the `Secure_Token__c` value in the URL. Tokens are:
- 45 characters, cryptographically random (256-bit AES key → hex → substring)
- Validated in `ESignTokenService.validateAndFetch()` on every request
- Rate-limited via Platform Cache to prevent brute-force enumeration
- Single-use in practice (once `Status__c = 'Signed'` the queueable returns immediately on subsequent calls)

### DML security model

All DML on the signing page path runs through `ESignSigningQueueable` with `AccessLevel.SYSTEM_MODE`. This is intentional — the signer is a guest user with no Salesforce license, and their action must not be blocked by sharing rules or FLS.

### Audit trail

Every meaningful event writes a `Signature_Audit__c` child record with:
- `Event_Type__c` — e.g. `Email_Sent`, `Viewed`, `Signed`, `Declined`, `Reminder_Sent`, `Error`
- `Actor_Email__c` — who performed the action
- `IP_Address__c` — client IP at the time of the event
- `User_Agent__c` — browser/device information
- `Timestamp__c` — UTC timestamp

The `ESignAuditTimeline` LWC displays these events chronologically on the record page.

### Expiration enforcement

`ESignExpiryScheduler` is a `Schedulable` class that queries for Signature Requests with `Token_Expiry__c < NOW()` and `Status__c IN ('Pending', 'Viewed')` and bulk-updates them to `Expired`. Schedule it daily via Anonymous Apex (see `scripts/esign/schedule_expiry_job.apex`).

---

## G. Deployment Notes

### Step 1: Deploy Metadata

```bash
sf project deploy start \
  --source-dir force-app/main/default/objects/Signature_Request__c \
  --source-dir force-app/main/default/objects/Signature_Audit__c \
  --source-dir force-app/main/default/labels \
  --source-dir force-app/main/default/permissionsets/Signature_Module_Admin.permissionset-meta.xml \
  --source-dir force-app/main/default/classes \
  --source-dir force-app/main/default/triggers \
  --source-dir force-app/main/default/lwc \
  --source-dir force-app/main/default/staticresources \
  --source-dir force-app/main/default/pages \
  --source-dir force-app/main/default/email \
  --source-dir force-app/main/default/sites \
  --source-dir force-app/main/default/flexipages \
  --source-dir force-app/main/default/applications \
  --source-dir force-app/main/default/tabs \
  --target-org YOUR_ORG_ALIAS
```

### Step 2: Deploy static resource bundles

The `pdfLib` and `html2canvas` static resources in this repo are **placeholder files**. Replace them before deploying:

```bash
# Download pdf-lib
curl -o force-app/main/default/staticresources/pdfLib.js \
  https://unpkg.com/pdf-lib/dist/pdf-lib.min.js

# Download html2canvas
curl -o force-app/main/default/staticresources/html2canvas.js \
  https://html2canvas.hertzen.com/dist/html2canvas.min.js
```

Then re-deploy the static resources:

```bash
sf project deploy start \
  --source-dir force-app/main/default/staticresources \
  --target-org YOUR_ORG_ALIAS
```

### Step 3: Configure custom labels

Update these labels in Setup → Custom Labels to match your org:

| Label | Example value |
|-------|--------------|
| `ESign_Site_Base_URL` | `https://yourorg.my.salesforce-sites.com/esign` |
| `ESign_Org_Display_Name` | `TechPulse Solutions` |
| `ESign_Support_Email` | `support@yourorg.com` |
| `ESign_Max_Reminders` | `3` |
| `ESign_Token_Expiry_Days` | `14` |

### Step 4: Configure Org-Wide Email Address

1. Go to Setup → Email → Organization-Wide Email Addresses.
2. Add an address with Display Name exactly matching the `ESign_Org_Display_Name` label value.
3. Verify the email address (Salesforce sends a confirmation link).
4. Ensure **Allow Display Name Edit** is checked if you want to use a custom display name.

### Step 5: Assign permissions

```bash
sf org assign permset \
  --name Signature_Module_Admin \
  --target-org YOUR_ORG_ALIAS
```

### Step 6: Configure Experience Site

1. Ensure a public Experience Site exists (e.g. `/esign`).
2. Add the `SignDocument` and `RaiseCase` Visualforce pages to the Site's list of allowed pages.
3. Set **Guest User Access** to allow unauthenticated access to these pages.
4. Activate the site.

### Step 7: Grant FLS for confirmation status fields

If the `Confirmation_Email_Status__c` and `Confirmation_Email_Error__c` fields are not visible after deployment, grant FLS via Anonymous Apex:

```apex
// Find the System Administrator profile's PermissionSet ID
String permSetId = [
    SELECT Id FROM PermissionSet
    WHERE Profile.Name = 'System Administrator' AND IsOwnedByProfile = true
    LIMIT 1
].Id;

insert new List<FieldPermissions>{
    new FieldPermissions(ParentId=permSetId, SobjectType='Signature_Request__c',
        Field='Signature_Request__c.Confirmation_Email_Status__c',
        PermissionsRead=true, PermissionsEdit=true),
    new FieldPermissions(ParentId=permSetId, SobjectType='Signature_Request__c',
        Field='Signature_Request__c.Confirmation_Email_Error__c',
        PermissionsRead=true, PermissionsEdit=true)
};
```

### Step 8: Schedule the expiry job

```apex
// Run once via Anonymous Apex
System.schedule('ESign Expiry Job', '0 0 2 * * ?', new ESignExpiryScheduler());
```

### Step 9: Add record page components

Add these LWC components to the `Signature_Request__c` record page via App Builder:
- `eSignStatusBadge` — near the top
- `eSignSignedPdfGenerator` — in the main body (renders only when needed)
- `eSignPdfStatusPanel` — adjacent to `eSignSignedPdfGenerator`
- `eSignAuditTimeline` — in a tab or section at the bottom

Add `eSignLauncher` to the source record pages (e.g. Opportunity, Contact).

### Required Metadata Objects

| Object | Purpose |
|--------|---------|
| `Signature_Request__c` | Primary signing record |
| `Signature_Audit__c` | Audit event log |
| `Document_Template__c` | DocGen template (if using with DocGen module) |
