import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent }               from 'lightning/platformShowToastEvent';
import getGeneratedDocumentsForRecord   from '@salesforce/apex/DocGen_Controller.getGeneratedDocumentsForRecord';
import createSignatureRequest           from '@salesforce/apex/ESignService.createSignatureRequest';

export default class ESignButton extends LightningElement {
    @api recordId;
    @api objectApiName;

    @track isOpen        = false;
    @track isLoadingDocs = false;
    @track isSending     = false;

    @track documents     = [];
    @track selectedDocId = '';

    @track recipientEmail  = '';
    @track recipientName   = '';
    @track messageToSigner = '';
    @track error           = null;

    // ── Getters ──────────────────────────────────────────────────────────────

    get hasDocuments() { return this.documents.length > 0; }

    get documentOptions() {
        return this.documents.map(d => ({
            label: `${d.templateName || 'Document'} — ${this._fmtDate(d.generatedAt)}`,
            value: d.contentDocumentId
        }));
    }

    get isSendDisabled() {
        return this.isSending || !this.selectedDocId || !this.recipientEmail;
    }

    // ── Open / close ──────────────────────────────────────────────────────────

    async handleOpen() {
        this.isOpen = true;
        this._reset();
        await this._loadDocuments();
    }

    handleClose() {
        if (this.isSending) return;
        this.isOpen = false;
    }

    // ── Load generated documents ──────────────────────────────────────────────

    async _loadDocuments() {
        this.isLoadingDocs = true;
        this.error = null;
        try {
            this.documents = await getGeneratedDocumentsForRecord({ recordId: this.recordId });
            if (this.documents.length) {
                // Pre-select the most recent document
                this.selectedDocId = this.documents[0].contentDocumentId;
            }
        } catch (e) {
            this.error = this._msg(e);
        } finally {
            this.isLoadingDocs = false;
        }
    }

    // ── Field handlers ────────────────────────────────────────────────────────

    handleDocChange(evt)     { this.selectedDocId   = evt.detail.value; }
    handleEmailChange(evt)   { this.recipientEmail  = evt.target.value; }
    handleNameChange(evt)    { this.recipientName   = evt.target.value; }
    handleMessageChange(evt) { this.messageToSigner = evt.target.value; }

    // ── Send ──────────────────────────────────────────────────────────────────

    async handleSend() {
        if (!this._validate()) return;
        this.isSending = true;
        this.error     = null;
        try {
            const result = await createSignatureRequest({
                request: {
                    contentDocumentId : this.selectedDocId,
                    recipientEmail    : this.recipientEmail,
                    recipientName     : this.recipientName   || null,
                    relatedRecordId   : this.recordId,
                    relatedObjectType : this.objectApiName   || null,
                    messageToSigner   : this.messageToSigner || null,
                    sourceSystem      : 'RecordPage'
                }
            });

            if (result.success) {
                this.dispatchEvent(new ShowToastEvent({
                    title  : 'Signature Request Sent',
                    message: `Signing link sent to ${this.recipientEmail}`,
                    variant: 'success'
                }));
                this.dispatchEvent(new CustomEvent('signingrequestcreated', {
                    bubbles : true,
                    composed: true,
                    detail  : {
                        signatureRequestId  : result.signatureRequestId,
                        signatureRequestName: result.signatureRequestName,
                        signingUrl          : result.signingUrl
                    }
                }));
                this.isOpen = false;
            } else {
                this.error = result.errorMessage || 'Failed to send signing request.';
            }
        } catch (e) {
            this.error = this._msg(e);
        } finally {
            this.isSending = false;
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _validate() {
        this.error = null;
        if (!this.selectedDocId) {
            this.error = 'Please select a document to send for signature.';
            return false;
        }
        if (!this.recipientEmail) {
            this.error = 'Recipient email is required.';
            return false;
        }
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(this.recipientEmail)) {
            this.error = 'Please enter a valid email address.';
            return false;
        }
        return true;
    }

    _reset() {
        this.documents      = [];
        this.selectedDocId  = '';
        this.recipientEmail = '';
        this.recipientName  = '';
        this.messageToSigner= '';
        this.error          = null;
    }

    _fmtDate(dateStr) {
        if (!dateStr) return '';
        try { return new Date(dateStr).toLocaleString(); }
        catch (e) { return dateStr; }
    }

    _msg(err) {
        if (typeof err === 'string') return err;
        if (err?.body?.message)      return err.body.message;
        if (err?.message)            return err.message;
        return 'An unexpected error occurred.';
    }
}
