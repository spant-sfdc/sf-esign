/**
 * Apex controller backing the eSignAuditTimeline LWC.
 * Returns audit events for a given Signature_Request__c, newest first.
 */
public with sharing class ESignAuditTimelineController {

    @AuraEnabled(cacheable=true)
    public static List<Signature_Audit__c> getAuditEvents(String signatureRequestId) {
        return [
            SELECT  Id,
                    Name,
                    Event_Type__c,
                    Event_Timestamp__c,
                    Actor_Email__c,
                    Token__c,
                    IP_Address__c,
                    User_Agent__c,
                    Event_Detail__c,
                    Source_System__c
            FROM    Signature_Audit__c
            WHERE   Signature_Request__c = :signatureRequestId
            WITH    SECURITY_ENFORCED
            ORDER BY Event_Timestamp__c DESC
            LIMIT   200
        ];
    }
}
