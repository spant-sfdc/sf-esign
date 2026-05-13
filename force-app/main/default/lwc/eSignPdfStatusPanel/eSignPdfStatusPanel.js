import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue }    from 'lightning/uiRecordApi';

import PDF_STATUS  from '@salesforce/schema/Signature_Request__c.PDF_Generation_Status__c';
import PDF_ERROR   from '@salesforce/schema/Signature_Request__c.PDF_Generation_Error__c';
import SIGNED_DOC  from '@salesforce/schema/Signature_Request__c.Signed_Document_Id__c';

export default class ESignPdfStatusPanel extends LightningElement {

    @api recordId;

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [PDF_STATUS, PDF_ERROR, SIGNED_DOC]
    })
    record;

    get pdfStatus() {
        return getFieldValue(this.record.data, PDF_STATUS) || '—';
    }
    get errorDetail() {
        return getFieldValue(this.record.data, PDF_ERROR);
    }
    get signedDocId() {
        return getFieldValue(this.record.data, SIGNED_DOC);
    }
    get hasStatus() {
        return !!getFieldValue(this.record.data, PDF_STATUS);
    }
    get hasError() {
        return this.pdfStatus === 'Failed' && !!this.errorDetail;
    }
    get hasSignedDoc() {
        return !!this.signedDocId;
    }
    get signedDocUrl() {
        return this.signedDocId
            ? `/lightning/r/ContentDocument/${this.signedDocId}/view`
            : '#';
    }
    get statusBadgeClass() {
        const s = this.pdfStatus;
        if (s === 'Complete')   return 'status-badge status-badge--complete';
        if (s === 'Failed')     return 'status-badge status-badge--failed';
        if (s === 'Processing') return 'status-badge status-badge--processing';
        if (s === 'Pending')    return 'status-badge status-badge--pending';
        return 'status-badge';
    }
}
