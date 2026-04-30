/**
 * Output DTO returned by ESignService.createSignatureRequest().
 * Serialisable to JSON for REST API callers.
 */
public class ESignResult {

    @AuraEnabled public Boolean success             { get; private set; }
    @AuraEnabled public String  signatureRequestId  { get; private set; }
    @AuraEnabled public String  signatureRequestName{ get; private set; }
    @AuraEnabled public String  token               { get; private set; }
    @AuraEnabled public String  signingUrl          { get; private set; }
    @AuraEnabled public String  raiseCaseUrl        { get; private set; }
    @AuraEnabled public String  errorMessage        { get; private set; }
    @AuraEnabled public String  errorCode           { get; private set; }

    private ESignResult() {}

    public static ESignResult ok(Signature_Request__c req) {
        String baseUrl = System.Label.ESign_Site_Base_URL;
        ESignResult r  = new ESignResult();
        r.success              = true;
        r.signatureRequestId   = req.Id;
        r.signatureRequestName = req.Name;
        r.token                = req.Secure_Token__c;
        r.signingUrl           = baseUrl + '/apex/SignDocument?token=' + req.Secure_Token__c;
        r.raiseCaseUrl         = baseUrl + '/apex/RaiseCase?token='    + req.Secure_Token__c;
        return r;
    }

    public static ESignResult fail(String code, String message) {
        ESignResult r = new ESignResult();
        r.success      = false;
        r.errorCode    = code;
        r.errorMessage = message;
        return r;
    }
}
