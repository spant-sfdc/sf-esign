/**
 * Enforces immutability of Signature_Audit__c records.
 *
 * This trigger is the second layer of immutability enforcement.
 * Layer 1: Permission Set (Signature_Module_Admin) sets allowEdit=false, allowDelete=false.
 * Layer 2: This trigger catches any programmatic update/delete attempts by Apex or Admin.
 *
 * By design: audit records can only be INSERTED. Any attempt to update
 * or delete an audit record throws an error visible to the caller.
 */
trigger ESignAuditTrigger on Signature_Audit__c (before update, before delete) {

    if (Trigger.isUpdate) {
        for (Signature_Audit__c rec : Trigger.new) {
            rec.addError(
                'Signature_Audit__c records are immutable. ' +
                'Updates are not permitted on the SF-eSign audit trail.'
            );
        }
    }

    if (Trigger.isDelete) {
        for (Signature_Audit__c rec : Trigger.old) {
            rec.addError(
                'Signature_Audit__c records are immutable. ' +
                'Deletions are not permitted on the SF-eSign audit trail.'
            );
        }
    }
}
