/**
 * Sends the signed-document confirmation email with the signed PDF attached.
 *
 * Enqueued by ESignDocumentController.savePdfAndNotify after the PDF is saved
 * to Salesforce Files. Running async keeps the RemoteAction heap below the
 * synchronous 6 MB limit when the original document is large.
 *
 * Updates Confirmation_Email_Status__c to Sent/Failed so admins can monitor
 * delivery without checking debug logs.
 */
public without sharing class ESignConfirmationEmailQueueable implements Queueable {

    private final String reqId;
    private final String contentDocId;

    public ESignConfirmationEmailQueueable(String reqId, String contentDocId) {
        this.reqId        = reqId;
        this.contentDocId = contentDocId;
    }

    public void execute(QueueableContext ctx) {
        System.debug(LoggingLevel.ERROR,
            '[EMAIL-Q1] execute START. reqId=' + reqId + ' contentDocId=' + contentDocId
            + ' jobId=' + ctx.getJobId());

        try {
            // ── Fetch Signature Request ────────────────────────────────────────
            List<Signature_Request__c> reqs = Database.queryWithBinds(
                'SELECT Id, Name, Recipient_Name__c, Signer_Email__c,'
                + ' Recipient_Email__c, Signed_DateTime__c'
                + ' FROM Signature_Request__c WHERE Id = :rId LIMIT 1',
                new Map<String, Object>{ 'rId' => reqId },
                AccessLevel.SYSTEM_MODE
            );
            if (reqs.isEmpty()) {
                System.debug(LoggingLevel.ERROR,
                    '[EMAIL-Q2] Signature_Request__c not found. reqId=' + reqId);
                markFailed(reqId, 'Signature_Request__c not found: ' + reqId);
                return;
            }
            Signature_Request__c req = reqs[0];
            System.debug(LoggingLevel.ERROR,
                '[EMAIL-Q2] Request found. name=' + req.Name
                + ' signerEmail=' + req.Signer_Email__c
                + ' recipientEmail=' + req.Recipient_Email__c);

            // ── Fetch ContentVersion (PDF blob) ───────────────────────────────
            // ORDER BY VersionNumber DESC rather than IsLatest = true to guarantee
            // the highest version is returned even in edge cases where IsLatest
            // hasn't propagated within the same transaction window.
            List<ContentVersion> cvs = Database.queryWithBinds(
                'SELECT Id, VersionData, ContentSize, Title FROM ContentVersion'
                + ' WHERE ContentDocumentId = :cdId'
                + ' ORDER BY VersionNumber DESC LIMIT 1',
                new Map<String, Object>{ 'cdId' => contentDocId },
                AccessLevel.SYSTEM_MODE
            );
            if (cvs.isEmpty() || cvs[0].VersionData == null) {
                System.debug(LoggingLevel.ERROR,
                    '[EMAIL-Q3] ContentVersion not found or VersionData null.'
                    + ' contentDocId=' + contentDocId
                    + ' rowsReturned=' + cvs.size());
                markFailed(reqId, 'ContentVersion not found for contentDocId: ' + contentDocId);
                return;
            }
            Integer blobBytes = cvs[0].VersionData.size();
            System.debug(LoggingLevel.ERROR,
                '[EMAIL-Q3] ContentVersion found.'
                + ' cvId=' + cvs[0].Id
                + ' title=' + cvs[0].Title
                + ' ContentSize=' + cvs[0].ContentSize
                + ' blobBytes=' + blobBytes);
            if (blobBytes == 0) {
                System.debug(LoggingLevel.ERROR,
                    '[EMAIL-Q3-FAIL] VersionData blob is zero bytes. Aborting.'
                    + ' contentDocId=' + contentDocId);
                markFailed(reqId, 'VersionData is zero bytes for contentDocId: ' + contentDocId);
                return;
            }

            // Clear any previous error before attempting send
            Database.update(new Signature_Request__c(
                Id                          = reqId,
                Confirmation_Email_Error__c = null
            ), AccessLevel.SYSTEM_MODE);

            // ── Send email ────────────────────────────────────────────────────
            System.debug(LoggingLevel.ERROR,
                '[EMAIL-Q3-SEND] Passing blob to sendSignedConfirmation.'
                + ' blobBytes=' + blobBytes + ' recipient='
                + (String.isNotBlank(req.Signer_Email__c)
                    ? req.Signer_Email__c : req.Recipient_Email__c));
            ESignEmailService.sendSignedConfirmation(req, cvs[0].VersionData, cvs[0].Title);

            // ── Mark Sent ─────────────────────────────────────────────────────
            Database.update(new Signature_Request__c(
                Id                              = reqId,
                Confirmation_Email_Status__c    = 'Sent',
                Confirmation_Email_Error__c     = null
            ), AccessLevel.SYSTEM_MODE);
            System.debug(LoggingLevel.ERROR,
                '[EMAIL-Q4] Confirmation email SENT and status marked Sent. reqId=' + reqId);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                '[EMAIL-Q4-FAIL] Exception: ' + e.getMessage()
                + ' | ' + e.getStackTraceString());
            markFailed(reqId, (e.getMessage() + '\n' + e.getStackTraceString()).left(32768));
        }
    }

    private static void markFailed(String rId, String detail) {
        if (String.isBlank(rId)) return;
        try {
            Database.update(new Signature_Request__c(
                Id                           = rId,
                Confirmation_Email_Status__c = 'Failed',
                Confirmation_Email_Error__c  = detail
            ), AccessLevel.SYSTEM_MODE);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                '[EMAIL-Q-MARKFAIL] Could not write Failed status: ' + ex.getMessage());
        }
    }
}
