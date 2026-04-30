# SF-eSign Integration Guide

## Overview

SF-eSign is a standalone, token-based eSignature module for Salesforce.
It accepts any `ContentDocumentId` and handles the complete signing lifecycle.

Three integration modes are supported. All three share the same contract:
supply a `ContentDocumentId` + `recipientEmail`, receive an `ESignResult`.

---

## Mode 1: Apex Service Call

The simplest integration. Call from any Apex class.

```apex
ESignRequest req = new ESignRequest();
req.contentDocumentId = '069XXXXXXXXXXXX';   // Any ContentDocumentId
req.recipientEmail    = 'signer@example.com';
req.recipientName     = 'Jane Smith';         // Optional
req.relatedRecordId   = opportunityId;        // Optional — any SObject Id
req.relatedObjectType = 'Opportunity';        // Optional
req.messageToSigner   = 'Please sign the attached agreement.'; // Optional
req.expiryHours       = 48;                   // Optional, default 72
req.sourceSystem      = 'DocGen';             // Optional, for audit trail

ESignResult result = ESignService.createSignatureRequest(req);

if (result.success) {
    // result.signatureRequestId  — Salesforce record Id
    // result.signatureRequestName — e.g. 'SR-0001'
    // result.signingUrl           — the link sent to the signer
} else {
    // result.errorCode    — e.g. 'VALIDATION_ERROR'
    // result.errorMessage — human-readable detail
}
```

### DocGen Example

```apex
// In your DocGen Apex, after PDF generation:
public static void sendForSignature(String contentDocumentId,
                                     String recipientEmail,
                                     Id relatedRecordId) {
    ESignRequest req = new ESignRequest();
    req.contentDocumentId = contentDocumentId;
    req.recipientEmail    = recipientEmail;
    req.relatedRecordId   = relatedRecordId;
    req.relatedObjectType = 'Opportunity';
    req.sourceSystem      = 'DocGen';
    ESignService.createSignatureRequest(req);
}
```

---

## Mode 2: LWC Component

Drop `<c-e-sign-launcher>` into any Lightning page or custom component.

```html
<!-- Parent component template -->
<c-e-sign-launcher
    content-document-id={generatedDocumentId}
    related-record-id={recordId}
    related-object-type="Opportunity"
    default-recipient-email={contactEmail}
    source-system="DocGen"
    onsigningrequestcreated={handleRequestCreated}>
</c-e-sign-launcher>
```

```js
// Parent component JS
handleRequestCreated(evt) {
    const { signatureRequestId, signingUrl } = evt.detail;
    // Store signatureRequestId, update UI, etc.
}
```

Display live status anywhere:

```html
<c-e-sign-status-badge
    signature-request-id={signatureRequestId}
    show-date>
</c-e-sign-status-badge>
```

Display full audit trail:

```html
<c-e-sign-audit-timeline
    signature-request-id={signatureRequestId}>
</c-e-sign-audit-timeline>
```

---

## Mode 3: REST API

Use from any external system (CRM, ERP, middleware).

### Create Request

```
POST /services/apexrest/esign/v1/request
Content-Type: application/json
Authorization: Bearer {OAuth_Token}

{
    "contentDocumentId": "069XXXXXXXXXXXX",
    "recipientEmail":    "signer@example.com",
    "recipientName":     "Jane Smith",
    "relatedRecordId":   "006XXXXXXXXXXXX",
    "relatedObjectType": "Opportunity",
    "messageToSigner":   "Please review and sign.",
    "expiryHours":       72,
    "sourceSystem":      "ExternalCRM"
}
```

Response `200 OK`:
```json
{
    "success": true,
    "signatureRequestId": "a00XXXXXXXXXXXX",
    "signatureRequestName": "SR-0001",
    "token": "esign_...",
    "signingUrl": "https://yoursite.force.com/esign/apex/SignDocument?token=esign_...",
    "raiseCaseUrl": "https://yoursite.force.com/esign/apex/RaiseCase?token=esign_..."
}
```

### Get Status

```
GET /services/apexrest/esign/v1/request?id={signatureRequestId}
Authorization: Bearer {OAuth_Token}
```

---

## Token Lifecycle

```
Created  →  Email Sent  →  [Signer opens link]
                               │
                               ▼ Viewed
                               │
                     ┌─────────┴──────────┐
                     ▼                    ▼
                   Signed              Declined
                     │
                     ▼
               Signed Document
               (new ContentVersion)
                     +
               Audit Trail
```

Expiry runs nightly at 01:00 AM via `ESignExpiryScheduler`.

---

## Error Codes

| Code | Meaning |
|------|---------|
| `TOKEN_MISSING` | No token in URL |
| `TOKEN_INVALID` | Token not found in database |
| `TOKEN_EXPIRED` | Token past expiry datetime |
| `ALREADY_SIGNED` | Request already in Signed status |
| `REQUEST_CANCELLED` | Admin cancelled the request |
| `REQUEST_DECLINED` | Signer declined |
| `VALIDATION_ERROR` | Missing/invalid input field |
| `DOCUMENT_ERROR` | ContentVersion retrieval failed |
| `EMAIL_ERROR` | Email template missing or dispatch failed |
| `RATE_LIMITED` | Too many page loads for this token in 1 hour |

---

## PDF Stamping

SF-eSign uses a two-tier approach:

**Tier 1 (always applied):** The original document bytes are preserved unchanged.
A new `ContentVersion` is created with a JSON audit manifest in the description
field containing signer name, timestamp, IP, request reference, and signature type.

**Tier 2 (optional callout):** If custom label `ESign_PDF_Stamp_Endpoint` is set,
the service POSTs `{documentBase64, signatureBase64, signerName, signedDateTime}`
to that endpoint and expects `{stampedBase64}` back. Failure falls back to Tier 1
automatically — the signing flow is never interrupted by a failed stamp callout.
