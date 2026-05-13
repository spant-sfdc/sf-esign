/**
 * eSignSignedPdfGenerator — auto-generates a signed PDF when a Signature Request is marked Signed.
 *
 * Place this component on the Signature_Request__c record page via App Builder.
 *
 * Behavior:
 *   • Renders nothing when Status != 'Signed' or Signed_Document_Id__c is already set.
 *   • Auto-triggers PDF generation once per page load when Status = 'Signed' and no PDF exists.
 *   • Shows spinner during generation, success banner on completion, error banner with Retry on failure.
 *
 * Generation flow:
 *   1. Fetch all signing metadata (getSignatureRequestData)
 *   2. Fetch original document bytes + file type (getSigningDocumentData)
 *   3. Normalize to PDF bytes:
 *        – PDF original → use as-is
 *        – HTML original → convert via htmlToPdf (html2canvas + PDF-LIB)
 *        – Other / missing → create a minimal stub PDF page
 *   4. Append certificate page via createSignedPdf (PDF-LIB)
 *   5. Save merged PDF via PdfGenerationController.savePdfWithLinks
 *   6. Update Signature_Request__c.Signed_Document_Id__c
 */

import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue }            from 'lightning/uiRecordApi';
import { ShowToastEvent }                      from 'lightning/platformShowToastEvent';

import STATUS_FIELD          from '@salesforce/schema/Signature_Request__c.Status__c';
import SIGNED_DOC_FIELD      from '@salesforce/schema/Signature_Request__c.Signed_Document_Id__c';
import CONTENT_VERSION_FIELD from '@salesforce/schema/Signature_Request__c.Content_Version_Id__c';
import RELATED_RECORD_FIELD  from '@salesforce/schema/Signature_Request__c.Related_Record_Id__c';
import PDF_STATUS_FIELD      from '@salesforce/schema/Signature_Request__c.PDF_Generation_Status__c';
import SIGNED_DATETIME_FIELD from '@salesforce/schema/Signature_Request__c.Signed_DateTime__c';

import getSignatureRequestData from '@salesforce/apex/PdfGenerationController.getSignatureRequestData';
import getSigningDocumentData  from '@salesforce/apex/PdfGenerationController.getSigningDocumentData';
import savePdfWithLinks        from '@salesforce/apex/PdfGenerationController.savePdfWithLinks';
import updateSignedDocumentId  from '@salesforce/apex/PdfGenerationController.updateSignedDocumentId';

import {
    initialize   as initPdfEngine,
    htmlToPdf,
    createSignedPdf,
    pdfBytesToBase64
} from 'c/pdfGenerationEngine';

export default class ESignSignedPdfGenerator extends LightningElement {

    @api recordId;

    @track isGenerating  = false;
    @track isComplete    = false;
    @track hasError      = false;
    @track statusMessage = 'Preparing signed PDF…';
    @track errorMessage  = '';

    _contentDocId = null;     // set after successful save
    _attemptDone  = false;    // prevents double-run within same page session
    _libsReady    = false;    // set true once initPdfEngine resolves

    // ── Template helpers ──────────────────────────────────────────────────────

    get showPanel() {
        return this.isGenerating || this.isComplete || this.hasError;
    }

    get fileUrl() {
        return this._contentDocId
            ? `/lightning/r/ContentDocument/${this._contentDocId}/view`
            : '#';
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        // Start loading pdf-lib + html2canvas immediately so they are ready
        // before the wire result arrives (both are needed for HTML → PDF fallback)
        initPdfEngine(this)
            .then(() => { this._libsReady = true; })
            .catch(err => console.warn('[eSignPdfGen] Library preload warning:', err.message));
    }

    // ── Wire: watch for Status = Signed ───────────────────────────────────────

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [
            STATUS_FIELD, SIGNED_DOC_FIELD, CONTENT_VERSION_FIELD,
            RELATED_RECORD_FIELD, PDF_STATUS_FIELD, SIGNED_DATETIME_FIELD
        ]
    })
    wiredRecord({ error, data }) {
        if (!data) return;

        const status    = getFieldValue(data, STATUS_FIELD);
        const signedDoc = getFieldValue(data, SIGNED_DOC_FIELD);
        const pdfStatus = getFieldValue(data, PDF_STATUS_FIELD);
        const signedAt  = getFieldValue(data, SIGNED_DATETIME_FIELD);

        if (status !== 'Signed' || signedDoc || this._attemptDone || this.isGenerating) return;

        // Trigger if VF page explicitly failed
        const pdfFailed = pdfStatus === 'Failed';

        // Trigger if generation appears stale: status isn't Complete and signing was
        // more than 3 minutes ago (covers tab-close during Processing or Pending timeout)
        const THREE_MIN_MS = 3 * 60 * 1000;
        const pdfStale = pdfStatus !== 'Complete'
            && signedAt
            && (Date.now() - new Date(signedAt).getTime() > THREE_MIN_MS);

        if (pdfFailed || pdfStale) {
            console.log('[eSignPdfGen] LWC fallback triggered.',
                'pdfStatus=' + pdfStatus,
                'pdfFailed=' + pdfFailed,
                'pdfStale=' + pdfStale);
            this._attemptDone = true;
            this._generate();
        }
    }

    // ── Retry handler ─────────────────────────────────────────────────────────

    async handleRetry() {
        this.hasError     = false;
        this.errorMessage = '';
        await this._generate();
    }

    // ── Core generation flow ──────────────────────────────────────────────────

    async _generate() {
        this.isGenerating = true;
        this.isComplete   = false;
        this.hasError     = false;

        try {
            // Ensure pdf-lib is loaded (idempotent)
            this.statusMessage = 'Loading PDF engine…';
            await initPdfEngine(this);

            // ── Step 1: Signing metadata ──────────────────────────────────────
            this.statusMessage = 'Fetching signing data…';
            const reqData  = await getSignatureRequestData({ requestId: this.recordId });
            console.log('[eSignPdfGen] reqData:', reqData.name, '| signer:', reqData.signerName);

            const certData = {
                requestRef:      reqData.name              || 'N/A',
                signerName:      reqData.signerName        || 'N/A',
                signerEmail:     reqData.signerEmail       || 'N/A',
                signedDateTime:  reqData.signedDateTime    || 'N/A',
                signatureMethod: reqData.signatureMethod   || 'N/A',
                ipAddress:       reqData.ipAddress         || 'N/A'
            };

            // ── Step 2: Original document ─────────────────────────────────────
            this.statusMessage = 'Loading original document…';
            let originalPdfBase64 = null;

            if (reqData.contentVersionId) {
                const docData = await getSigningDocumentData({
                    contentVersionId: reqData.contentVersionId
                });
                console.log('[eSignPdfGen] original doc:', docData.title,
                    '| type:', docData.fileType,
                    '| size:', Math.round((docData.base64 || '').length * 0.75 / 1024), 'KB');

                originalPdfBase64 = await this._normalizeToPdfBase64(docData);
            }

            if (!originalPdfBase64) {
                // No original or unsupported type — build a minimal stub page
                console.log('[eSignPdfGen] no usable original — creating stub PDF');
                originalPdfBase64 = await this._buildStubPdf(certData);
            }

            // ── Step 3: Append certificate page ───────────────────────────────
            this.statusMessage = 'Generating signed PDF…';
            const mergedBytes = await createSignedPdf({
                originalPdfBase64,
                signatureImageBase64: reqData.signatureImageBase64 || null,
                certData
            });
            console.log('[eSignPdfGen] merged PDF:', Math.round(mergedBytes.length / 1024), 'KB');

            // ── Step 4: Save to Salesforce ────────────────────────────────────
            this.statusMessage = 'Saving PDF…';
            const dateStr  = new Date().toISOString().replace(/\D/g, '').substring(0, 14);
            const safeName = (reqData.signerName || 'Signer')
                .replace(/[^a-zA-Z0-9]/g, '').substring(0, 20) || 'Signer';
            const fileName = `Signed-${dateStr}-${safeName}`;

            const docId = await savePdfWithLinks({
                base64Pdf:      pdfBytesToBase64(mergedBytes),
                fileName,
                parentId:       this.recordId,
                linkedEntityId: reqData.relatedRecordId || null
            });
            console.log('[eSignPdfGen] upload success — ContentDocumentId:', docId);

            // ── Step 5: Update Signed_Document_Id__c ──────────────────────────
            this.statusMessage = 'Updating record…';
            await updateSignedDocumentId({ requestId: this.recordId, contentDocId: docId });

            this._contentDocId = docId;
            this.isComplete    = true;
            this.dispatchEvent(new ShowToastEvent({
                title:   'Signed PDF Ready',
                message: 'The signed document with certificate has been attached to this record.',
                variant: 'success'
            }));

        } catch (err) {
            console.error('[eSignPdfGen] generation failed:', err);
            this.hasError     = true;
            this.errorMessage = err.body?.message || err.message || 'PDF generation failed.';
            this.dispatchEvent(new ShowToastEvent({
                title:   'Signed PDF Generation Failed',
                message: this.errorMessage,
                variant: 'error',
                mode:    'sticky'
            }));
        } finally {
            this.isGenerating = false;
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /**
     * Converts a document to a base64-encoded PDF string.
     * PDF  → returned as-is
     * HTML → rendered via html2canvas + PDF-LIB
     * Other / missing → returns null (caller creates stub)
     */
    async _normalizeToPdfBase64(docData) {
        const { fileType, base64 } = docData;
        if (!base64) return null;

        const ft = (fileType || '').toUpperCase();

        if (ft === 'PDF') {
            return base64;
        }

        if (ft === 'HTML' || ft === 'HTM') {
            this.statusMessage = 'Converting HTML to PDF…';
            const htmlString = atob(base64);
            const pdfBytes   = await htmlToPdf(htmlString);
            console.log('[eSignPdfGen] HTML→PDF:', Math.round(pdfBytes.length / 1024), 'KB');
            return pdfBytesToBase64(pdfBytes);
        }

        return null;   // unsupported format
    }

    /**
     * Creates a minimal one-page reference PDF using PDF-LIB directly.
     * Used when no original document is available or its format is unsupported.
     */
    async _buildStubPdf(certData) {
        const { PDFDocument, StandardFonts, rgb } = window.PDFLib;
        const doc   = await PDFDocument.create();
        const font  = await doc.embedFont(StandardFonts.Helvetica);
        const fontB = await doc.embedFont(StandardFonts.HelveticaBold);
        const page  = doc.addPage([595, 842]);

        page.drawText('Original Document', {
            x: 40, y: 780, size: 14, font: fontB, color: rgb(0.15, 0.15, 0.15)
        });
        page.drawLine({
            start: { x: 40, y: 770 }, end: { x: 555, y: 770 },
            thickness: 0.5, color: rgb(0.8, 0.8, 0.8)
        });
        page.drawText(
            'The original document was attached separately to this record.',
            { x: 40, y: 748, size: 10, font, color: rgb(0.4, 0.4, 0.4) }
        );
        page.drawText(`Signing Request: ${certData.requestRef}`, {
            x: 40, y: 728, size: 9, font, color: rgb(0.5, 0.5, 0.5)
        });

        const bytes = await doc.save();
        return pdfBytesToBase64(bytes);
    }
}
