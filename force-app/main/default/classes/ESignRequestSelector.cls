/**
 * All SOQL for Signature_Request__c is centralised here.
 *
 * Design decisions:
 *  - Every query is WITH SECURITY_ENFORCED unless called from a
 *    `without sharing` guest-context controller that uses its own
 *    explicit field list (token-only lookup).
 *  - findByToken() is the only query exposed without SECURITY_ENFORCED
 *    because it runs under the Guest User profile inside a Site, which
 *    has no FLS by definition. The field list is minimal and explicit.
 *  - No dynamic SOQL — all queries are static to avoid injection risk.
 */
public class ESignRequestSelector {

    // ─────────────────────────────────────────────────────────────────────────
    // PUBLIC QUERY METHODS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Token-based lookup used by the public signing page (guest context).
     * Returns all fields needed to drive the signing flow in one query.
     * Does NOT use WITH SECURITY_ENFORCED because the guest user has no FLS.
     */
    public static List<Signature_Request__c> findByToken(String token) {
        return [
            SELECT  Id,
                    Name,
                    Status__c,
                    Recipient_Email__c,
                    Recipient_Name__c,
                    Document_Id__c,
                    Content_Version_Id__c,
                    Token_Expiry__c,
                    Last_Accessed__c,
                    Signed_DateTime__c,
                    Signer_Email__c,
                    Signature_Type__c,
                    Signature_Image_Id__c,
                    Signed_Document_Id__c,
                    Signing_IP__c,
                    Message_to_Signer__c,
                    Secure_Token__c,
                    Related_Record_Id__c,
                    Related_Object_Type__c,
                    Is_Test__c
            FROM    Signature_Request__c
            WHERE   Secure_Token__c = :token
            LIMIT   1
        ];
    }

    /**
     * Finds all Pending requests past their expiry — used by the scheduler.
     * Bulkified: returns up to 200 to stay within a single DML chunk.
     */
    public static List<Signature_Request__c> findExpiredPending() {
        return [
            SELECT  Id,
                    Name,
                    Recipient_Email__c,
                    Secure_Token__c,
                    Token_Expiry__c,
                    Is_Test__c
            FROM    Signature_Request__c
            WHERE   Status__c = 'Pending'
            AND     Token_Expiry__c < :DateTime.now()
            AND     Is_Test__c = false
            WITH    SECURITY_ENFORCED
            LIMIT   200
        ];
    }

    /**
     * Finds a single request by Id for internal Apex flows.
     * Used after insert to re-query with all required fields.
     */
    public static Signature_Request__c findById(String requestId) {
        List<Signature_Request__c> results = [
            SELECT  Id,
                    Name,
                    Status__c,
                    Recipient_Email__c,
                    Recipient_Name__c,
                    Document_Id__c,
                    Content_Version_Id__c,
                    Secure_Token__c,
                    Token_Expiry__c,
                    Related_Record_Id__c,
                    Related_Object_Type__c,
                    Message_to_Signer__c,
                    Is_Test__c
            FROM    Signature_Request__c
            WHERE   Id = :requestId
            WITH    SECURITY_ENFORCED
            LIMIT   1
        ];
        return results.isEmpty() ? null : results[0];
    }

    /**
     * Finds all Pending requests for a given recipient email.
     * Used for deduplication checks before creating a new request.
     */
    public static List<Signature_Request__c> findPendingByEmail(
            String email, String contentDocumentId) {

        return [
            SELECT Id, Name, Status__c, Token_Expiry__c
            FROM   Signature_Request__c
            WHERE  Recipient_Email__c = :email
            AND    Document_Id__c     = :contentDocumentId
            AND    Status__c          IN ('Pending', 'Viewed')
            AND    Is_Test__c         = false
            WITH   SECURITY_ENFORCED
            LIMIT  5
        ];
    }
}
