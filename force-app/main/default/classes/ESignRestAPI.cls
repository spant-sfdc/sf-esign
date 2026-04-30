/**
 * REST API entry point for SF-eSign.
 * Endpoint: /services/apexrest/esign/v1/request
 *
 * POST body (JSON):
 * {
 *   "contentDocumentId": "069...",
 *   "recipientEmail":    "signer@example.com",
 *   "recipientName":     "Jane Smith",
 *   "relatedRecordId":   "006...",
 *   "relatedObjectType": "Opportunity",
 *   "messageToSigner":   "Please sign...",
 *   "expiryHours":       72,
 *   "sourceSystem":      "ExternalCRM"
 * }
 */
@RestResource(urlMapping='/esign/v1/request')
global with sharing class ESignRestAPI {

    @HttpPost
    global static void createRequest() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            if (req.requestBody == null || req.requestBody.size() == 0) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    ESignResult.fail('VALIDATION_ERROR', 'Request body is required')
                ));
                return;
            }

            ESignRequest esignReq = (ESignRequest) JSON.deserialize(
                req.requestBody.toString(),
                ESignRequest.class
            );

            if (String.isBlank(esignReq.sourceSystem)) {
                esignReq.sourceSystem = 'REST';
            }

            ESignResult result = ESignService.createSignatureRequest(esignReq);
            res.statusCode = result.success ? 200 : 422;
            res.responseBody = Blob.valueOf(JSON.serialize(result));

        } catch (JSONException e) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(
                ESignResult.fail('PARSE_ERROR', 'Invalid JSON body: ' + e.getMessage())
            ));
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(
                ESignResult.fail('UNEXPECTED_ERROR', e.getMessage())
            ));
        }
    }

    @HttpGet
    global static void getRequestStatus() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        String requestId = req.params.get('id');
        if (String.isBlank(requestId)) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf('{"success":false,"error":"id parameter is required"}');
            return;
        }

        try {
            Signature_Request__c sigReq = ESignRequestSelector.findById(requestId);
            if (sigReq == null) {
                res.statusCode = 404;
                res.responseBody = Blob.valueOf('{"success":false,"error":"Signature request not found"}');
                return;
            }

            res.statusCode = 200;
            Map<String, Object> payload = new Map<String, Object>{
                'success'              => true,
                'signatureRequestId'   => sigReq.Id,
                'signatureRequestName' => sigReq.Name,
                'status'               => sigReq.Status__c,
                'recipientEmail'       => sigReq.Recipient_Email__c,
                'tokenExpiry'          => sigReq.Token_Expiry__c,
                'signedDateTime'       => sigReq.Signed_DateTime__c,
                'signedDocumentId'     => sigReq.Signed_Document_Id__c
            };
            res.responseBody = Blob.valueOf(JSON.serialize(payload));

        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new Map<String, Object>{ 'success' => false, 'error' => e.getMessage() }
            ));
        }
    }
}
