/**
 * REST API entry point for SF-eSign.
 * Endpoint: /services/apexrest/esign/v1/request
 *
 * Allows any external system to create a signature request via HTTP.
 *
 * POST body (JSON):
 * {
 *   "contentDocumentId": "069...",
 *   "recipientEmail":    "signer@example.com",
 *   "recipientName":     "Jane Smith",       // optional
 *   "relatedRecordId":   "006...",           // optional
 *   "relatedObjectType": "Opportunity",      // optional
 *   "messageToSigner":   "Please sign...",   // optional
 *   "expiryHours":       72,                 // optional, default from label
 *   "sourceSystem":      "ExternalCRM"       // optional
 * }
 *
 * Response (JSON):
 * {
 *   "success":              true,
 *   "signatureRequestId":   "a00...",
 *   "signatureRequestName": "SR-0001",
 *   "token":                "esign_...",
 *   "signingUrl":           "https://...",
 *   "raiseCaseUrl":         "https://...",
 *   "errorMessage":         null,
 *   "errorCode":            null
 * }
 *
 * Security:
 *  - Requires a Connected App OAuth token or Session Id with
 *    Signature_Module_Admin permission set assigned.
 *  - All field validation is performed inside ESignRequest.validate().
 */
@RestResource(urlMapping='/esign/v1/request')
global with sharing class ESignRestAPI {

    @HttpPost
    global static ESignResult createRequest() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            if (req.requestBody == null || req.requestBody.size() == 0) {
                res.statusCode = 400;
                return ESignResult.fail('VALIDATION_ERROR', 'Request body is required');
            }

            ESignRequest esignReq = (ESignRequest) JSON.deserialize(
                req.requestBody.toString(),
                ESignRequest.class
            );

            // Ensure sourceSystem is tagged for REST callers if not set
            if (String.isBlank(esignReq.sourceSystem)) {
                esignReq.sourceSystem = 'REST';
            }

            ESignResult result = ESignService.createSignatureRequest(esignReq);
            res.statusCode = result.success ? 200 : 422;
            return result;

        } catch (JSONException e) {
            res.statusCode = 400;
            return ESignResult.fail('PARSE_ERROR', 'Invalid JSON body: ' + e.getMessage());
        } catch (Exception e) {
            res.statusCode = 500;
            return ESignResult.fail('UNEXPECTED_ERROR', e.getMessage());
        }
    }

    /**
     * GET /services/apexrest/esign/v1/request?id={signatureRequestId}
     * Returns the current status of a signing request.
     */
    @HttpGet
    global static Map<String, Object> getRequestStatus() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        String requestId = req.params.get('id');
        if (String.isBlank(requestId)) {
            res.statusCode = 400;
            return new Map<String, Object>{
                'success' => false,
                'error'   => 'id parameter is required'
            };
        }

        try {
            Signature_Request__c sigReq = ESignRequestSelector.findById(requestId);
            if (sigReq == null) {
                res.statusCode = 404;
                return new Map<String, Object>{
                    'success' => false,
                    'error'   => 'Signature request not found'
                };
            }

            res.statusCode = 200;
            return new Map<String, Object>{
                'success'              => true,
                'signatureRequestId'   => sigReq.Id,
                'signatureRequestName' => sigReq.Name,
                'status'               => sigReq.Status__c,
                'recipientEmail'       => sigReq.Recipient_Email__c,
                'tokenExpiry'          => sigReq.Token_Expiry__c,
                'signedDateTime'       => sigReq.Signed_DateTime__c,
                'signedDocumentId'     => sigReq.Signed_Document_Id__c
            };

        } catch (Exception e) {
            res.statusCode = 500;
            return new Map<String, Object>{
                'success' => false,
                'error'   => e.getMessage()
            };
        }
    }
}
