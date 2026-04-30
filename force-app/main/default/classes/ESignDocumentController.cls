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
    public String signatureData  { get; set; } // base64 data-URI from canvas/upload
    public String signatureType  { get; set; } // Draw | Type | Upload

    private String token;

    // ─────────────────────────────────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────────────────────────────────

    public ESignDocumentController() {
        token        = ApexPages.currentPage().getParameters().get('token');
        isSubmitting = false;
        pageState    = 'LOADING';
        initialise();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INITIALISE (token validation + document load)
    // ─────────────────────────────────────────────────────────────────────────

    private void initialise() {
        try {
            checkRateLimit();

            signRequest    = ESignTokenService.validateAndFetch(token);
            documentBase64 = ESignDocumentService.getVersionBase64(
                signRequest.Content_Version_Id__c);

            // Mark Viewed / update last-accessed via Queueable (no guest DML)
            if (signRequest.Status__c == 'Pending' || signRequest.Status__c == 'Viewed') {
                System.enqueueJob(new ESignSigningQueueable(
                    ESignSigningQueueable.ACTION_VIEWED,
                    token, getClientIP(), getUserAgent()
                ));
            }

            pageState = 'SIGNING';

        } catch (ESignException e) {
            errorCode = e.getMessage();
            pageState = 'ERROR';
        } catch (Exception e) {
            errorCode = 'UNEXPECTED_ERROR';
            pageState = 'ERROR';
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SUBMIT SIGNATURE
    // ─────────────────────────────────────────────────────────────────────────

    public PageReference submitSignature() {
        if (isSubmitting) return null;
        isSubmitting = true;

        try {
            // Re-validate token (read-only) — prevents replay attacks
            signRequest = ESignTokenService.validateAndFetch(token);

            if (String.isBlank(signatureData) || String.isBlank(signatureType)) {
                ApexPages.addMessage(new ApexPages.Message(
                    ApexPages.Severity.ERROR,
                    'Please provide a signature before submitting.'));
                isSubmitting = false;
                return null;
            }

            // Delegate all DML + file creation to Queueable
            System.enqueueJob(new ESignSigningQueueable(
                token, signatureData, signatureType,
                getClientIP(), getUserAgent()
            ));

            // Optimistically update in-memory state for VF rendered="" bindings
            signRequest.Status__c = 'Signed';
            pageState = 'COMPLETE';

        } catch (ESignException e) {
            errorCode    = e.getMessage();
            pageState    = 'ERROR';
            isSubmitting = false;
        } catch (Exception e) {
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
        try {
            signRequest = ESignTokenService.validateAndFetch(token);

            System.enqueueJob(new ESignSigningQueueable(
                ESignSigningQueueable.ACTION_DECLINE,
                token, getClientIP(), getUserAgent()
            ));

            signRequest.Status__c = 'Declined';
            pageState = 'COMPLETE';

        } catch (ESignException e) {
            errorCode = e.getMessage();
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
}
