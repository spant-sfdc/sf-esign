# SF-eSign

Standalone, token-based eSignature module for Salesforce.

Accepts **any** `ContentDocumentId`. No external service required. No dependency on any specific system (DocGen, ERP, etc.).

---

## What It Does

- Sends any Salesforce file for electronic signature via a secure, time-limited link
- Supports Draw, Type, and Upload signature modes
- Maintains an immutable audit trail (`Signature_Audit__c`)
- Generates a signed document version (original never modified)
- Exposes three integration modes: Apex service call, LWC component, REST API

---

## Quick Start (3 lines of Apex)

```apex
ESignRequest req = new ESignRequest();
req.contentDocumentId = '069XXXXXXXXXXXX'; // Any ContentDocumentId
req.recipientEmail    = 'signer@example.com';
ESignResult result = ESignService.createSignatureRequest(req);
// result.signingUrl → email dispatched automatically
```

---

## Integration Modes

### 1. Apex Service Call
```apex
ESignResult result = ESignService.createSignatureRequest(req);
```

### 2. LWC Component
```html
<c-e-sign-launcher
    content-document-id={documentId}
    related-record-id={recordId}
    onsigningrequestcreated={handleCreated}>
</c-e-sign-launcher>
```

### 3. REST API
```
POST /services/apexrest/esign/v1/request
GET  /services/apexrest/esign/v1/request?id={signatureRequestId}
```

---

## Architecture

```
Caller (DocGen / LWC / REST)
        │
        ▼
ESignService.createSignatureRequest()   ← Single entry point
        │
        ├── ESignTokenService            ← 256-bit secure token
        ├── ESignAuditService            ← Immutable audit (insert-only)
        ├── ESignEmailService            ← Email dispatch
        └── ESignDocumentService         ← Document retrieval + signing
                │
                ▼
        Salesforce Sites (Guest)
                │
                ▼
        SignDocument.page (VF)
                │
        Draw / Type / Upload signature
                │
                ▼
        Signed ContentVersion created
        Audit trail complete
```

---

## Security

| Feature | Detail |
|---------|--------|
| Token entropy | 256-bit AES, prefixed `esign_` |
| Token masking | First 10 chars stored in audit logs only |
| Rate limiting | 10 page loads/token/hour (Platform Cache) |
| Audit immutability | Permission set + Apex trigger (2-layer) |
| Guest user access | Token-gated only, no direct record access |
| Document integrity | Original never modified, new ContentVersion only |

---

## Deployment

See [docs/deployment_guide.md](docs/deployment_guide.md) for full instructions.

**Quick steps:**
1. Deploy metadata to org
2. Update 6 Custom Labels with org-specific values
3. Create Salesforce Site (Setup UI)
4. Assign `Signature_Module_Admin` permission set
5. Run `ESignExpiryScheduler.scheduleDaily()` in Execute Anonymous

---

## Integration with DocGen (or any system)

```apex
// After generating your document:
ESignRequest req = new ESignRequest();
req.contentDocumentId = generatedContentDocId;
req.recipientEmail    = recipientEmail;
req.relatedRecordId   = opportunityId;
req.sourceSystem      = 'DocGen';
ESignService.createSignatureRequest(req);
```

Full guide: [docs/integration_guide.md](docs/integration_guide.md)

---

## File Structure

```
force-app/main/default/
├── objects/
│   ├── Signature_Request__c/   ← 22 fields, signing lifecycle
│   └── Signature_Audit__c/     ← 9 fields, immutable audit trail
├── classes/
│   ├── ESignService.cls         ← Public entry point
│   ├── ESignTokenService.cls    ← Token generation & validation
│   ├── ESignAuditService.cls    ← Audit trail engine
│   ├── ESignEmailService.cls    ← Email dispatch
│   ├── ESignDocumentService.cls ← Document handling + PDF stamping
│   ├── ESignRequestSelector.cls ← All SOQL centralised here
│   ├── ESignDocumentController.cls ← VF page controller (Sites-safe)
│   ├── ESignAuditTimelineController.cls
│   ├── ESignRestAPI.cls         ← REST API endpoint
│   ├── ESignExpiryScheduler.cls ← Daily expiry job
│   ├── ESignException.cls
│   ├── ESignRequest.cls         ← Input DTO
│   └── ESignResult.cls          ← Output DTO
├── triggers/
│   └── ESignAuditTrigger.trigger ← Immutability enforcement
├── pages/
│   └── SignDocument.page         ← Public signing page
├── lwc/
│   ├── eSignLauncher/            ← Integration entry component
│   ├── eSignStatusBadge/         ← Live status display
│   └── eSignAuditTimeline/       ← Audit history UI
├── staticresources/ESign_Assets/ ← CSS + JS for signing page
├── email/                        ← Email templates
├── permissionsets/               ← Signature_Module_Admin
└── labels/                       ← 6 configurable custom labels
```

---

## Compatibility

- Salesforce API Version: 61.0+
- Requires: Salesforce Sites (for public signing page)
- Optional: Platform Cache (for rate limiting), Org-Wide Email Address

---

## Version

`v1.0.0` — Initial production release
