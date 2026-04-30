/**
 * Public entry point for the SF-eSign module.
 *
 * This is the ONLY class external systems (DocGen, LWC, REST API) should call.
 * All other service classes are internal to the module.
 *
 * Calling pattern:
 *   ESignRequest req = new ESignRequest();
 *   req.contentDocumentId = '069...';
 *   req.recipientEmail    = 'signer@example.com';
 *   ESignResult result = ESignService.createSignatureRequest(req);
 *
 * No DocGen imports. No assumptions about document origin.
 */
public with sharing class ESignService {

    // ─────────────────────────────────────────────────────────────────────────
    // CREATE SIGNATURE REQUEST
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Creates a Signature_Request__c, generates a secure token, and
     * dispatches the signing email.
     *
     * Returns ESignResult with success=true and signing URLs on success,
     * or success=false with errorCode/errorMessage on failure.
     * Never throws — all exceptions are caught and returned as ESignResult.
     */
    @AuraEnabled
    public static ESignResult createSignatureRequest(ESignRequest request) {
        try {
            request.validate();

            // Resolve the ContentVersion to pin before insert
            String versionId = resolveVersionId(request);

            // Build and insert the request record
            Signature_Request__c req = buildRecord(request, versionId);
            insert req;

            // Re-query to get auto-generated Name field
            req = ESignRequestSelector.findById(req.Id);

            // Link original document to this Signature_Request__c record
            if (String.isNotBlank(req.Document_Id__c)) {
                ESignDocumentService.linkDocumentToRecord(req.Document_Id__c, req.Id);
            }

            // Audit: Created
            ESignAuditService.log(
                req.Id, 'Created', req.Recipient_Email__c,
                req.Secure_Token__c, null, null, request.sourceSystem
            );

            // Dispatch signing email (Phase 3 — wired here)
            ESignEmailService.sendSigningRequest(req);

            // Audit: Email_Sent (logged inside ESignEmailService on success)

            return ESignResult.ok(req);

        } catch (ESignException e) {
            ESignAuditService.logError(
                null, e.getMessage(), request?.recipientEmail, null, request?.sourceSystem
            );
            String[] parts = e.getMessage().split(':');
            return ESignResult.fail(parts[0], parts.size() > 1 ? parts[1] : e.getMessage());

        } catch (Exception e) {
            ESignAuditService.logError(
                null, e.getMessage(), request?.recipientEmail, null, request?.sourceSystem
            );
            return ESignResult.fail('UNEXPECTED_ERROR', e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CANCEL REQUEST
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Cancels an active signing request. Admin/system use only.
     * Cannot cancel Signed or already-terminal requests.
     */
    @AuraEnabled
    public static ESignResult cancelSignatureRequest(String signatureRequestId) {
        try {
            Signature_Request__c req = ESignRequestSelector.findById(signatureRequestId);
            if (req == null) {
                return ESignResult.fail('TOKEN_INVALID', 'Request not found');
            }
            if (new Set<String>{'Signed','Expired','Cancelled'}.contains(req.Status__c)) {
                return ESignResult.fail('INVALID_STATE',
                    'Cannot cancel a request in status: ' + req.Status__c);
            }
            req.Status__c = 'Cancelled';
            update req;

            ESignAuditService.log(
                req.Id, 'Cancelled', req.Recipient_Email__c,
                req.Secure_Token__c, null, null, 'Admin'
            );
            return ESignResult.ok(req);

        } catch (Exception e) {
            return ESignResult.fail('UNEXPECTED_ERROR', e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INTERNAL HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    private static Signature_Request__c buildRecord(
            ESignRequest req, String versionId) {

        return new Signature_Request__c(
            Document_Id__c         = req.contentDocumentId,
            Content_Version_Id__c  = versionId,
            Related_Record_Id__c   = req.relatedRecordId,
            Related_Object_Type__c = req.relatedObjectType,
            Recipient_Email__c     = req.recipientEmail.toLowerCase().trim(),
            Recipient_Name__c      = req.recipientName,
            Status__c              = 'Pending',
            Secure_Token__c        = ESignTokenService.generateToken(),
            Token_Expiry__c        = DateTime.now().addHours(req.expiryHours),
            Message_to_Signer__c   = req.messageToSigner,
            Requester_Id__c        = UserInfo.getUserId()
        );
    }

    private static String resolveVersionId(ESignRequest req) {
        if (String.isNotBlank(req.contentVersionId)) {
            return req.contentVersionId;
        }
        List<ContentVersion> versions = [
            SELECT Id
            FROM   ContentVersion
            WHERE  ContentDocumentId = :req.contentDocumentId
            AND    IsLatest          = true
            LIMIT  1
        ];
        if (versions.isEmpty()) {
            throw new ESignException(
                'DOCUMENT_ERROR:No ContentVersion found for document ' + req.contentDocumentId
            );
        }
        return versions[0].Id;
    }
}
