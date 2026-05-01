/**
 * SF-eSign Client-Side Logic
 *
 * Responsibilities:
 *  - Canvas draw signature (touch + mouse)
 *  - Typed signature rendered to canvas
 *  - Upload preview + validation
 *  - Tab switching
 *  - Pre-submit validation and data serialisation to hidden VF fields
 *
 * No external dependencies. Pure ES5 for maximum browser compatibility
 * with the Sites guest context.
 */
(function (global) {
    'use strict';

    var ESign = {};

    // ─────────────────────────────────────────
    // STATE
    // ─────────────────────────────────────────
    var activeTab            = 'draw';
    var drawCanvas           = null;
    var drawCtx              = null;
    var typedCanvas          = null;
    var typedCtx             = null;
    var isDrawing            = false;
    var lastX                = 0;
    var lastY                = 0;
    var uploadDataUrl        = null;
    var hasDrawnSomething    = false;

    // Decline modal state
    var _declineReasonFieldId = null;
    var _declineDescFieldId   = null;
    var _declineSubmitBtnId   = null;

    // ─────────────────────────────────────────
    // INIT
    // ─────────────────────────────────────────
    function init() {
        drawCanvas  = document.getElementById('esignCanvas');
        typedCanvas = document.getElementById('esignTypedCanvas');

        if (drawCanvas) {
            drawCtx = drawCanvas.getContext('2d');
            setupDrawCanvas();
        }
        if (typedCanvas) {
            typedCtx = typedCanvas.getContext('2d');
        }
    }

    // ─────────────────────────────────────────
    // TAB SWITCHING
    // ─────────────────────────────────────────
    ESign.switchTab = function (tab) {
        activeTab = tab;

        var tabs     = document.querySelectorAll('.esign-tab');
        var contents = document.querySelectorAll('.esign-tab-content');

        tabs.forEach(function (t) {
            t.classList.remove('esign-tab--active');
        });
        contents.forEach(function (c) {
            c.classList.add('esign-tab-content--hidden');
        });

        var activeBtn     = document.getElementById('tab-' + tab + '-btn');
        var activeContent = document.getElementById('esign-tab-' + tab);
        if (activeBtn)     activeBtn.classList.add('esign-tab--active');
        if (activeContent) activeContent.classList.remove('esign-tab-content--hidden');
    };

    // ─────────────────────────────────────────
    // DRAW CANVAS
    // ─────────────────────────────────────────
    function setupDrawCanvas() {
        // Mouse events
        drawCanvas.addEventListener('mousedown',  startDraw);
        drawCanvas.addEventListener('mousemove',  draw);
        drawCanvas.addEventListener('mouseup',    stopDraw);
        drawCanvas.addEventListener('mouseleave', stopDraw);

        // Touch events (mobile)
        drawCanvas.addEventListener('touchstart', function (e) {
            e.preventDefault();
            var touch = e.touches[0];
            var rect  = drawCanvas.getBoundingClientRect();
            lastX = touch.clientX - rect.left;
            lastY = touch.clientY - rect.top;
            isDrawing = true;
        }, { passive: false });

        drawCanvas.addEventListener('touchmove', function (e) {
            e.preventDefault();
            if (!isDrawing) return;
            var touch = e.touches[0];
            var rect  = drawCanvas.getBoundingClientRect();
            var x     = touch.clientX - rect.left;
            var y     = touch.clientY - rect.top;
            drawLine(lastX, lastY, x, y);
            lastX = x; lastY = y;
            hasDrawnSomething = true;
        }, { passive: false });

        drawCanvas.addEventListener('touchend', function () {
            isDrawing = false;
        });

        // Default pen style
        drawCtx.strokeStyle = '#1a1a2e';
        drawCtx.lineWidth   = 2.5;
        drawCtx.lineCap     = 'round';
        drawCtx.lineJoin    = 'round';
    }

    function startDraw(e) {
        isDrawing = true;
        var rect = drawCanvas.getBoundingClientRect();
        lastX    = (e.clientX - rect.left) * (drawCanvas.width / rect.width);
        lastY    = (e.clientY - rect.top)  * (drawCanvas.height / rect.height);
    }

    function draw(e) {
        if (!isDrawing) return;
        var rect = drawCanvas.getBoundingClientRect();
        var x    = (e.clientX - rect.left) * (drawCanvas.width / rect.width);
        var y    = (e.clientY - rect.top)  * (drawCanvas.height / rect.height);
        drawLine(lastX, lastY, x, y);
        lastX = x; lastY = y;
        hasDrawnSomething = true;
    }

    function stopDraw() { isDrawing = false; }

    function drawLine(x1, y1, x2, y2) {
        drawCtx.beginPath();
        drawCtx.moveTo(x1, y1);
        drawCtx.lineTo(x2, y2);
        drawCtx.stroke();
    }

    ESign.clearCanvas = function () {
        if (drawCtx && drawCanvas) {
            drawCtx.clearRect(0, 0, drawCanvas.width, drawCanvas.height);
            hasDrawnSomething = false;
        }
    };

    // ─────────────────────────────────────────
    // TYPED SIGNATURE
    // ─────────────────────────────────────────
    ESign.renderTypedSignature = function (text) {
        if (!typedCtx || !typedCanvas) return;

        typedCtx.clearRect(0, 0, typedCanvas.width, typedCanvas.height);

        if (!text || text.trim() === '') return;

        var fontSize = Math.min(60, Math.floor(typedCanvas.width / (text.length * 0.6 + 2)));
        fontSize     = Math.max(28, fontSize);

        typedCtx.font        = fontSize + 'px "Dancing Script", "Brush Script MT", cursive';
        typedCtx.fillStyle   = '#0b2d6e';
        typedCtx.textBaseline = 'middle';
        typedCtx.textAlign   = 'center';
        typedCtx.fillText(text, typedCanvas.width / 2, typedCanvas.height / 2);
    };

    // ─────────────────────────────────────────
    // UPLOAD PREVIEW
    // ─────────────────────────────────────────
    ESign.previewUpload = function (inputEl) {
        var file = inputEl.files && inputEl.files[0];
        if (!file) return;

        if (file.size > 2 * 1024 * 1024) {
            alert('Image must be under 2 MB. Please choose a smaller file.');
            inputEl.value = '';
            return;
        }

        var reader   = new FileReader();
        reader.onload = function (e) {
            uploadDataUrl = e.target.result;
            var preview   = document.getElementById('esignUploadPreview');
            if (preview) {
                preview.src = uploadDataUrl;
                preview.classList.add('esign-upload-preview--visible');
            }
        };
        reader.readAsDataURL(file);
    };

    // ─────────────────────────────────────────
    // PRE-SUBMIT: Validate + populate hidden fields
    // Returns false to abort VF form submission if invalid.
    // ─────────────────────────────────────────
    ESign.prepareAndValidate = function (sigDataFieldId, sigTypeFieldId) {
        var dataUrl  = null;
        var sigType  = null;

        if (activeTab === 'draw') {
            if (!hasDrawnSomething) {
                alert('Please draw your signature before submitting.');
                return false;
            }
            dataUrl = drawCanvas.toDataURL('image/png');
            sigType = 'Draw';
        }

        else if (activeTab === 'type') {
            var typedInput = document.getElementById('esignTypedInput');
            if (!typedInput || typedInput.value.trim() === '') {
                alert('Please type your name before submitting.');
                return false;
            }
            dataUrl = typedCanvas.toDataURL('image/png');
            sigType = 'Type';
        }

        else if (activeTab === 'upload') {
            if (!uploadDataUrl) {
                alert('Please upload a signature image before submitting.');
                return false;
            }
            dataUrl = uploadDataUrl;
            sigType = 'Upload';
        }

        if (!dataUrl || !sigType) {
            alert('Please provide a signature before submitting.');
            return false;
        }

        // Populate VF hidden fields
        var sigDataField = document.getElementById(sigDataFieldId);
        var sigTypeField = document.getElementById(sigTypeFieldId);
        if (sigDataField) sigDataField.value = dataUrl;
        if (sigTypeField) sigTypeField.value = sigType;

        // Disable submit button to prevent double-submission
        var btnSign = document.getElementById('btnSign');
        if (btnSign) {
            btnSign.value    = 'Processing...';
            btnSign.disabled = true;
        }

        return true; // Allow VF form submission
    };

    // ─────────────────────────────────────────
    // DECLINE MODAL
    // ─────────────────────────────────────────
    ESign.showDeclineForm = function (reasonFieldId, descFieldId, submitBtnId) {
        _declineReasonFieldId = reasonFieldId;
        _declineDescFieldId   = descFieldId;
        _declineSubmitBtnId   = submitBtnId;

        var modal = document.getElementById('esign-decline-modal');
        if (modal) modal.style.display = 'flex';

        // Reset inputs
        var sel = document.getElementById('esignDeclineReasonSel');
        var ta  = document.getElementById('esignDeclineDescTa');
        if (sel) sel.value = '';
        if (ta)  ta.value  = '';
    };

    ESign.confirmDecline = function () {
        var sel = document.getElementById('esignDeclineReasonSel');
        var ta  = document.getElementById('esignDeclineDescTa');

        if (!sel || !sel.value) {
            alert('Please select a reason before declining.');
            return;
        }

        var reasonField = document.getElementById(_declineReasonFieldId);
        var descField   = document.getElementById(_declineDescFieldId);
        var submitBtn   = document.getElementById(_declineSubmitBtnId);

        if (reasonField) reasonField.value = sel.value;
        if (descField)   descField.value   = ta ? ta.value : '';

        // Hide modal before server round-trip
        var modal = document.getElementById('esign-decline-modal');
        if (modal) modal.style.display = 'none';

        if (submitBtn) {
            submitBtn.click();
        }
    };

    ESign.cancelDecline = function () {
        var modal = document.getElementById('esign-decline-modal');
        if (modal) modal.style.display = 'none';
    };

    // ─────────────────────────────────────────
    // BOOT
    // ─────────────────────────────────────────
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

    global.ESign = ESign;

}(window));
