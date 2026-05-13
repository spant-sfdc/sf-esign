/**
 * @deprecated HTML signed document generation removed.
 *
 * PDF generation has moved to the client-side PDF-LIB engine:
 *   c/eSignSignedPdfGenerator (LWC on the Signature_Request__c record page)
 *   → c/pdfGenerationEngine (PDF-LIB engine)
 *   → PdfGenerationController.savePdfWithLinks / updateSignedDocumentId
 *
 * This Queueable is enqueued by ESignSignedDocumentService but performs no
 * file generation. It exists to preserve the trigger → service → queueable
 * chain for backward compatibility without modifying the trigger.
 *
 * Safe to remove once the trigger and service are also cleaned up.
 */
public without sharing class ESignDocumentGenerationQueueable implements Queueable {

    private final String reqId;

    public ESignDocumentGenerationQueueable(String reqId) {
        this.reqId = reqId;
    }

    public void execute(QueueableContext ctx) {
        System.debug(LoggingLevel.INFO,
            '[ESDGQ] reqId=' + reqId
            + ' — PDF generation delegated to c/eSignSignedPdfGenerator LWC. No server-side action taken.');
    }
}
