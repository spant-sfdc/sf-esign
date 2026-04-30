/**
 * Input DTO for ESignService.createSignatureRequest().
 * Deliberately generic — callers pass a ContentDocumentId
 * from any source. No DocGen-specific fields.
 */
public class ESignRequest {

    /** ContentDocumentId of the document to send for signing. Required. */
    public String contentDocumentId   { get; set; }

    /** Specific ContentVersionId to pin. Optional — latest version resolved if blank. */
    public String contentVersionId    { get; set; }

    /** Signer email address. Required. */
    public String recipientEmail      { get; set; }

    /** Signer display name used in emails and signing page. Optional. */
    public String recipientName       { get; set; }

    /** Id of any Salesforce record to associate the signed document with. Optional. */
    public String relatedRecordId     { get; set; }

    /** API name of the SObject for relatedRecordId (e.g. 'Opportunity'). Optional. */
    public String relatedObjectType   { get; set; }

    /** Plain-text message displayed on the signing page and in the email. Optional. */
    public String messageToSigner     { get; set; }

    /** Token validity window in hours. Defaults to label ESign_Token_Expiry_Hours_Default. */
    public Integer expiryHours        { get; set; }

    /**
     * Identifies the calling system for audit purposes.
     * Examples: 'DocGen', 'LWC', 'API', 'Manual'.
     */
    public String sourceSystem        { get; set; }

    public ESignRequest() {
        this.expiryHours  = Integer.valueOf(System.Label.ESign_Token_Expiry_Hours_Default);
        this.sourceSystem = 'API';
    }

    /**
     * Validates required fields and basic format.
     * Throws ESignException(VALIDATION_ERROR) on the first failure found.
     */
    public void validate() {
        if (String.isBlank(contentDocumentId)) {
            throw new ESignException('VALIDATION_ERROR:contentDocumentId is required');
        }
        if (String.isBlank(recipientEmail)) {
            throw new ESignException('VALIDATION_ERROR:recipientEmail is required');
        }
        if (!recipientEmail.contains('@') || !recipientEmail.contains('.')) {
            throw new ESignException('VALIDATION_ERROR:recipientEmail is not a valid address');
        }
        if (expiryHours == null || expiryHours < 1 || expiryHours > 720) {
            throw new ESignException('VALIDATION_ERROR:expiryHours must be between 1 and 720');
        }
    }
}
