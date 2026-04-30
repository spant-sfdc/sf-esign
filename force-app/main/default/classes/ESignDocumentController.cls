/**
 * Controller for the public SignDocument Visualforce page.
 *
 * Security notes:
 *  - Declared `without sharing` because the Guest User has no access to
 *    Signature_Request__c records. The token is the sole access key.
 *  - All record queries are performed via ESignRequestSelector which
 *    uses explicit field lists — no SOQL injection is possible.
 *  - Rate limiting is enforced via a cache-backed counter per token.
 *  - All state changes (Viewed, Signed, Declined) are applied in this
 *    controller; no client-supplied values are trusted for status.
 *  - Signature data is accepted as a base64 data-URI and decoded server-side.
 *
 * Phase coverage: Phase 5 (page load, preview, error states)
 *                 Phase 6 (submit: signature save, signed document, status update)
 *                 Phase 10 (rate limiting, duplicate-submit prevention)
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
        token       = ApexPages.currentPage().getParameters().get('token');
        isSubmitting = false;
        pageState   = 'LOADING';
        initialise();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INITIALISE (token validation + document load)
    // ─────────────────────────────────────────────────────────────────────────

    private void initialise() {
        try {
            // Phase 10: rate limit check before any record fetch
            checkRateLimit();

            signRequest   = ESignTokenService.validateAndFetch(token);
            documentBase64 = ESignDocumentService.getVersionBase64(
                signRequest.Content_Version_Id__c);

            // Mark as Viewed on first load
            if (signRequest.Status__c == 'Pending') {
                signRequest.Status__c     = 'Viewed';
                signRequest.Last_Accessed__c = DateTime.now();
                Database.update(signRequest, AccessLevel.SYSTEM_MODE);
                ESignAuditService.log(
                    signRequest.Id, 'Viewed',
                    signRequest.Recipient_Email__c, token,
                    getClientIP(), getUserAgent(), 'Site'
                );
            } else if (signRequest.Status__c == 'Viewed') {
                signRequest.Last_Accessed__c = DateTime.now();
                Database.update(signRequest, AccessLevel.SYSTEM_MODE);
            }

            pageState = 'SIGNING';

        } catch (ESignException e) {
            errorCode = e.getMessage();
            pageState = 'ERROR';
        } catch (Exception e) {
            ESignAuditService.logError(null, e.getMessage(), null, token, 'Site');
            errorCode = 'UNEXPECTED_ERROR';
            pageState = 'ERROR';
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SUBMIT SIGNATURE (Phase 6)
    // ─────────────────────────────────────────────────────────────────────────

    public PageReference submitSignature() {
        // Prevent double-submission from browser refresh
        if (isSubmitting) return null;
        isSubmitting = true;

        try {
            // Re-validate token — prevents replay on expired/cancelled requests
            signRequest = ESignTokenService.validateAndFetch(token);

            // Validate signature data supplied by signer
            if (String.isBlank(signatureData) || String.isBlank(signatureType)) {
                ApexPages.addMessage(new ApexPages.Message(
                    ApexPages.Severity.ERROR,
                    'Please provide a signature before submitting.'));
                isSubmitting = false;
                return null;
            }

            // Decode signature image from base64 data-URI
            Blob sigBlob = decodeSignatureBlob(signatureData);

            // Save signature image as ContentDocument
            String sigImageDocId = ESignDocumentService.saveSignatureImage(
                signRequest.Name, sigBlob);

            // Update request to Signed state
            signRequest.Status__c          = 'Signed';
            signRequest.Signed_DateTime__c = DateTime.now();
            signRequest.Signer_Email__c    = signRequest.Recipient_Email__c;
            signRequest.Signature_Type__c  = signatureType;
            signRequest.Signing_IP__c      = getClientIP();
            signRequest.Signer_User_Agent__c = getUserAgent();
            signRequest.Signature_Image_Id__c = sigImageDocId;
            Database.update(signRequest, AccessLevel.SYSTEM_MODE);

            // Create signed document version (Tier 1 + optional Tier 2 stamp)
            String signedDocId = ESignDocumentService.createSignedVersion(
                signRequest, sigBlob);

            // Store signed document id on request
            signRequest.Signed_Document_Id__c = signedDocId;
            Database.update(signRequest, AccessLevel.SYSTEM_MODE);

            // Audit: Signed
            ESignAuditService.log(
                signRequest.Id, 'Signed',
                signRequest.Signer_Email__c, token,
                getClientIP(), getUserAgent(), 'Site'
            );

            pageState = 'COMPLETE';

        } catch (ESignException e) {
            errorCode    = e.getMessage();
            pageState    = 'ERROR';
            isSubmitting = false;
        } catch (Exception e) {
            ESignAuditService.logError(
                signRequest?.Id, e.getMessage(),
                signRequest?.Recipient_Email__c, token, 'Site');
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
            signRequest.Status__c = 'Declined';
            Database.update(signRequest, AccessLevel.SYSTEM_MODE);
            ESignAuditService.log(
                signRequest.Id, 'Declined',
                signRequest.Recipient_Email__c, token,
                getClientIP(), getUserAgent(), 'Site'
            );
            pageState = 'COMPLETE';
        } catch (ESignException e) {
            errorCode = e.getMessage();
            pageState = 'ERROR';
        }
        return null;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RATE LIMITING (Phase 10)
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
            // Session cache unavailable — fail open (don't block signer)
            return;
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

    private Blob decodeSignatureBlob(String dataUri) {
        // dataUri format: "data:image/png;base64,<base64data>"
        String base64Part = dataUri.contains(',')
            ? dataUri.substringAfter(',')
            : dataUri;
        try {
            return EncodingUtil.base64Decode(base64Part);
        } catch (Exception e) {
            throw new ESignException('VALIDATION_ERROR:Invalid signature image data');
        }
    }

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
