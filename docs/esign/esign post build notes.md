SF-eSign: Post-Build Production Readiness
1. Deployment Validation Checklist
Pre-Deploy

[ ] sf org login web --alias nonprofitorg
[ ] Confirm API version 61.0 in sfdx-project.json
[ ] Update CustomLabels.labels-meta.xml — replace all placeholder values:
      ESign_Site_Base_URL      → your actual site URL
      ESign_Support_Email      → real support email
      ESign_Org_Display_Name   → your org display name
[ ] Zip ESign_Assets static resource:
      cd force-app/main/default/staticresources
      zip -r ESign_Assets.resource ESign_Assets/
Deploy Objects First (order matters — Audit has Master-Detail on Request)

sf project deploy start \
  --source-dir force-app/main/default/objects/Signature_Request__c \
  --target-org nonprofitorg --wait 10

sf project deploy start \
  --source-dir force-app/main/default/objects/Signature_Audit__c \
  --target-org nonprofitorg --wait 10
Deploy Everything Else

sf project deploy start \
  --source-dir force-app/main/default \
  --target-org nonprofitorg --wait 30
Post-Deploy Configuration
Salesforce Site Setup:


Setup → Sites → New
  Label:              ESign Portal
  Name:               esign
  Home Page:          SignDocument
  Status:             Active
→ Save

Sites → ESign Portal → Visualforce Pages → Add:
  ✓ SignDocument

Sites → ESign Portal → Public Access Settings → Edit:
  Object: Signature_Request__c  → Read: ✓   Create/Edit/Delete: ✗
  Object: Signature_Audit__c    → Read: ✗   Create: ✓   Edit/Delete: ✗
  Object: ContentVersion        → Read: ✓   Create: ✓   Edit/Delete: ✗
  VF Pages → ESignDocumentController: ✓ Enabled
Permission Set Assignment:


sf org assign permset \
  --name Signature_Module_Admin \
  --on-behalf-of admin@yourorg.com \
  --target-org nonprofitorg
Verify Custom Labels (Setup → Custom Labels):


[ ] ESign_Site_Base_URL             ← must match your Site URL exactly
[ ] ESign_Token_Expiry_Hours_Default = 72
[ ] ESign_Max_Reminders             = 3
[ ] ESign_Rate_Limit_Per_Hour       = 10
[ ] ESign_Support_Email             ← valid monitored inbox
[ ] ESign_Org_Display_Name          ← as shown in emails
Activate Scheduler (Execute Anonymous):


ESignExpiryScheduler.scheduleDaily();
// Verify: Setup → Scheduled Jobs → "ESign Daily Expiry Job" appears
Verify Trigger is Active:


Setup → Apex Triggers → ESignAuditTrigger → Status: Active
2. End-to-End Test Scenarios
TC-01: Create Request via Apex

// Prerequisites: Any file uploaded to org. Get its ContentDocumentId.
List<ContentDocument> docs = [SELECT Id FROM ContentDocument LIMIT 1];

ESignRequest req = new ESignRequest();
req.contentDocumentId = docs[0].Id;
req.recipientEmail    = 'your-test-email@example.com';
req.recipientName     = 'Test Signer';
req.expiryHours       = 1;

ESignResult result = ESignService.createSignatureRequest(req);

// ASSERT
System.assert(result.success, result.errorMessage);
System.assert(result.signingUrl.contains('token=esign_'));
System.assert(result.signatureRequestName.startsWith('SR-'));

// Verify record
Signature_Request__c sr = [SELECT Status__c, Secure_Token__c
    FROM Signature_Request__c WHERE Id = :result.signatureRequestId];
System.assertEquals('Pending', sr.Status__c);
System.assert(sr.Secure_Token__c.startsWith('esign_'));
Expected: ESignResult.success = true, record created, 2 audit events (Created + Email_Sent).

TC-02: Email Delivery Verification

1. Run TC-01 with your real email address
2. CHECK:
   [ ] Email received within 2 minutes
   [ ] Subject contains "SR-XXXX"
   [ ] "Review & Sign Document" button present
   [ ] "Raise a Support Case" link present
   [ ] Link format: {ESign_Site_Base_URL}/apex/SignDocument?token=esign_...
   [ ] Expiry date shown is correct (now + expiryHours)
3. Click link → page should load (Status changes Pending → Viewed)
4. Verify Signature_Request__c.Status__c = 'Viewed'
5. Verify new Signature_Audit__c record with Event_Type = 'Viewed'
TC-03: Draw Signature Flow

1. Open signing link
2. VERIFY:
   [ ] Document renders in iframe (PDF visible)
   [ ] Request name shown in header
   [ ] "Draw" tab is active by default
3. Draw a signature on canvas
4. Click "I Agree & Sign Document"
5. VERIFY:
   [ ] Page shows "Document Signed Successfully"
   [ ] Timestamp displayed
   [ ] Reference number shown
6. In org: Signature_Request__c
   [ ] Status = Signed
   [ ] Signed_DateTime__c populated
   [ ] Signing_IP__c populated
   [ ] Signature_Type__c = Draw
   [ ] Signature_Image_Id__c populated (ContentDocumentId)
   [ ] Signed_Document_Id__c populated (new ContentVersion)
7. Signature_Audit__c events: Created, Email_Sent, Viewed, Signed (4 records)
TC-04: Type Signature Flow

1. Open a fresh signing link (new request)
2. Click "Type" tab
3. Type full name in input field
4. VERIFY canvas renders typed name in script font
5. Submit → VERIFY Signature_Type__c = 'Type'
TC-05: Upload Signature Flow

1. Open a fresh signing link
2. Click "Upload" tab
3. Upload a PNG image (< 2 MB)
4. VERIFY preview image appears
5. Submit → VERIFY Signature_Type__c = 'Upload'
Edge case: Upload a file > 2 MB → browser alert should block submission.

TC-06: Expired Token Scenario

// Force-expire a request
Signature_Request__c sr = [SELECT Id FROM Signature_Request__c
    WHERE Status__c = 'Pending' LIMIT 1];
sr.Token_Expiry__c = DateTime.now().addHours(-1);
update sr;

1. Open signing link for that request
2. VERIFY: Page shows "Link Expired" error state (not a blank/error page)
3. Verify Status_c updated to 'Expired'
4. Verify Audit event: Event_Type = 'Expired'
TC-07: Already Signed Scenario

1. Complete a signing (TC-03)
2. Re-open the same signing link
3. VERIFY: Page shows "Already Signed" state
4. No new audit events created
5. No status change on the record
TC-08: Decline Flow

1. Open signing link
2. Click "Decline to Sign"
3. Confirm browser dialog
4. VERIFY: Page shows "You Have Declined"
5. Signature_Request__c.Status__c = 'Declined'
6. Audit event: Event_Type = 'Declined'
7. Re-open link → "Request Unavailable" error state
TC-09: Audit Immutability Enforcement

// Must throw — second enforcement layer
Signature_Audit__c audit = [SELECT Id FROM Signature_Audit__c LIMIT 1];
try {
    audit.Actor_Email__c = 'tampered@example.com';
    update audit;
    System.assert(false, 'Expected DMLException was not thrown');
} catch (DmlException e) {
    System.assert(e.getMessage().contains('immutable'));
}

try {
    delete audit;
    System.assert(false, 'Expected DMLException was not thrown');
} catch (DmlException e) {
    System.assert(e.getMessage().contains('immutable'));
}
TC-10: Signed Document Version Verification

Signature_Request__c sr = [SELECT Signed_Document_Id__c,
    Content_Version_Id__c FROM Signature_Request__c
    WHERE Status__c = 'Signed' LIMIT 1];

// Original version still exists (never overwritten)
List<ContentVersion> original = [SELECT Id, Title FROM ContentVersion
    WHERE Id = :sr.Content_Version_Id__c];
System.assertEquals(1, original.size());

// New signed version exists under same ContentDocument
List<ContentVersion> signedVer = [SELECT Id, Title, Description
    FROM ContentVersion
    WHERE ContentDocumentId = :sr.Signed_Document_Id__c
    AND Title LIKE '%SIGNED%'];
System.assertEquals(1, signedVer.size());
System.assert(signedVer[0].Description.contains('SF-eSign'));
System.assert(signedVer[0].Description.contains('signerEmail'));
3. Debug & Logging Strategy
Enable Debug Logs

Setup → Debug Logs → New
  User: your admin or the Guest User for the Site
  Duration: 30 minutes
  Debug Level: APEX_CODE=DEBUG, WORKFLOW=INFO, CALLOUT=INFO
For Site/Guest User issues — the Guest User is a specific profile user. Find it:


Setup → Sites → ESign Portal → Public Access Settings
  → User: "ESign Portal Guest User" → Enable debug log for that user
Failure: Email Not Received

1. Check Debug Logs → search "ESignEmailService"
2. Look for "Email dispatch failed" entry
3. Common causes:
   a. Email template not found:
      → Setup → Classic Email Templates → unfiled$public folder
      → Confirm "ESign Signing Request" exists and is Available
   b. Org-wide email not verified:
      → Setup → Org-Wide Email Addresses → verify the address
   c. Email deliverability setting:
      → Setup → Deliverability → Access Level = "All Email"
4. Check: Setup → Email Log Files → run for past 1 hour
Failure: Token Validation / Page Shows Error

1. Check the token in the URL — must start with "esign_"
2. Execute Anonymous — verify the record exists:
   List<Signature_Request__c> sr = [SELECT Id, Status__c,
       Token_Expiry__c FROM Signature_Request__c
       WHERE Secure_Token__c = 'esign_XXXX'];
   System.debug(sr);
3. Debug Log → search "ESignTokenService" or "ESignDocumentController"
4. Common causes:
   a. TOKEN_INVALID → External ID not indexed yet (redeploy object)
   b. TOKEN_EXPIRED → Token_Expiry__c in the past
   c. RATE_LIMITED → Session cache hit → wait 1 hour or clear via:
      Cache.Session.remove('local.ESign.' + token.substring(0,20));
Failure: VF Page Blank / JS Error

1. Browser DevTools → Console tab → check for JS errors
2. Common causes:
   a. Static resource not deployed as ZIP:
      → Redeploy ESign_Assets.resource as a ZIP file
      → Verify URL: {siteUrl}/resource/ESign_Assets/css/esign.css loads
   b. CSP blocking:
      → Setup → CSP Trusted Sites → add your site domain
   c. Canvas not loading on mobile:
      → Test with desktop browser first
3. Check: ApexPages.currentPage().getHeaders() returns expected values
   (test from Execute Anonymous in a guest-user-simulated context)
Failure: Signed Document Not Created

Debug Log → search "ESignDocumentService"
Common causes:
  a. ContentVersion insert failed → check FLS for Guest User on ContentVersion
  b. ContentDocumentLink insert failed → check Guest User CRUD on CDL
  c. Related_Record_Id is invalid → linkDocumentToRecord() silently skips
     if recordId is blank; check that value is passed correctly
Key Log Markers to Search
Failure	Search Term
Email	ESignEmailService
Token	ESignTokenService
Signing page	ESignDocumentController
Document	ESignDocumentService
Expiry job	ESignExpiryScheduler
Audit	ESignAuditService
Rate limit	Rate_Limited
4. DocGen Integration
Where to Call in DocGen
The integration point is immediately after DocGen generates and saves the PDF as a ContentVersion. That happens in your existing DocGenService or equivalent Apex class.


// In your existing DocGen Apex — after PDF insert:
public static void generateAndSend(Id recordId, String recipientEmail) {

    // === YOUR EXISTING DocGen code ===
    ContentVersion generatedPdf = new ContentVersion(
        Title        = 'Agreement - ' + recordId,
        PathOnClient = 'agreement.pdf',
        VersionData  = pdfBlob
    );
    insert generatedPdf;
    String contentDocId = [SELECT ContentDocumentId FROM ContentVersion
                           WHERE Id = :generatedPdf.Id].ContentDocumentId;
    // === END DocGen code ===

    // === CALL SF-eSign (the only coupling needed) ===
    ESignRequest req = new ESignRequest();
    req.contentDocumentId = contentDocId;
    req.recipientEmail    = recipientEmail;
    req.relatedRecordId   = recordId;
    req.relatedObjectType = recordId.getSObjectType().getDescribe().getName();
    req.sourceSystem      = 'DocGen';
    req.messageToSigner   = 'Please review and sign the attached document.';

    ESignResult result = ESignService.createSignatureRequest(req);
    // Optionally store result.signatureRequestId on the DocGen record
}
That is the complete integration. DocGen imports nothing from SF-eSign beyond calling one method.

LWC Integration (Recommended UX)
Add a "Send for Signature" button to your DocGen LWC viewer after generation succeeds:


<!-- docGenViewer.html — add after successful generation -->
<template if:true={showSignaturePanel}>
    <c-e-sign-launcher
        content-document-id={generatedDocumentId}
        related-record-id={recordId}
        related-object-type={objectApiName}
        default-recipient-email={recipientEmail}
        source-system="DocGen"
        onsigningrequestcreated={handleSigningRequestCreated}
        oncancel={handleSignatureCancel}>
    </c-e-sign-launcher>

    <!-- Track status after sending -->
    <template if:true={signatureRequestId}>
        <c-e-sign-status-badge
            signature-request-id={signatureRequestId}
            show-date>
        </c-e-sign-status-badge>
    </template>
</template>

// docGenViewer.js additions
@track showSignaturePanel = false;
@track signatureRequestId = null;

handleDocGenComplete(evt) {
    this.generatedDocumentId = evt.detail.contentDocumentId;
    this.showSignaturePanel  = true; // Reveal launcher after generation
}

handleSigningRequestCreated(evt) {
    this.signatureRequestId  = evt.detail.signatureRequestId;
    this.showSignaturePanel  = false;
}

handleSignatureCancel() {
    this.showSignaturePanel = false;
}
Post-Generation Auto-Trigger (Alternative)
For fully automated flows (no UI step), call from a Flow or Process:


Flow: After DocGen completes
  → Apex Action: ESignService.createSignatureRequest
  → Input: contentDocumentId, recipientEmail, relatedRecordId
  → Output: signatureRequestId (store on record if needed)
Make ESignService.createSignatureRequest invocable for Flow:


// Add this annotation to ESignService (no other change needed):
@InvocableMethod(label='Send Document for Signature'
                 description='Initiates an SF-eSign signing request')
public static List<ESignResult> createSignatureRequestBulk(
    List<ESignRequest> requests) {
    List<ESignResult> results = new List<ESignResult>();
    for (ESignRequest req : requests) {
        results.add(createSignatureRequest(req));
    }
    return results;
}
UX Decision Guide
Scenario	Recommended Approach
User reviews doc before sending	LWC eSignLauncher in DocGen viewer
Auto-send on generation	Apex call in DocGenService
Admin-triggered from record	eSignLauncher on record page
External system triggers	REST API POST
5. Security Review Checklist
Guest User

[ ] Guest User can read Signature_Request__c only by token lookup
    (ESignRequestSelector.findByToken has no SECURITY_ENFORCED —
     correct, because Guest has no FLS, and field list is explicit)
[ ] Guest User cannot query Signature_Request__c freely
    (no SOQL without WHERE Secure_Token__c = :token)
[ ] Guest User cannot create Signature_Request__c directly
    (controller is without sharing + uses System.runAs context for DML)
[ ] Guest User CAN insert Signature_Audit__c
    (required for Viewed/Signed events — confirm object CRUD in Site profile)
[ ] Guest User has NO access to other custom objects
Token Security

[ ] Token is 256-bit AES entropy — computationally non-guessable ✓
[ ] Token is External ID (indexed) — lookups are O(1), no table scan ✓
[ ] Token is NEVER stored in full in Signature_Audit__c — masked to 10 chars ✓
[ ] Token is NEVER logged via System.debug in production code ✓
[ ] Token appears only in URL query param and Signature_Request__c.Secure_Token__c
[ ] Confirm Secure_Token__c field is NOT accessible to Profiles/PSets
    that should not see it (review FLS in Signature_Module_Admin carefully)
[ ] Token expiry is enforced server-side (DateTime.now()) — never client-trusted ✓
File Access Security

[ ] Original ContentDocument is never modified — new ContentVersion only ✓
[ ] Signature image saved as a separate ContentDocument ✓
[ ] Signed document linked to related record with ShareType='V' (View) ✓
[ ] ContentDocumentLink insert skipped if no relatedRecordId ✓
[ ] Guest User cannot access ContentVersion.VersionData directly
    (delivered base64 via controller in response — no direct file URL) ✓
[ ] 10 MB document size guard in ESignDocumentService.getVersionBase64() ✓
Audit Immutability

[ ] Permission Set: allowEdit=false, allowDelete=false on Signature_Audit__c ✓
[ ] ESignAuditTrigger: before update + before delete both throw addError() ✓
[ ] ESignAuditService: only ever calls insert — no update/delete paths ✓
[ ] Test immutability enforcement (TC-09) before go-live
[ ] Confirm trigger is Active in production (not Inactive)
Additional Hardening

[ ] Rate limiting: 10 page loads/token/hour via Session Cache ✓
    → If Session Cache partition not available, fails open (does not block)
    → Configure partition: Setup → Platform Cache → New Session Cache Partition
       Name: ESign, Default: 25 MB
[ ] Prevent double-submission: submit button disabled via JS after click ✓
[ ] isSubmitting flag in controller prevents server-side double-processing ✓
[ ] No SOQL injection risk — all queries use static bind variables ✓
[ ] No XSS risk — all VF output uses apex:outputText or rendered={} (no escape=false)
6. GitHub Finalization
Commit Structure

# Stage only SF-eSign files (not the entire org)
git add force-app/main/default/objects/Signature_Request__c/
git add force-app/main/default/objects/Signature_Audit__c/
git add force-app/main/default/classes/ESign*.cls
git add force-app/main/default/classes/ESign*.cls-meta.xml
git add force-app/main/default/triggers/ESignAuditTrigger.*
git add force-app/main/default/pages/SignDocument.*
git add force-app/main/default/lwc/eSign*/
git add force-app/main/default/staticresources/ESign_Assets/
git add force-app/main/default/staticresources/ESign_Assets.resource-meta.xml
git add force-app/main/default/email/unfiled\$public/ESign_*
git add force-app/main/default/permissionsets/Signature_Module_Admin.*
git add force-app/main/default/labels/CustomLabels.labels-meta.xml
git add docs/esign/
git add scripts/esign/

git commit -m "feat(esign): implement SF-eSign standalone eSignature module v1.0

- Signature_Request__c + Signature_Audit__c data model (31 fields)
- Token-based signing via Salesforce Sites (256-bit entropy)
- Draw / Type / Upload signature capture with canvas + JS
- Immutable audit trail with trigger enforcement (2-layer)
- PDF stamping: Tier 1 manifest + Tier 2 callout with fallback
- ESignEmailService with initial + reminder templates
- ESignExpiryScheduler (daily, bulkified, self-deduplicating)
- REST API: POST create + GET status (/services/apexrest/esign/v1/request)
- LWC: eSignLauncher, eSignStatusBadge, eSignAuditTimeline
- Signature_Module_Admin permission set
- Rate limiting via Session Cache (10 loads/token/hour)
- Deployment guide + integration guide"

git tag -a v1.0.0 -m "SF-eSign v1.0.0 — initial production release"
git push origin main --tags
README Essential Sections

# SF-eSign — Standalone Salesforce eSignature Module

## What It Does
Token-based document signing via Salesforce Sites.
Accepts any ContentDocumentId. No external service required.

## Quick Integration (3 lines of Apex)
[code block from Integration Guide Mode 1]

## Three Integration Modes
- Apex service call
- LWC component drop-in
- REST API

## Deployment
See docs/esign/deployment_guide.md

## Architecture
[paste the layered diagram from architecture doc]

## Security
- 256-bit token entropy
- Immutable audit trail (2-layer enforcement)
- Rate limiting (Session Cache)
- No record IDs exposed in URLs

## Compatibility
- API Version: 61.0
- Requires: Salesforce Sites, Platform Cache (optional)
7. High-Value Future Enhancements
1. Multi-Signer Support (Ordered)
Add a Signature_Request_Signer__c junction object with Order__c and Status__c. The scheduler auto-sends to the next signer when the current one completes. Highest value for contract workflows.

2. Embedded Signing Widget (LWC)
Replace the VF/Sites approach with an Experience Cloud page + LWC signingWidget that runs inside an authenticated portal. Eliminates the Site guest-user complexity and enables pre-filled signer identity from the logged-in user's profile.

3. Signature Placement Coordinates
Store X_Position__c, Y_Position__c, Page_Number__c on the request. The document service uses these to pass precise stamp coordinates to the Tier 2 callout endpoint, enabling legally-positioned signatures rather than appended manifests.

4. Webhook / Platform Event on Status Change
Publish an ESign_Status_Change__e Platform Event when status changes to Signed/Declined/Expired. Allows DocGen and any other subscriber to react in real time without polling the Signature_Request__c record.

5. Bulk Request API
POST /services/apexrest/esign/v1/requests (plural) accepting a JSON array. Process up to 50 requests per call with Database.insert(allRecords, false) for partial success handling. Required for high-volume batch signing workflows (e.g. annual renewal campaigns).