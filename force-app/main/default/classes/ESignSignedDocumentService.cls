/**
 * Trigger-facing service called by SignatureRequestAfterUpdate.
 * Enqueues ESignDocumentGenerationQueueable per signing request so that
 * getContentAsPDF() (a callout) can run outside the trigger's DML transaction.
 *
 * processedIds guards against duplicate enqueue within a single transaction
 * (e.g. bulk updates where the same record appears multiple times).
 */
public without sharing class ESignSignedDocumentService {

    private static Set<Id> processedIds = new Set<Id>();

    public static void generateSignedDocuments(List<Signature_Request__c> reqs) {
        for (Signature_Request__c req : reqs) {
            if (processedIds.contains(req.Id)) continue;
            processedIds.add(req.Id);
            try {
                System.enqueueJob(new ESignDocumentGenerationQueueable(req.Id));
                System.debug(LoggingLevel.ERROR,
                    '[ESGD-ENQUEUE] Queued PDF generation for reqId=' + req.Id);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    '[ESGD-ERR] reqId=' + req.Id + ': ' + e.getMessage()
                    + ' | ' + e.getStackTraceString());
            }
        }
    }
}
