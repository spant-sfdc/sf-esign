# SF-eSign Deployment Guide

## Prerequisites

- Salesforce CLI (sf or sfdx) installed
- Authenticated org alias (e.g. `nonprofitorg`)
- Permission to deploy metadata (Deploy/Modify All)
- A Salesforce Site configured (or create one in step 5)

---

## Step 1: Deploy Metadata

```bash
# From the repository root:
sf project deploy start \
  --source-dir force-app/main/default/objects/Signature_Request__c \
  --source-dir force-app/main/default/objects/Signature_Audit__c \
  --source-dir force-app/main/default/labels \
  --source-dir force-app/main/default/permissionsets/Signature_Module_Admin.permissionset-meta.xml \
  --target-org nonprofitorg

# Then deploy all classes, triggers, pages, LWC, static resources, emails:
sf project deploy start --source-dir force-app --target-org nonprofitorg
```

---

## Step 2: Deploy pdf-lib and html2canvas Static Resources

**Important:** The `pdfLib.js` and `html2canvas.js` files in this repository are placeholders.
Download the real minified bundles before deploying:

```bash
# Download pdf-lib (client-side PDF generation)
curl -o force-app/main/default/staticresources/pdfLib.js \
  https://unpkg.com/pdf-lib/dist/pdf-lib.min.js

# Download html2canvas (HTML-to-canvas for certificate page rendering)
curl -o force-app/main/default/staticresources/html2canvas.js \
  https://html2canvas.hertzen.com/dist/html2canvas.min.js

# Re-deploy static resources
sf project deploy start \
  --source-dir force-app/main/default/staticresources \
  --target-org YOUR_ORG_ALIAS
```

The `ESign_Assets` static resource must be deployed as a ZIP file.
The source-dir deploy above handles this automatically via SFDX.
If deploying via Workbench/ANT, zip the `ESign_Assets/` folder first:

```bash
cd force-app/main/default/staticresources
zip -r ESign_Assets.resource ESign_Assets/
```

---

## Step 3: Configure Custom Labels

In Setup → Custom Labels, update these labels with your org-specific values:

| Label | Value |
|-------|-------|
| `ESign_Site_Base_URL` | `https://yourorg.my.site.com/esign` |
| `ESign_Support_Email` | `support@yourorg.com` |
| `ESign_Org_Display_Name` | `Your Organisation Name` |
| `ESign_Token_Expiry_Hours_Default` | `72` (adjustable) |
| `ESign_Max_Reminders` | `3` (adjustable) |
| `ESign_Rate_Limit_Per_Hour` | `10` (adjustable) |

---

## Step 4: Assign Permission Set

```bash
sf org assign permset \
  --name Signature_Module_Admin \
  --on-behalf-of admin@yourorg.com \
  --target-org nonprofitorg
```

Or in Setup → Permission Sets → Signature Module Admin → Manage Assignments.

---

## Step 5: Configure Salesforce Site

1. Setup → Sites → New
2. Site Label: `ESign Portal`
3. Site Name: `esign`
4. Default Web Address: `esign`
5. Active Site Home Page: `SignDocument`
6. Click **Save**

Add to Site's Visualforce Pages:
- `SignDocument`
- `RaiseCase`
- `ESignThankYou`

Guest User Profile — add object access (read-only on `Signature_Request__c`).

---

## Step 6: Guest User Profile Permissions

In Setup → Sites → ESign Portal → Public Access Settings:

**Object Access:**

| Object | Read | Create | Edit | Delete |
|--------|------|--------|------|--------|
| `Signature_Request__c` | ✓ | ✗ | ✗ | ✗ |
| `Signature_Audit__c` | ✗ | ✓ | ✗ | ✗ |
| `ContentVersion` | ✓ | ✓ | ✗ | ✗ |

The VF controller (`ESignDocumentController`) is declared `without sharing`
and uses System context for DML — the guest user never directly touches records.

---

## Step 7: Schedule Expiry Job

In Developer Console → Execute Anonymous:

```apex
ESignExpiryScheduler.scheduleDaily();
```

Verify in Setup → Scheduled Jobs that `ESign Daily Expiry Job` appears.

---

## Step 8: Configure Org-Wide Email Address (Optional)

For branded "From" on signing emails:
1. Setup → Organisation-Wide Email Addresses → Add
2. Display Name: _(match `ESign_Org_Display_Name` label)_
3. Email Address: `noreply@yourorg.com`

---

## Step 9: Test the Flow

```apex
// Execute Anonymous — creates a test request
ESignRequest req = new ESignRequest();
req.contentDocumentId = '069XXXXXXXXXXXX'; // Any file in your org
req.recipientEmail    = 'your-email@example.com';
req.expiryHours       = 1;

ESignResult result = ESignService.createSignatureRequest(req);
System.debug('Signing URL: ' + result.signingUrl);
```

Check your inbox for the signing email. Open the link. Sign the document.
Verify `Signature_Request__c` status = Signed and `Signature_Audit__c` events.

---

## Step 10: Verify Audit Immutability

```apex
// This should throw — verifies the trigger is active
List<Signature_Audit__c> audits = [SELECT Id FROM Signature_Audit__c LIMIT 1];
if (!audits.isEmpty()) {
    try {
        update audits;
    } catch (DmlException e) {
        System.debug('Immutability confirmed: ' + e.getMessage());
    }
}
```

---

## Deployment Checklist

- [ ] Objects deployed: `Signature_Request__c`, `Signature_Audit__c`
- [ ] New fields deployed: `PDF_Generation_Status__c`, `PDF_Generation_Error__c`, `Confirmation_Email_Status__c`, `Confirmation_Email_Error__c`
- [ ] Custom Labels updated with org-specific values
- [ ] Permission Set assigned to admins
- [ ] Salesforce Site created and activated
- [ ] Guest User profile permissions set
- [ ] `pdfLib.js` replaced with real pdf-lib.min.js bundle
- [ ] `html2canvas.js` replaced with real html2canvas.min.js bundle
- [ ] Static resources deployed
- [ ] Expiry scheduler started
- [ ] Org-Wide Email Address configured (Display Name matches `ESign_Org_Display_Name` label exactly)
- [ ] FLS granted for `Confirmation_Email_Status__c` and `Confirmation_Email_Error__c` if needed
- [ ] LWC record page components added via App Builder
- [ ] End-to-end signing flow tested
- [ ] Audit immutability verified
