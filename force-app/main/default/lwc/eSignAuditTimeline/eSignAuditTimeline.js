import { LightningElement, api, wire } from 'lwc';
import { getRecord }                   from 'lightning/uiRecordApi';
import getAuditEvents                  from '@salesforce/apex/ESignAuditTimelineController.getAuditEvents';

const DOT_CLASS = {
    Created      : 'esign-timeline__dot esign-timeline__dot--blue',
    Email_Sent   : 'esign-timeline__dot esign-timeline__dot--blue',
    Viewed       : 'esign-timeline__dot esign-timeline__dot--yellow',
    Signed       : 'esign-timeline__dot esign-timeline__dot--green',
    Declined     : 'esign-timeline__dot esign-timeline__dot--red',
    Expired      : 'esign-timeline__dot esign-timeline__dot--grey',
    Cancelled    : 'esign-timeline__dot esign-timeline__dot--grey',
    Reminder_Sent: 'esign-timeline__dot esign-timeline__dot--blue',
    Rate_Limited : 'esign-timeline__dot esign-timeline__dot--red',
    Error        : 'esign-timeline__dot esign-timeline__dot--red'
};

const LABEL_CLASS = {
    Signed   : 'esign-event-label esign-event-label--success',
    Declined : 'esign-event-label esign-event-label--error',
    Expired  : 'esign-event-label esign-event-label--neutral',
    Error    : 'esign-event-label esign-event-label--error',
    Rate_Limited: 'esign-event-label esign-event-label--error'
};

export default class ESignAuditTimeline extends LightningElement {

    @api signatureRequestId;

    _events = [];
    _isLoading = true;
    _hasError  = false;

    @wire(getAuditEvents, { signatureRequestId: '$signatureRequestId' })
    wiredAudit({ data, error }) {
        this._isLoading = false;
        if (data) {
            this._events = data.map(ev => ({
                ...ev,
                dotClass          : DOT_CLASS[ev.Event_Type__c] || 'esign-timeline__dot esign-timeline__dot--grey',
                labelClass        : LABEL_CLASS[ev.Event_Type__c] || 'esign-event-label',
                formattedTimestamp: ev.Event_Timestamp__c
                    ? new Date(ev.Event_Timestamp__c).toLocaleString()
                    : ''
            }));
            this._hasError = false;
        } else if (error) {
            this._hasError = true;
        }
    }

    get isLoading() { return this._isLoading; }
    get hasError()  { return this._hasError; }
    get events()    { return this._events; }
    get hasEvents() { return this._events.length > 0; }
    get isEmpty()   { return !this._isLoading && !this._hasError && this._events.length === 0; }
}
