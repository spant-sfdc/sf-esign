trigger SignatureRequestAfterUpdate on Signature_Request__c (after update) {
    List<Signature_Request__c> pdfQualifying   = new List<Signature_Request__c>();
    List<Signature_Request__c> emailQualifying = new List<Signature_Request__c>();

    for (Signature_Request__c rec : Trigger.new) {
        Signature_Request__c oldRec = Trigger.oldMap.get(rec.Id);

        // PDF generation: Status just changed to Signed
        if (rec.Status__c == 'Signed' && oldRec.Status__c != 'Signed') {
            pdfQualifying.add(rec);
        }

        // Confirmation email: Signed_Document_Id__c just populated on a Signed record.
        // Change-detection (old == null, new != null) guarantees the signed PDF exists
        // and is committed before the queueable fetches it — this condition can only
        // be true once per record lifetime.
        if (rec.Status__c == 'Signed'
                && rec.Signed_Document_Id__c != null
                && oldRec.Signed_Document_Id__c == null
                && rec.Confirmation_Email_Status__c != 'Sent') {
            System.debug(LoggingLevel.ERROR,
                '[EMAIL-TRIGGER-2] Email condition matched.'
                + ' reqId=' + rec.Id
                + ' Signed_Document_Id__c=' + rec.Signed_Document_Id__c
                + ' old_Signed_Document_Id__c=' + oldRec.Signed_Document_Id__c
                + ' Confirmation_Email_Status__c=' + rec.Confirmation_Email_Status__c);
            emailQualifying.add(rec);
        }
    }

    if (!pdfQualifying.isEmpty()) {
        ESignSignedDocumentService.generateSignedDocuments(pdfQualifying);
    }
    if (!emailQualifying.isEmpty()) {
        ESignConfirmationEmailService.enqueueConfirmationEmails(emailQualifying);
    }
}
