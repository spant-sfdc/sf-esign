/**
 * Controller for the public SignDocument Visualforce page.
 *
 * Security model:
 *  - `without sharing` — token is the sole access key; sharing rules don't apply.
 *  - This controller performs NO DML. All state changes (Viewed, Signed, Declined)
 *    are delegated to ESignSigningQueueable, which runs in system context and
 *    holds the AllowsCallouts interface for the PDF stamp service.
 *  - Signature data (base64) is passed to the Queueable; it is never persisted
 *    directly from this class.
 *  - Rate limiting is enforced via a cache-backed counter per token.
 */
public without sharing class ESignDocumentController {

    // ─────────────────────────────────────────────────────────────────────────
    // VIEW STATE
    // ─────────────────────────────────────────────────────────────────────────

    public Signature_Request__c signRequest  { get; private set; }
    public String  errorCode                 { get; private set; }
    public String  documentBase64            { get; private set; }
    public String  pageState                 { get; private set; } // LOADING | SIGNING | COMPLETE | ERROR
    public Boolean isSubmitting              { get; set; }

    // Signer-supplied inputs (set by VF page via apex:inputHidden)
    public String signatureData       { get; set; } // base64 data-URI from canvas/upload
    public String signatureType       { get; set; } // Draw | Type | Upload
    public String declineReason       { get; set; }
    public String declineDescription  { get; set; }

    private String token;

    // ─────────────────────────────────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────────────────────────────────

    public ESignDocumentController() {
        token        = ApexPages.currentPage().getParameters().get('token');
        isSubmitting = false;
        pageState    = 'LOADING';
        System.debug(LoggingLevel.ERROR, '[CP-1] Controller constructed. token blank=' + String.isBlank(token));
        initialise();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INITIALISE (token validation + document load)
    // ─────────────────────────────────────────────────────────────────────────

    private void initialise() {
        try {
            if (String.isBlank(token)) {
                System.debug(LoggingLevel.ERROR, '[CP-2] FAIL: token is blank');
                errorCode = 'TOKEN_INVALID';
                pageState = 'ERROR';
                return;
            }
            System.debug(LoggingLevel.ERROR, '[CP-2] Token received: ' + ESignTokenService.maskToken(token));

            checkRateLimit();
            System.debug(LoggingLevel.ERROR, '[CP-3] Rate limit passed');

            signRequest = ESignTokenService.validateAndFetch(token);
            System.debug(LoggingLevel.ERROR,
                '[CP-4] Request fetched. Id=' + signRequest.Id
                + ' Status=' + signRequest.Status__c
                + ' ContentVersionId=' + signRequest.Content_Version_Id__c);

            try {
                if (String.isNotBlank(signRequest.Content_Version_Id__c)) {
                    documentBase64 = ESignDocumentService.getVersionBase64(
                        signRequest.Content_Version_Id__c);
                }
                System.debug(LoggingLevel.ERROR,
                    '[CP-5] documentBase64 length=' + (documentBase64 != null ? documentBase64.length() : 0));
            } catch (Exception docEx) {
                System.debug(LoggingLevel.ERROR,
                    '[CP-5] FAIL document preview: ' + docEx.getMessage());
            }

            try {
                if (signRequest.Status__c == 'Pending' || signRequest.Status__c == 'Viewed') {
                    System.enqueueJob(new ESignSigningQueueable(
                        ESignSigningQueueable.ACTION_VIEWED,
                        token, getClientIP(), getUserAgent()
                    ));
                    System.debug(LoggingLevel.ERROR, '[CP-6] Viewed queueable enqueued');
                }
            } catch (Exception qEx) {
                System.debug(LoggingLevel.ERROR, '[CP-6] FAIL Viewed enqueue: ' + qEx.getMessage());
            }

            pageState = 'SIGNING';
            System.debug(LoggingLevel.ERROR, '[CP-7] pageState=SIGNING');

        } catch (ESignException e) {
            System.debug(LoggingLevel.ERROR, '[CP-ERR] ESignException: ' + e.getMessage());
            String code = e.getMessage();
            if (code == 'TOKEN_MISSING' || String.isBlank(code)) { code = 'TOKEN_INVALID'; }
            else if (code.startsWith('DOCUMENT_ERROR')) { code = 'UNEXPECTED_ERROR'; }
            errorCode = code;
            pageState = 'ERROR';
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                '[CP-ERR] Unexpected: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            errorCode = 'UNEXPECTED_ERROR';
            pageState = 'ERROR';
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SUBMIT SIGNATURE
    // ─────────────────────────────────────────────────────────────────────────

    public PageReference submitSignature() {
        System.debug(LoggingLevel.ERROR, '[CP-8] submitSignature called. isSubmitting=' + isSubmitting);
        if (isSubmitting) return null;
        isSubmitting = true;

        try {
            signRequest = ESignTokenService.validateAndFetch(token);
            System.debug(LoggingLevel.ERROR,
                '[CP-9] Re-validated. sigDataBlank=' + String.isBlank(signatureData)
                + ' sigType=' + signatureType
                + ' sigDataLen=' + (signatureData != null ? signatureData.length() : 0));

            if (String.isBlank(signatureData) || String.isBlank(signatureType)) {
                ApexPages.addMessage(new ApexPages.Message(
                    ApexPages.Severity.ERROR,
                    'Please provide a signature before submitting.'));
                isSubmitting = false;
                return null;
            }

            System.enqueueJob(new ESignSigningQueueable(
                token, signatureData, signatureType,
                getClientIP(), getUserAgent()
            ));
            System.debug(LoggingLevel.ERROR, '[CP-10] Sign queueable enqueued');

            signRequest.Status__c = 'Signed';
            pageState = 'COMPLETE';
            System.debug(LoggingLevel.ERROR, '[CP-11] submitSignature complete. pageState=COMPLETE');

        } catch (ESignException e) {
            System.debug(LoggingLevel.ERROR, '[CP-ERR] submitSignature ESignException: ' + e.getMessage());
            errorCode    = e.getMessage();
            pageState    = 'ERROR';
            isSubmitting = false;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                '[CP-ERR] submitSignature Exception: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            errorCode    = 'UNEXPECTED_ERROR';
            pageState    = 'ERROR';
            isSubmitting = false;
        }
        return null;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DECLINE
    // ─────────────────────────────────────────────────────────────────────────

    public PageReference declineSignature() {
        System.debug(LoggingLevel.ERROR,
            '[CP-8D] declineSignature called. reason=' + declineReason
            + ' descBlank=' + String.isBlank(declineDescription));
        try {
            signRequest = ESignTokenService.validateAndFetch(token);
            System.debug(LoggingLevel.ERROR, '[CP-9D] Re-validated for decline');

            System.enqueueJob(new ESignSigningQueueable(
                ESignSigningQueueable.ACTION_DECLINE,
                token, declineReason, declineDescription,
                getClientIP(), getUserAgent()
            ));
            System.debug(LoggingLevel.ERROR, '[CP-10D] Decline queueable enqueued');

            signRequest.Status__c = 'Declined';
            pageState = 'COMPLETE';
            System.debug(LoggingLevel.ERROR, '[CP-11D] declineSignature complete');

        } catch (ESignException e) {
            System.debug(LoggingLevel.ERROR, '[CP-ERR] declineSignature ESignException: ' + e.getMessage());
            errorCode = e.getMessage();
            pageState = 'ERROR';
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                '[CP-ERR] declineSignature Exception: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            errorCode = 'UNEXPECTED_ERROR';
            pageState = 'ERROR';
        }
        return null;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RATE LIMITING
    // ─────────────────────────────────────────────────────────────────────────

    private void checkRateLimit() {
        if (String.isBlank(token)) return;

        Integer maxLoads = Integer.valueOf(System.Label.ESign_Rate_Limit_Per_Hour);
        String  cacheKey = 'local.ESign.' + token.substring(0, Math.min(20, token.length()));

        Integer loadCount = 0;
        try {
            Object cached = Cache.Session.get(cacheKey);
            loadCount = (cached != null) ? (Integer) cached : 0;
        } catch (Exception cacheEx) {
            return; // Session cache unavailable — fail open
        }

        if (loadCount >= maxLoads) {
            ESignAuditService.logRateLimit(null, null, token, getClientIP(), loadCount);
            throw new ESignException('RATE_LIMITED');
        }

        try {
            Cache.Session.put(cacheKey, loadCount + 1, 3600);
        } catch (Exception ignored) {}
    }

    // ─────────────────────────────────────────────────────────────────────────
    // HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    private String getClientIP() {
        return ApexPages.currentPage().getHeaders().get('X-Salesforce-SIP');
    }

    private String getUserAgent() {
        String ua = ApexPages.currentPage().getHeaders().get('USER-AGENT');
        return (ua != null && ua.length() > 255) ? ua.substring(0, 255) : ua;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CONVENIENCE BOOLEANS for VF rendered="" bindings
    // ─────────────────────────────────────────────────────────────────────────

    public Boolean isErrorState    { get { return pageState == 'ERROR'; } }
    public Boolean isSigningState  { get { return pageState == 'SIGNING'; } }
    public Boolean isCompleteState { get { return pageState == 'COMPLETE'; } }

    public Boolean isTokenInvalid   { get { return errorCode == 'TOKEN_INVALID'; } }
    public Boolean isTokenExpired   { get { return errorCode == 'TOKEN_EXPIRED'; } }
    public Boolean isAlreadySigned  { get { return errorCode == 'ALREADY_SIGNED'; } }
    public Boolean isDeclined       { get { return errorCode == 'REQUEST_DECLINED'; } }
    public Boolean isCancelled      { get { return errorCode == 'REQUEST_CANCELLED'; } }
    public Boolean isRateLimited    { get { return errorCode == 'RATE_LIMITED'; } }
    public Boolean isUnexpected     { get { return errorCode == 'UNEXPECTED_ERROR'; } }

    public Boolean isSignedComplete {
        get { return isCompleteState && signRequest?.Status__c == 'Signed'; }
    }
    public Boolean isDeclinedComplete {
        get { return isCompleteState && signRequest?.Status__c == 'Declined'; }
    }

    // Expose token to the VF page for use in JS remoting calls on the success screen.
    // The token is already in the browser URL, so exposing it here adds no new surface.
    public String signingToken { get { return token; } }

    // ─────────────────────────────────────────────────────────────────────────
    // REMOTE ACTIONS — called from SignDocument.page success screen JavaScript
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Polls for signing completion. Returns signing data for PDF generation once
     * the ESignSigningQueueable has run (Status = Signed AND Signature_Image_Id__c set).
     * Returns { ready: false } until then; { ready: false, alreadyDone: true } if a
     * signed PDF was already generated (idempotency).
     */
    @RemoteAction
    public static Map<String, Object> pollSigningData(String token) {
        try {
            if (String.isBlank(token)) return new Map<String, Object>{ 'ready' => false };
            List<Signature_Request__c> reqs = Database.queryWithBinds(
                'SELECT Id, Status__c, Name, Recipient_Name__c,'
                + ' Signer_Email__c, Recipient_Email__c, Signed_DateTime__c,'
                + ' Signature_Type__c, Signing_IP__c, Content_Version_Id__c,'
                + ' Signature_Image_Id__c, Related_Record_Id__c, Signed_Document_Id__c'
                + ' FROM Signature_Request__c WHERE Secure_Token__c = :tok LIMIT 1',
                new Map<String, Object>{ 'tok' => token },
                AccessLevel.SYSTEM_MODE
            );
            if (reqs.isEmpty()) return new Map<String, Object>{ 'ready' => false };
            Signature_Request__c req = reqs[0];

            if (String.isNotBlank(req.Signed_Document_Id__c)) {
                return new Map<String, Object>{ 'ready' => false, 'alreadyDone' => true };
            }
            if (req.Status__c != 'Signed' || String.isBlank(req.Signature_Image_Id__c)) {
                return new Map<String, Object>{ 'ready' => false };
            }

            // Fetch original document bytes (≤ 10 MB)
            String originalBase64 = null;
            String originalType   = null;
            if (String.isNotBlank(req.Content_Version_Id__c)) {
                List<ContentVersion> cvs = Database.queryWithBinds(
                    'SELECT VersionData, ContentSize, FileType FROM ContentVersion'
                    + ' WHERE Id = :cvId LIMIT 1',
                    new Map<String, Object>{ 'cvId' => req.Content_Version_Id__c },
                    AccessLevel.SYSTEM_MODE
                );
                if (!cvs.isEmpty() && cvs[0].VersionData != null
                        && cvs[0].ContentSize != null && cvs[0].ContentSize <= 10485760) {
                    originalBase64 = EncodingUtil.base64Encode(cvs[0].VersionData);
                    originalType   = cvs[0].FileType;
                }
            }

            // Fetch signature image bytes (≤ 512 KB)
            String sigImageBase64 = null;
            List<ContentVersion> sigCvs = Database.queryWithBinds(
                'SELECT VersionData, ContentSize FROM ContentVersion'
                + ' WHERE ContentDocumentId = :docId AND IsLatest = true LIMIT 1',
                new Map<String, Object>{ 'docId' => req.Signature_Image_Id__c },
                AccessLevel.SYSTEM_MODE
            );
            if (!sigCvs.isEmpty() && sigCvs[0].VersionData != null
                    && sigCvs[0].ContentSize != null && sigCvs[0].ContentSize <= 524288) {
                sigImageBase64 = EncodingUtil.base64Encode(sigCvs[0].VersionData);
            }

            String signerEmail = String.isNotBlank(req.Signer_Email__c)
                ? req.Signer_Email__c : req.Recipient_Email__c;
            String signedAt = req.Signed_DateTime__c != null
                ? req.Signed_DateTime__c.format('dd MMMM yyyy HH:mm z') : null;

            System.debug(LoggingLevel.INFO,
                '[VF-POLL] Data ready. reqId=' + req.Id
                + ' originalType=' + originalType
                + ' origSize=' + (originalBase64 != null ? originalBase64.length() : 0)
                + ' sigImgSize=' + (sigImageBase64 != null ? sigImageBase64.length() : 0));

            // Mark Processing before returning data — ensures status is tracked
            // even if the tab closes before the client can call updatePdfStatus.
            try {
                Database.update(new Signature_Request__c(
                    Id                       = req.Id,
                    PDF_Generation_Status__c = 'Processing'
                ), AccessLevel.SYSTEM_MODE);
            } catch (Exception updateEx) {
                System.debug(LoggingLevel.WARN,
                    '[VF-POLL] Could not set Processing status: ' + updateEx.getMessage());
            }

            return new Map<String, Object>{
                'ready'          => true,
                'reqId'          => req.Id,
                'reqName'        => req.Name,
                'signerName'     => req.Recipient_Name__c,
                'signerEmail'    => signerEmail,
                'signedDateTime' => signedAt,
                'sigMethod'      => req.Signature_Type__c,
                'ipAddress'      => req.Signing_IP__c,
                'originalBase64' => originalBase64,
                'originalType'   => originalType,
                'sigImageBase64' => sigImageBase64
            };
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[VF-POLL] Error: ' + e.getMessage());
            return new Map<String, Object>{ 'ready' => false };
        }
    }

    /**
     * Saves the client-generated signed PDF, links it to both the Signature Request and
     * its related record, updates Signed_Document_Id__c, and enqueues the confirmation email.
     * Idempotent: returns the existing contentDocId if already saved.
     */
    @RemoteAction
    public static Map<String, Object> savePdfAndNotify(
            String token, String base64Pdf, String fileName) {
        String failReqId = null; // captured early so the catch block can mark Failed
        try {
            if (String.isBlank(token) || String.isBlank(base64Pdf)) {
                throw new ESignException('VALIDATION_ERROR:Missing required parameters');
            }
            List<Signature_Request__c> reqs = Database.queryWithBinds(
                'SELECT Id, Status__c, Name, Related_Record_Id__c, Signed_Document_Id__c,'
                + ' Recipient_Email__c, Signer_Email__c, Recipient_Name__c, Signed_DateTime__c'
                + ' FROM Signature_Request__c WHERE Secure_Token__c = :tok LIMIT 1',
                new Map<String, Object>{ 'tok' => token },
                AccessLevel.SYSTEM_MODE
            );
            if (reqs.isEmpty()) throw new ESignException('VALIDATION_ERROR:Request not found');
            Signature_Request__c req = reqs[0];
            failReqId = req.Id;

            if (req.Status__c != 'Signed') {
                throw new ESignException('VALIDATION_ERROR:Request is not in Signed status');
            }
            if (String.isNotBlank(req.Signed_Document_Id__c)) {
                return new Map<String, Object>{ 'contentDocId' => req.Signed_Document_Id__c };
            }

            // Save PDF to Files
            String contentDocId = PdfStorageService.savePdf(
                base64Pdf, String.isNotBlank(fileName) ? fileName : 'SignedDocument', req.Id);
            base64Pdf = null; // release heap

            PdfStorageService.linkDocument(contentDocId, req.Id);
            if (String.isNotBlank(req.Related_Record_Id__c)) {
                PdfStorageService.linkDocument(contentDocId, req.Related_Record_Id__c);
            }

            req.Signed_Document_Id__c    = contentDocId;
            req.PDF_Generation_Status__c = 'Complete';
            req.PDF_Generation_Error__c  = null;
            // Confirmation email is triggered by the AFTER UPDATE trigger on
            // Signed_Document_Id__c transition (null → value). No enqueue here.
            Database.update(req, AccessLevel.SYSTEM_MODE);

            System.debug(LoggingLevel.ERROR,
                '[VF-SAVE] Complete. contentDocId=' + contentDocId + ' reqId=' + req.Id
                + ' — trigger will handle confirmation email.');
            return new Map<String, Object>{ 'contentDocId' => contentDocId };

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                '[VF-SAVE] Error: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            if (failReqId != null) {
                try {
                    Database.update(new Signature_Request__c(
                        Id                       = failReqId,
                        PDF_Generation_Status__c = 'Failed',
                        PDF_Generation_Error__c  = (e.getMessage() + '\n' + e.getStackTraceString())
                                                   .left(32768)
                    ), AccessLevel.SYSTEM_MODE);
                } catch (Exception statusEx) {
                    System.debug(LoggingLevel.ERROR,
                        '[VF-SAVE] Could not mark Failed status: ' + statusEx.getMessage());
                }
            }
            throw e;
        }
    }

    /**
     * Fire-and-forget status update called by SignDocument.page JS at each generation stage.
     * Provides server-side visibility into client-side generation progress and failures.
     */
    @RemoteAction
    public static void updatePdfStatus(String token, String status, String errorDetail) {
        try {
            if (String.isBlank(token) || String.isBlank(status)) return;
            List<Signature_Request__c> reqs = Database.queryWithBinds(
                'SELECT Id FROM Signature_Request__c WHERE Secure_Token__c = :tok LIMIT 1',
                new Map<String, Object>{ 'tok' => token },
                AccessLevel.SYSTEM_MODE
            );
            if (reqs.isEmpty()) return;
            Signature_Request__c req = new Signature_Request__c(Id = reqs[0].Id);
            req.PDF_Generation_Status__c = status;
            if (String.isNotBlank(errorDetail)) {
                req.PDF_Generation_Error__c = errorDetail.left(32768);
            } else if (status != 'Failed') {
                req.PDF_Generation_Error__c = null;
            }
            Database.update(req, AccessLevel.SYSTEM_MODE);
            System.debug(LoggingLevel.INFO, '[VF-STATUS] Updated to: ' + status);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                '[VF-STATUS] Update failed: ' + e.getMessage());
        }
    }

    public String documentUrl {
        get {
            if (signRequest != null && String.isNotBlank(signRequest.Document_Id__c)) {
                return '/sfc/servlet.shepherd/document/download/'
                       + signRequest.Document_Id__c
                       + '?operationContext=DELIVERY';
            }
            return null;
        }
    }
}
