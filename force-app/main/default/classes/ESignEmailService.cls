/**
 * Handles all outbound email dispatch for SF-eSign.
 *
 * Design decisions:
 *  - Uses SingleEmailMessage for direct control over recipient, template, and object.
 *  - Template developer names are constants here; no dynamic lookup.
 *  - Reminder cap is enforced before dispatch: see sendReminder().
 *  - All dispatches log to audit trail regardless of outcome.
 *  - Runs with sharing to respect org-level email limits (not guest context).
 */
public with sharing class ESignEmailService {

    private static final String TEMPLATE_SIGNING_REQUEST = 'ESign_SigningRequest';
    private static final String TEMPLATE_REMINDER        = 'ESign_ReminderEmail';

    // ─────────────────────────────────────────────────────────────────────────
    // INITIAL SIGNING REQUEST EMAIL
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Sends the initial signing request email.
     * Called by ESignService.createSignatureRequest() immediately after insert.
     */
    public static void sendSigningRequest(Signature_Request__c req) {
        Id templateId = resolveTemplateId(TEMPLATE_SIGNING_REQUEST);

        Messaging.SingleEmailMessage mail = buildMail(
            req.Recipient_Email__c,
            req.Recipient_Name__c,
            req.Id,
            templateId
        );

        sendWithAudit(mail, req, 'Email_Sent');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // REMINDER EMAIL
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Sends a reminder email if the request is still active and
     * under the maximum reminder cap defined by ESign_Max_Reminders label.
     */
    public static void sendReminder(Signature_Request__c req) {
        Integer maxReminders = Integer.valueOf(System.Label.ESign_Max_Reminders);

        if (!new Set<String>{'Pending','Viewed'}.contains(req.Status__c)) {
            return; // Terminal state — no reminder needed
        }

        Integer sentCount = (req.Reminder_Sent_Count__c == null)
            ? 0 : Integer.valueOf(req.Reminder_Sent_Count__c);

        if (sentCount >= maxReminders) {
            ESignAuditService.log(req.Id, 'Error', req.Recipient_Email__c,
                req.Secure_Token__c, null, null, 'EmailService');
            return;
        }

        Id templateId = resolveTemplateId(TEMPLATE_REMINDER);
        Messaging.SingleEmailMessage mail = buildMail(
            req.Recipient_Email__c,
            req.Recipient_Name__c,
            req.Id,
            templateId
        );

        Boolean sent = sendWithAudit(mail, req, 'Reminder_Sent');

        if (sent) {
            req.Reminder_Sent_Count__c = sentCount + 1;
            req.Last_Reminder_Sent__c  = DateTime.now();
            update req;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INTERNAL HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    private static Messaging.SingleEmailMessage buildMail(
            String toEmail,
            String toName,
            String whatId,
            Id templateId) {

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ toEmail });
        mail.setTemplateId(templateId);
        mail.setWhatId(whatId);                          // Binds {!relatedTo.*} merge fields
        mail.setTargetObjectId(UserInfo.getUserId());    // Required by Salesforce for template merge resolution
        mail.setSaveAsActivity(false);                   // Avoid Activity overhead on custom object
        mail.setTreatTargetObjectAsRecipient(false);     // Email goes to toAddresses, not the target user

        // Use a no-reply org-wide address if available; falls back to running user
        List<OrgWideEmailAddress> owas = [
            SELECT Id FROM OrgWideEmailAddress
            WHERE  DisplayName = :System.Label.ESign_Org_Display_Name
            LIMIT  1
        ];
        if (!owas.isEmpty()) {
            mail.setOrgWideEmailAddressId(owas[0].Id);
        }

        return mail;
    }

    /**
     * Dispatches email and logs audit event.
     * Throws ESignException if the send fails so callers can surface the error.
     * Returns true on success.
     */
    private static Boolean sendWithAudit(
            Messaging.SingleEmailMessage mail,
            Signature_Request__c req,
            String auditEventType) {

        try {
            // allOrNone=false so we can inspect the result without a thrown exception
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(
                new List<Messaging.SingleEmailMessage>{ mail }, false
            );

            if (results.isEmpty() || !results[0].isSuccess()) {
                String errDetail = (!results.isEmpty() && !results[0].getErrors().isEmpty())
                    ? results[0].getErrors()[0].getMessage()
                    : 'Unknown send error — check org email deliverability settings (Setup > Deliverability)';
                throw new ESignException('EMAIL_SEND_ERROR:' + errDetail);
            }

            ESignAuditService.log(
                req.Id, auditEventType, req.Recipient_Email__c,
                req.Secure_Token__c, null, null, 'EmailService'
            );
            return true;

        } catch (ESignException e) {
            ESignAuditService.logError(
                req.Id, e.getMessage(),
                req.Recipient_Email__c, req.Secure_Token__c, 'EmailService'
            );
            throw e; // re-throw so ESignService can fail the overall request
        } catch (Exception e) {
            ESignAuditService.logError(
                req.Id, 'Email dispatch failed: ' + e.getMessage(),
                req.Recipient_Email__c, req.Secure_Token__c, 'EmailService'
            );
            throw new ESignException('EMAIL_SEND_ERROR:' + e.getMessage());
        }
    }

    private static Id resolveTemplateId(String developerName) {
        List<EmailTemplate> templates = [
            SELECT Id FROM EmailTemplate
            WHERE  DeveloperName = :developerName
            LIMIT  1
        ];
        if (templates.isEmpty()) {
            throw new ESignException(
                'EMAIL_ERROR:Email template not found: ' + developerName
            );
        }
        return templates[0].Id;
    }
}
