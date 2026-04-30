import { LightningElement, api, track } from 'lwc';
import createSignatureRequest from '@salesforce/apex/ESignService.createSignatureRequest';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

/**
 * eSignLauncher — integration entry component for SF-eSign.
 *
 * Usage (from any parent component or record page):
 *   <c-e-sign-launcher
 *       content-document-id={documentId}
 *       related-record-id={recordId}
 *       related-object-type="Opportunity"
 *       onsigningrequestcreated={handleRequestCreated}>
 *   </c-e-sign-launcher>
 *
 * The component dispatches 'signingrequestcreated' when the request is
 * successfully created, passing { signatureRequestId, signingUrl } in detail.
 */
export default class ESignLauncher extends LightningElement {

    // ── Inputs from parent ──────────────────────────────────────────────────
    /** ContentDocumentId to send for signing. Required. */
    @api contentDocumentId;

    /** Optional: any SObject record Id to link the signed doc back to. */
    @api relatedRecordId;

    /** Optional: API name of the related SObject (e.g. 'Opportunity'). */
    @api relatedObjectType;

    /** Optional: pre-fill recipient email (e.g. from a related contact). */
    @api defaultRecipientEmail = '';

    /** Identifies the calling system in audit trail. */
    @api sourceSystem = 'LWC';

    // ── Internal state ──────────────────────────────────────────────────────
    @track recipientEmail  = '';
    @track recipientName   = '';
    @track messageToSigner = '';
    @track expiryHours     = 72;
    @track isLoading       = false;
    @track isSuccess       = false;
    @track errorMessage    = '';
    @track result          = null;

    // ── Lifecycle ───────────────────────────────────────────────────────────
    connectedCallback() {
        if (this.defaultRecipientEmail) {
            this.recipientEmail = this.defaultRecipientEmail;
        }
    }

    // ── Computed ────────────────────────────────────────────────────────────
    get sendLabel()     { return this.isLoading ? 'Sending...' : 'Send for Signature'; }
    get isSendDisabled(){ return this.isLoading || !this.contentDocumentId; }

    // ── Handlers ────────────────────────────────────────────────────────────
    handleChange(evt) {
        const field = evt.target.dataset.field;
        let val = evt.target.value;
        if (field === 'expiryHours') val = parseInt(val, 10);
        this[field] = val;
        this.errorMessage = '';
    }

    async handleSend() {
        if (!this.validate()) return;

        this.isLoading    = true;
        this.errorMessage = '';

        try {
            this.result = await createSignatureRequest({
                request: {
                    contentDocumentId : this.contentDocumentId,
                    recipientEmail    : this.recipientEmail,
                    recipientName     : this.recipientName,
                    relatedRecordId   : this.relatedRecordId,
                    relatedObjectType : this.relatedObjectType,
                    messageToSigner   : this.messageToSigner,
                    expiryHours       : this.expiryHours,
                    sourceSystem      : this.sourceSystem
                }
            });

            if (this.result.success) {
                this.isSuccess = true;
                this.fireToast('success', 'Signing request sent to ' + this.recipientEmail);
                this.dispatchEvent(new CustomEvent('signingrequestcreated', {
                    detail: {
                        signatureRequestId  : this.result.signatureRequestId,
                        signatureRequestName: this.result.signatureRequestName,
                        signingUrl          : this.result.signingUrl
                    },
                    bubbles   : true,
                    composed  : true
                }));
            } else {
                this.errorMessage = this.result.errorMessage || 'An error occurred.';
            }
        } catch (e) {
            this.errorMessage = e.body?.message || e.message || 'Unexpected error.';
        } finally {
            this.isLoading = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel', { bubbles: true, composed: true }));
    }

    // ── Validation ──────────────────────────────────────────────────────────
    validate() {
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!this.contentDocumentId) {
            this.errorMessage = 'A document must be provided before sending for signature.';
            return false;
        }
        if (!emailRegex.test(this.recipientEmail)) {
            this.errorMessage = 'Please enter a valid email address.';
            return false;
        }
        if (!this.expiryHours || this.expiryHours < 1 || this.expiryHours > 720) {
            this.errorMessage = 'Expiry must be between 1 and 720 hours.';
            return false;
        }
        return true;
    }

    // ── Utilities ────────────────────────────────────────────────────────────
    fireToast(variant, message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'SF-eSign', message, variant }));
    }
}
