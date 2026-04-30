/**
 * Typed exception for all SF-eSign module errors.
 * Uses coded messages so callers can switch on the code
 * without string-matching localised UI text.
 *
 * Error codes:
 *   TOKEN_MISSING      – no token supplied
 *   TOKEN_INVALID      – token not found in database
 *   TOKEN_EXPIRED      – request past Token_Expiry__c
 *   ALREADY_SIGNED     – request Status = Signed
 *   REQUEST_CANCELLED  – request Status = Cancelled
 *   REQUEST_DECLINED   – request Status = Declined
 *   VALIDATION_ERROR   – caller-supplied input failed validation
 *   DOCUMENT_ERROR     – ContentVersion retrieval or write failure
 *   EMAIL_ERROR        – email dispatch failure
 *   RATE_LIMITED       – too many page loads for this token
 */
public class ESignException extends Exception {}
