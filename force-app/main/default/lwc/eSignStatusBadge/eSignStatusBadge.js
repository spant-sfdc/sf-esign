import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import STATUS_FIELD       from '@salesforce/schema/Signature_Request__c.Status__c';
import SIGNED_DATE_FIELD  from '@salesforce/schema/Signature_Request__c.Signed_DateTime__c';
import RECIPIENT_FIELD    from '@salesforce/schema/Signature_Request__c.Recipient_Email__c';

const FIELDS = [STATUS_FIELD, SIGNED_DATE_FIELD, RECIPIENT_FIELD];

const STATUS_CONFIG = {
    Pending  : { label: 'Pending',  icon: 'utility:clock',   css: 'esign-badge esign-badge--warning' },
    Viewed   : { label: 'Viewed',   icon: 'utility:preview', css: 'esign-badge esign-badge--info'    },
    Signed   : { label: 'Signed',   icon: 'utility:check',   css: 'esign-badge esign-badge--success' },
    Declined : { label: 'Declined', icon: 'utility:close',   css: 'esign-badge esign-badge--error'   },
    Expired  : { label: 'Expired',  icon: 'utility:ban',     css: 'esign-badge esign-badge--neutral' },
    Cancelled: { label: 'Cancelled',icon: 'utility:remove',  css: 'esign-badge esign-badge--neutral' }
};

export default class ESignStatusBadge extends LightningElement {

    @api signatureRequestId;
    @api showDate = false;

    _record;
    _error;

    @wire(getRecord, { recordId: '$signatureRequestId', fields: FIELDS })
    wiredRecord({ data, error }) {
        this._record = data;
        this._error  = error;
    }

    get isLoaded()    { return !!this._record; }
    get status()      { return getFieldValue(this._record, STATUS_FIELD); }
    get signedDate()  { return getFieldValue(this._record, SIGNED_DATE_FIELD); }

    get config()      { return STATUS_CONFIG[this.status] || STATUS_CONFIG['Pending']; }
    get badgeClass()  { return this.config.css; }
    get iconName()    { return this.config.icon; }
    get statusLabel() { return this.config.label; }

    get showSignedDate() {
        return this.showDate && this.status === 'Signed' && this.signedDate;
    }

    get formattedSignedDate() {
        if (!this.signedDate) return '';
        return new Date(this.signedDate).toLocaleString();
    }
}
