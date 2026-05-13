/**
 * Trigger-facing service called by SignatureRequestAfterUpdate when
 * Signed_Document_Id__c is first populated on a Signed record.
 *
 * Responsibilities:
 *   • Guard against duplicate enqueue in the same transaction via processedIds.
 *   • Enqueue ESignConfirmationEmailQueueable for each qualifying record.
 *   • Update Confirmation_Email_Status__c to Pending/Failed immediately so
 *     the outcome is visible on the record without opening debug logs.
 *
 * The DML update (Pending) re-fires the trigger, but the change-detection guard
 * (old.Signed_Document_Id__c == null) prevents re-entry for the email condition.
 */
public without sharing class ESignConfirmationEmailService {

    private static Set<Id> processedIds = new Set<Id>();

    public static void enqueueConfirmationEmails(List<Signature_Request__c> reqs) {
        List<Signature_Request__c> statusUpdates = new List<Signature_Request__c>();

        for (Signature_Request__c req : reqs) {
            if (processedIds.contains(req.Id)) continue;
            processedIds.add(req.Id);

            try {
                Id jobId = System.enqueueJob(
                    new ESignConfirmationEmailQueueable(req.Id, req.Signed_Document_Id__c));
                System.debug(LoggingLevel.ERROR,
                    '[EMAIL-TRIGGER-1] Queueable enqueued.'
                    + ' reqId=' + req.Id
                    + ' contentDocId=' + req.Signed_Document_Id__c
                    + ' jobId=' + jobId);
                statusUpdates.add(new Signature_Request__c(
                    Id                           = req.Id,
                    Confirmation_Email_Status__c = 'Pending',
                    Confirmation_Email_Error__c  = null
                ));
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    '[EMAIL-TRIGGER-1-FAIL] enqueueJob threw. reqId=' + req.Id
                    + ' error=' + e.getMessage()
                    + ' | ' + e.getStackTraceString());
                statusUpdates.add(new Signature_Request__c(
                    Id                           = req.Id,
                    Confirmation_Email_Status__c = 'Failed',
                    Confirmation_Email_Error__c  = ('Enqueue failed: '
                        + e.getMessage() + '\n' + e.getStackTraceString()).left(32768)
                ));
            }
        }

        if (!statusUpdates.isEmpty()) {
            // allowPartialSuccess = true so one bad record does not block others
            Database.update(statusUpdates, false, AccessLevel.SYSTEM_MODE);
        }
    }
}
