public without sharing class ESignEmailService {

    // ─────────────────────────────────────────────────────────────────────────
    // PUBLIC API
    // ─────────────────────────────────────────────────────────────────────────

    public static void sendSigningRequest(Signature_Request__c req) {
        Messaging.SingleEmailMessage mail = buildSigningRequestMail(req);
        sendWithAudit(mail, req, 'Email_Sent');
    }

    /**
     * Sends a branded confirmation email to the signer with the signed PDF attached.
     * Called by ESignConfirmationEmailQueueable after the merged PDF has been saved.
     *
     * @param req          Signature_Request__c with fields: Name, Recipient_Name__c,
     *                     Signer_Email__c, Recipient_Email__c, Signed_DateTime__c
     * @param pdfBlob      Signed PDF bytes fetched from ContentVersion.VersionData
     * @param pdfFileName  File title used as the attachment name (no extension required)
     */
    public static void sendSignedConfirmation(
            Signature_Request__c req,
            Blob pdfBlob,
            String pdfFileName) {

        System.debug(LoggingLevel.ERROR,
            '[EMAIL-S1] sendSignedConfirmation START. reqId=' + req.Id
            + ' pdfSize=' + (pdfBlob != null ? pdfBlob.size() : 0)
            + ' pdfFileName=' + pdfFileName);

        String orgName     = System.Label.ESign_Org_Display_Name;
        String support     = System.Label.ESign_Support_Email;
        String signerEmail = String.isNotBlank(req.Signer_Email__c)
            ? req.Signer_Email__c : req.Recipient_Email__c;
        String greeting    = String.isNotBlank(req.Recipient_Name__c)
            ? 'Hello ' + req.Recipient_Name__c + ','
            : 'Hello,';
        String signedAt    = req.Signed_DateTime__c != null
            ? req.Signed_DateTime__c.format('dd MMMM yyyy HH:mm z') : 'N/A';

        String body =
              '<p style="color:#333;font-size:15px;line-height:1.6;margin:0 0 16px">'
            +     greeting + '</p>'
            + '<p style="color:#333;font-size:15px;line-height:1.6;margin:0 0 20px">'
            +   'Your document has been signed successfully. The signed PDF with its Signature '
            +   'Certificate is attached to this email for your records.</p>'
            + '<div style="background:#f3fbf0;border:1px solid #b0ddb0;border-radius:6px;'
            +   'padding:20px 24px;margin:0 0 24px">'
            +   '<table style="width:100%;border-collapse:collapse;font-size:14px">'
            +   '<tr><td style="color:#666;padding:5px 0;width:140px;vertical-align:top">'
            +       'Document</td>'
            +     '<td style="color:#222;font-weight:600;padding:5px 0">' + req.Name + '</td></tr>'
            + (String.isNotBlank(req.Recipient_Name__c)
                ? '<tr><td style="color:#666;padding:5px 0">Signed by</td>'
                + '<td style="color:#222;padding:5px 0">' + req.Recipient_Name__c + '</td></tr>'
                : '')
            +   '<tr><td style="color:#666;padding:5px 0">Signed at</td>'
            +     '<td style="color:#222;padding:5px 0">' + signedAt + '</td></tr>'
            +   '</table></div>'
            + '<p style="color:#555;font-size:13px;line-height:1.6;margin:0 0 8px">'
            +   'The signed PDF is attached to this email. It contains a Signature Certificate '
            +   'verifying the authenticity of the electronic signature.</p>'
            + '<hr style="border:none;border-top:1px solid #e5e5e5;margin:24px 0"/>'
            + '<p style="color:#888;font-size:12px;text-align:center;margin:0">'
            +   'Generated securely via SF-eSign &bull; ' + orgName + '</p>';

        String html = wrapHtml(orgName, 'Document Signed Successfully', body, support, req.Name);

        String safeName = (String.isNotBlank(pdfFileName) ? pdfFileName : req.Name)
            .replaceAll('[^a-zA-Z0-9 _\\-]', '').trim();
        if (!safeName.toLowerCase().endsWith('.pdf')) safeName += '.pdf';

        Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
        att.setFileName(safeName);
        att.setBody(pdfBlob);
        att.setContentType('application/pdf');

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ signerEmail });
        mail.setSubject('Document Signed Successfully — ' + req.Name);
        mail.setHtmlBody(html);
        mail.setFileAttachments(new List<Messaging.EmailFileAttachment>{ att });
        mail.setSaveAsActivity(false);
        applyOwa(mail);

        System.debug(LoggingLevel.ERROR,
            '[EMAIL-S2] Calling Messaging.sendEmail. toAddress=' + signerEmail
            + ' subject=Document Signed Successfully - ' + req.Name
            + ' orgWideAddressId=' + mail.getOrgWideEmailAddressId());

        try {
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(
                new List<Messaging.SingleEmailMessage>{ mail }, false
            );
            if (results.isEmpty() || !results[0].isSuccess()) {
                String err = (!results.isEmpty() && !results[0].getErrors().isEmpty())
                    ? results[0].getErrors()[0].getMessage()
                    : 'Unknown send error';
                System.debug(LoggingLevel.ERROR,
                    '[EMAIL-S2-FAIL] sendEmail returned failure. err=' + err);
                throw new ESignException('EMAIL_SEND_ERROR:' + err);
            }
            System.debug(LoggingLevel.ERROR,
                '[EMAIL-S3] sendEmail SUCCESS. reqId=' + req.Id + ' toAddress=' + signerEmail);
            ESignAuditService.log(
                req.Id, 'Signed_Confirmation_Sent', signerEmail, null, null, null, 'EmailService'
            );
        } catch (ESignException e) {
            System.debug(LoggingLevel.ERROR,
                '[EMAIL-S3-FAIL] ESignException: ' + e.getMessage());
            ESignAuditService.logError(req.Id, e.getMessage(), signerEmail, null, 'EmailService');
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                '[EMAIL-S3-FAIL] Unexpected exception: ' + e.getMessage()
                + ' | ' + e.getStackTraceString());
            throw new ESignException('EMAIL_SEND_ERROR:' + e.getMessage());
        }
    }

    public static void sendReminder(Signature_Request__c req) {
        Integer maxReminders = Integer.valueOf(System.Label.ESign_Max_Reminders);
        if (!new Set<String>{'Pending','Viewed'}.contains(req.Status__c)) return;
        Integer sentCount = req.Reminder_Sent_Count__c == null
            ? 0 : Integer.valueOf(req.Reminder_Sent_Count__c);
        if (sentCount >= maxReminders) {
            ESignAuditService.log(req.Id, 'Error', req.Recipient_Email__c,
                req.Secure_Token__c, null, null, 'EmailService');
            return;
        }
        Messaging.SingleEmailMessage mail = buildReminderMail(req);
        Boolean sent = sendWithAudit(mail, req, 'Reminder_Sent');
        if (sent) {
            req.Reminder_Sent_Count__c = sentCount + 1;
            req.Last_Reminder_Sent__c  = DateTime.now();
            update req;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EMAIL BUILDERS  (no setTemplateId / setWhatId / setTargetObjectId)
    // ─────────────────────────────────────────────────────────────────────────

    private static Messaging.SingleEmailMessage buildSigningRequestMail(
            Signature_Request__c req) {

        String baseUrl    = System.Label.ESign_Site_Base_URL;
        String orgName    = System.Label.ESign_Org_Display_Name;
        String support    = System.Label.ESign_Support_Email;
        String signingUrl = baseUrl + '/apex/SignDocument?token=' + req.Secure_Token__c;
        String caseUrl    = baseUrl + '/apex/RaiseCase?token='    + req.Secure_Token__c;
        String greeting   = String.isNotBlank(req.Recipient_Name__c)
            ? 'Hello ' + req.Recipient_Name__c + ','
            : 'Hello,';
        String expiry = req.Token_Expiry__c != null
            ? req.Token_Expiry__c.format() : '';
        String msgBox = String.isNotBlank(req.Message_to_Signer__c)
            ? '<div style="background:#f0f7ff;border-left:4px solid #0070d2;padding:14px 18px;'
              + 'border-radius:4px;margin-bottom:20px;font-size:14px;color:#1c4f82">'
              + req.Message_to_Signer__c + '</div>'
            : '';

        String body =
              '<p style="color:#333;font-size:15px;line-height:1.6;margin:0 0 16px">' + greeting + '</p>'
            + '<p style="color:#333;font-size:15px;line-height:1.6;margin:0 0 16px">'
            +   'You have received a document that requires your electronic signature.</p>'
            + msgBox
            + '<p style="color:#333;font-size:15px;line-height:1.6;margin:0 0 20px">'
            +   'Please click the button below to review and sign the document.'
            +   ' The link is secure and unique to you.</p>'
            + '<a href="' + signingUrl + '" style="display:block;width:fit-content;margin:0 auto 12px;'
            +   'background:#0070d2;color:#ffffff;text-decoration:none;padding:14px 36px;'
            +   'border-radius:6px;font-size:16px;font-weight:bold;text-align:center">'
            +   'Review &amp; Sign Document</a>'
            + (String.isNotBlank(expiry)
                ? '<p style="font-size:12px;color:#888;text-align:center;margin-top:8px">'
                  + 'This link expires on ' + expiry + '.</p>' : '')
            + '<hr style="border:none;border-top:1px solid #e5e5e5;margin:24px 0"/>'
            + '<p style="color:#333;font-size:15px;line-height:1.6;margin:0 0 8px">'
            +   'If you have questions or believe you received this in error:</p>'
            + '<a href="' + caseUrl + '" style="display:block;width:fit-content;margin:0 auto;'
            +   'color:#c23934;text-decoration:none;font-size:13px;text-align:center">'
            +   'Raise a Support Case</a>';

        String html = wrapHtml(orgName, 'Secure Electronic Signature Request',
            body, support, req.Name);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ req.Recipient_Email__c });
        mail.setSubject('Action Required: Please sign your document — ' + req.Name);
        mail.setHtmlBody(html);
        mail.setSaveAsActivity(false);
        applyOwa(mail);
        return mail;
    }

    private static Messaging.SingleEmailMessage buildReminderMail(
            Signature_Request__c req) {

        String baseUrl    = System.Label.ESign_Site_Base_URL;
        String orgName    = System.Label.ESign_Org_Display_Name;
        String support    = System.Label.ESign_Support_Email;
        String signingUrl = baseUrl + '/apex/SignDocument?token=' + req.Secure_Token__c;
        String greeting   = String.isNotBlank(req.Recipient_Name__c)
            ? 'Hello ' + req.Recipient_Name__c + ','
            : 'Hello,';
        String expiry = req.Token_Expiry__c != null
            ? req.Token_Expiry__c.format() : '';

        String body =
              '<p style="color:#333;font-size:15px;line-height:1.6;margin:0 0 16px">' + greeting + '</p>'
            + '<p style="color:#333;font-size:15px;line-height:1.6;margin:0 0 20px">'
            +   'This is a reminder that a document is still awaiting your electronic signature.</p>'
            + '<a href="' + signingUrl + '" style="display:block;width:fit-content;margin:0 auto 12px;'
            +   'background:#0070d2;color:#ffffff;text-decoration:none;padding:14px 36px;'
            +   'border-radius:6px;font-size:16px;font-weight:bold;text-align:center">'
            +   'Review &amp; Sign Document</a>'
            + (String.isNotBlank(expiry)
                ? '<p style="font-size:12px;color:#888;text-align:center;margin-top:8px">'
                  + 'This link expires on ' + expiry + '.</p>' : '');

        String html = wrapHtml(orgName, 'Reminder: Document Awaiting Your Signature',
            body, support, req.Name);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ req.Recipient_Email__c });
        mail.setSubject('Reminder: Please sign your document — ' + req.Name);
        mail.setHtmlBody(html);
        mail.setSaveAsActivity(false);
        applyOwa(mail);
        return mail;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INTERNAL HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    private static String wrapHtml(String orgName, String subtitle,
            String bodyContent, String supportEmail, String reqName) {
        return '<!DOCTYPE html><html><head><meta charset="UTF-8"/>'
            + '<meta name="viewport" content="width=device-width,initial-scale=1"/></head>'
            + '<body style="font-family:Arial,Helvetica,sans-serif;background:#f4f6f9;margin:0;padding:0">'
            + '<div style="max-width:600px;margin:32px auto;background:#ffffff;border-radius:8px;'
            +   'overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,.12)">'
            + '<div style="background:#0070d2;padding:28px 32px;text-align:center">'
            +   '<h1 style="color:#ffffff;font-size:22px;margin:0">' + orgName + '</h1>'
            +   '<p style="color:#cce3f6;font-size:13px;margin:6px 0 0">' + subtitle + '</p>'
            + '</div>'
            + '<div style="padding:32px">' + bodyContent + '</div>'
            + '<div style="background:#f4f6f9;padding:20px 32px;text-align:center;'
            +   'font-size:12px;color:#888">'
            +   '<p>This is an automated message from ' + orgName + '.</p>'
            +   '<p>Need help? Contact <a href="mailto:' + supportEmail
            +     '" style="color:#0070d2;text-decoration:none">' + supportEmail + '</a></p>'
            +   '<p>Request Reference: ' + reqName + '</p>'
            + '</div></div></body></html>';
    }

    private static void applyOwa(Messaging.SingleEmailMessage mail) {
        List<OrgWideEmailAddress> owas = [
            SELECT Id FROM OrgWideEmailAddress
            WHERE  DisplayName = :System.Label.ESign_Org_Display_Name
            LIMIT  1
        ];
        if (!owas.isEmpty()) {
            mail.setOrgWideEmailAddressId(owas[0].Id);
        }
    }

    private static Boolean sendWithAudit(
            Messaging.SingleEmailMessage mail,
            Signature_Request__c req,
            String auditEventType) {

        try {
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(
                new List<Messaging.SingleEmailMessage>{ mail }, false
            );
            if (results.isEmpty() || !results[0].isSuccess()) {
                String errDetail = (!results.isEmpty() && !results[0].getErrors().isEmpty())
                    ? results[0].getErrors()[0].getMessage()
                    : 'Unknown send error — verify Setup > Email > Deliverability is set to All Email';
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
            throw e;
        } catch (Exception e) {
            ESignAuditService.logError(
                req.Id, 'Email dispatch failed: ' + e.getMessage(),
                req.Recipient_Email__c, req.Secure_Token__c, 'EmailService'
            );
            throw new ESignException('EMAIL_SEND_ERROR:' + e.getMessage());
        }
    }
}
