/**
 * Handles all token generation and validation for SF-eSign.
 *
 * Design constraints:
 *  - Token entropy: 256-bit AES key → hex-encoded → first 48 chars prefixed with 'esign_'
 *  - Tokens are indexed via External ID (Secure_Token__c) for O(1) lookups
 *  - Validation is always server-side; expiry is never read from the client
 *  - Full token is NEVER written to Signature_Audit__c; use maskToken() for logs
 */
public class ESignTokenService {

    private static final String TOKEN_PREFIX = 'esign_';
    private static final Integer TOKEN_HEX_LENGTH = 48;

    // ─────────────────────────────────────────────────────────────────────────
    // TOKEN GENERATION
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Generates a cryptographically secure, unique token.
     * Format: esign_<48 hex chars> = 54 chars total.
     */
    public static String generateToken() {
        Blob   randomBytes = Crypto.generateAesKey(256);
        String hex         = EncodingUtil.convertToHex(randomBytes);
        return TOKEN_PREFIX + hex.substring(0, TOKEN_HEX_LENGTH);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TOKEN VALIDATION
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Validates a token and returns the associated Signature_Request__c.
     *
     * Throws ESignException with a coded message on every failure so
     * the VF controller can render the correct error state without
     * embedding business logic.
     *
     * Does NOT update LastAccessed or Status — callers own those side-effects
     * so they can be applied in the right context (with/without sharing).
     */
    public static Signature_Request__c validateAndFetch(String token) {
        if (String.isBlank(token)) {
            throw new ESignException('TOKEN_MISSING');
        }

        List<Signature_Request__c> results = ESignRequestSelector.findByToken(token);

        if (results.isEmpty()) {
            throw new ESignException('TOKEN_INVALID');
        }

        Signature_Request__c req = results[0];

        // Expiry check — must use server time, never client-supplied value
        if (req.Token_Expiry__c != null && req.Token_Expiry__c < DateTime.now()) {
            if (req.Status__c != 'Expired') {
                req.Status__c = 'Expired';
                Database.update(req, AccessLevel.SYSTEM_MODE);
            }
            throw new ESignException('TOKEN_EXPIRED');
        }

        if (req.Status__c == 'Signed') {
            throw new ESignException('ALREADY_SIGNED');
        }

        if (req.Status__c == 'Cancelled') {
            throw new ESignException('REQUEST_CANCELLED');
        }

        if (req.Status__c == 'Declined') {
            throw new ESignException('REQUEST_DECLINED');
        }

        return req;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TOKEN MASKING (for audit logs)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Returns a masked representation of the token safe for audit logs.
     * Preserves the first 10 characters for correlation, masks the rest.
     * Example: "esign_ab12" + "***"
     */
    public static String maskToken(String token) {
        if (String.isBlank(token) || token.length() <= 10) {
            return '***';
        }
        return token.substring(0, 10) + '***';
    }
}
