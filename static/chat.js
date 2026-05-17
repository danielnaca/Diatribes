// ── Chat logic ────────────────────────────────────────────────────────────────

DSWAP.load();

// ── Elements ──────────────────────────────────────────────────────────────────
const conversation   = document.getElementById('conversation');
const actionBtn      = document.getElementById('action-btn');
const textInput      = document.getElementById('text-input');
const skipBtn        = document.getElementById('skip-btn');
const optionsBtn     = document.getElementById('options-btn');
const optionsSheet   = document.getElementById('options-sheet');
const optionsOverlay = document.getElementById('options-overlay');

// ── State ─────────────────────────────────────────────────────────────────────
let history      = [];
let recorder     = null;
let chunks       = [];
let appState     = 'IDLE';
let pending      = null;
let currentAudio = null;
let activePopup  = null;
let turnFromVoice = false;  // whether the current turn was started by mic

// ── Mix preset → approach mapping ─────────────────────────────────────────────
// 1=Native, 2=Light, 3=Medium, 4=Strong, 5=Immersion
const MIX_APPROACH = {
    1: { approach: 'pos',          posOverride: [] },
    2: { approach: 'pos',          posOverride: ['nouns'] },
    3: { approach: 'pos',          posOverride: null },   // use checked toggles
    4: { approach: 'sentence_alt', posOverride: [] },
    5: { approach: 'immersion',    posOverride: [] },
};

// ── Speed slider in options sheet ─────────────────────────────────────────────
const sheetSpeedSlider = document.getElementById('sheet-speed-slider');
const sheetSpeedVal    = document.getElementById('sheet-speed-val');

function formatSpeed(v) {
    return parseFloat(v).toFixed(2).replace(/\.?0+$/, '') + '×';
}

sheetSpeedSlider.addEventListener('input', () => {
    const v = parseFloat(sheetSpeedSlider.value);
    sheetSpeedVal.textContent = formatSpeed(v);
    Settings.save({ speed: v });
});

// ── Options sheet ─────────────────────────────────────────────────────────────
function openOptions() {
    // Sync speed slider with saved setting
    const s = Settings.load();
    sheetSpeedSlider.value     = s.speed;
    sheetSpeedVal.textContent  = formatSpeed(s.speed);

    optionsOverlay.removeAttribute('hidden');
    optionsSheet.removeAttribute('hidden');
    syncPosSection();
}
function closeOptions() {
    optionsOverlay.setAttribute('hidden', '');
    optionsSheet.setAttribute('hidden', '');
}

optionsBtn.addEventListener('click', openOptions);
optionsOverlay.addEventListener('click', closeOptions);

const mixSlider  = document.getElementById('mix-slider');
const posSection = document.getElementById('pos-section');

function syncPosSection() {
    const level = parseInt(mixSlider.value);
    posSection.hidden = (level !== 3); // only relevant for "Medium" (use all toggles)
}
mixSlider.addEventListener('input', syncPosSection);

// ── Segmented controls in sheet ───────────────────────────────────────────────
function initSeg(container) {
    container.querySelectorAll('.seg-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            container.querySelectorAll('.seg-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
        });
    });
}
function segValue(container) {
    return container.querySelector('.seg-btn.active')?.dataset.value ?? null;
}

initSeg(document.getElementById('corrections-seg'));
initSeg(document.getElementById('length-seg'));
initSeg(document.getElementById('highlight-seg'));

document.getElementById('highlight-seg').addEventListener('click', () => {
    const on = segValue(document.getElementById('highlight-seg')) === 'on';
    document.body.classList.toggle('highlights-off', !on);
});

// ── Sidebar / hamburger ───────────────────────────────────────────────────────
const sidebar        = document.getElementById('sidebar');
const sidebarOverlay = document.getElementById('sidebar-overlay');

document.querySelectorAll('.hamburger').forEach(btn => {
    btn.addEventListener('click', () => {
        sidebar.classList.add('open');
        sidebarOverlay.classList.add('open');
    });
});
sidebarOverlay.addEventListener('click', () => {
    sidebar.classList.remove('open');
    sidebarOverlay.classList.remove('open');
});

document.querySelectorAll('.nav-item').forEach(item => {
    item.addEventListener('click', () => {
        const view = item.dataset.view;
        document.querySelectorAll('.nav-item').forEach(i => i.classList.remove('active'));
        item.classList.add('active');
        document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
        document.getElementById('view-' + view).classList.add('active');
        sidebar.classList.remove('open');
        sidebarOverlay.classList.remove('open');
    });
});

// ── SVGs ──────────────────────────────────────────────────────────────────────
const MIC_SVG  = '<svg viewBox="0 0 24 24" width="18" height="18" fill="white"><path d="M12 14c1.66 0 3-1.34 3-3V5c0-1.66-1.34-3-3-3S9 3.34 9 5v6c0 1.66 1.34 3 3 3z"/><path d="M17 11c0 2.76-2.24 5-5 5s-5-2.24-5-5H5c0 3.53 2.61 6.43 6 6.92V21h2v-3.08c3.39-.49 6-3.39 6-6.92h-2z"/></svg>';
const STOP_SVG = '<svg viewBox="0 0 24 24" width="16" height="16" fill="white"><rect x="5" y="5" width="14" height="14" rx="2"/></svg>';
const SEND_SVG = '<svg viewBox="0 0 24 24" width="18" height="18" fill="white"><path d="M4 12l1.41 1.41L11 7.83V20h2V7.83l5.58 5.59L20 12l-8-8-8 8z"/></svg>';

// ── Single action button ──────────────────────────────────────────────────────
function updateActionBtn() {
    const hasText = textInput.value.trim().length > 0;
    if (appState === 'RECORDING') {
        actionBtn.innerHTML = STOP_SVG;
        actionBtn.classList.add('recording');
        actionBtn.classList.remove('disabled');
        actionBtn.disabled = false;
    } else if (appState === 'PROCESSING') {
        actionBtn.innerHTML = MIC_SVG;
        actionBtn.classList.remove('recording');
        actionBtn.classList.add('disabled');
        actionBtn.disabled = true;
    } else if (hasText) {
        actionBtn.innerHTML = SEND_SVG;
        actionBtn.classList.remove('recording', 'disabled');
        actionBtn.disabled = false;
    } else {
        actionBtn.innerHTML = MIC_SVG;
        actionBtn.classList.remove('recording', 'disabled');
        actionBtn.disabled = false;
    }
}

updateActionBtn();

textInput.addEventListener('input', updateActionBtn);
textInput.addEventListener('keydown', e => {
    if (e.key === 'Enter') actionBtn.click();
});

actionBtn.addEventListener('click', async () => {
    if (appState === 'PROCESSING') return;

    if (appState === 'RECORDING') {
        stopRecording();
        return;
    }

    const t = textInput.value.trim();
    if (t) {
        textInput.value = '';
        updateActionBtn();
        turnFromVoice = false;
        handleUserText(t);
        return;
    }

    // mic toggle
    try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        startRecording(stream);
    } catch {
        setStatus('Mic access denied');
    }
});

// ── Skip retry ────────────────────────────────────────────────────────────────
skipBtn.addEventListener('click', () => {
    if (appState === 'CORRECTION' && pending) {
        skipBtn.hidden = true;
        addMsg('assistant', pending._displayHtml || pending.response, !!pending._displayHtml);
        history.push({ role: 'assistant', content: pending.response });
        setState('PROCESSING');
        speak(pending._speakText || pending.response, () => setState('IDLE'));
        pending = null;
    }
});

// ── Recording ─────────────────────────────────────────────────────────────────
function startRecording(stream) {
    chunks = [];
    turnFromVoice = true;
    const mime = getSupportedMime();
    recorder = new MediaRecorder(stream, mime ? { mimeType: mime } : {});
    recorder.ondataavailable = e => { if (e.data.size > 0) chunks.push(e.data); };
    recorder.onstop = () => {
        stream.getTracks().forEach(t => t.stop());
        transcribeAudio(new Blob(chunks, { type: recorder.mimeType }));
    };
    recorder.start();
    setState('RECORDING');
}
function stopRecording() {
    if (recorder && recorder.state !== 'inactive') recorder.stop();
    setState('PROCESSING');
}
async function transcribeAudio(blob) {
    setStatus('Transcribing…');
    try {
        const fd = new FormData();
        const ext = blob.type.includes('mp4') ? 'mp4' : blob.type.includes('ogg') ? 'ogg' : 'webm';
        fd.append('audio', blob, 'rec.' + ext);
        const res = await fetch('/api/transcribe', { method: 'POST', body: fd });
        if (!res.ok) throw new Error();
        const data = await res.json();
        if (data.text) handleUserText(data.text);
        else { setStatus('No speech detected'); setState('IDLE'); }
    } catch {
        setStatus('Transcription error');
        setState('IDLE');
    }
}

// ── Helpers: options reading ──────────────────────────────────────────────────
function getMixConfig() {
    const level = parseInt(mixSlider.value);
    const cfg   = MIX_APPROACH[level];
    const pos   = cfg.posOverride ?? getPosSelections();
    return { approach: cfg.approach, pos_selections: pos };
}
function getPosSelections() {
    return Array.from(document.querySelectorAll('#pos-section input:checked')).map(cb => cb.value);
}

// ── Main handler ──────────────────────────────────────────────────────────────
async function handleUserText(text) {
    const correctionsMode = segValue(document.getElementById('corrections-seg'));
    const lengthValue     = parseInt(segValue(document.getElementById('length-seg')));

    if (appState === 'CORRECTION') {
        addMsg('user', text);
        skipBtn.hidden = true;
        addMsg('assistant', pending._displayHtml || pending.response, !!pending._displayHtml);
        history.push({ role: 'assistant', content: pending.response });
        setState('PROCESSING');
        speak(pending._speakText || pending.response, () => setState('IDLE'));
        pending = null;
        return;
    }

    addMsg('user', text);
    setState('PROCESSING');
    setStatus('Thinking…');

    const { approach, pos_selections } = getMixConfig();
    const s = Settings.load();

    try {
        const fd = new FormData();
        fd.append('user_text', text);
        fd.append('length_value', lengthValue);
        fd.append('correction_on', correctionsMode !== 'off');
        fd.append('language', s.language);
        fd.append('conversation_history', JSON.stringify(history));
        fd.append('approach', approach);
        fd.append('pos_selections', JSON.stringify(pos_selections));

        const res = await fetch('/api/respond', { method: 'POST', body: fd });
        if (!res.ok) throw new Error('Request failed');
        const data = await res.json();

        history.push({ role: 'user', content: text });

        let displayHtml = null;
        let speakText   = data.response;

        if (approach === 'pos') {
            const langCode = s.language === 'Spanish' ? 'es' : 'fr';
            const enabledPos = new Set(pos_selections.map(p => ({ nouns: 'noun', verbs: 'verb', adjectives: 'adj', adverbs: 'adv' }[p])).filter(Boolean));
            const { html, plain } = DSWAP.swap(data.response, langCode, enabledPos);
            displayHtml = html;
            speakText   = plain;
        }

        const shouldSpeak = turnFromVoice;

        if (data.correction && correctionsMode !== 'off') {
            addMsg('correction', data.correction);
            if (correctionsMode === 'repeat') {
                pending = { ...data, _displayHtml: displayHtml, _speakText: speakText };
                skipBtn.hidden = false;
                if (shouldSpeak) speak(data.correction, () => setState('CORRECTION'));
                else setState('CORRECTION');
            } else {
                addMsg('assistant', displayHtml || data.response, !!displayHtml);
                history.push({ role: 'assistant', content: data.response });
                if (shouldSpeak) speak(speakText, () => setState('IDLE'));
                else setState('IDLE');
            }
        } else {
            addMsg('assistant', displayHtml || data.response, !!displayHtml);
            history.push({ role: 'assistant', content: data.response });
            if (shouldSpeak) speak(speakText, () => setState('IDLE'));
            else setState('IDLE');
        }
    } catch (e) {
        setStatus('Error: ' + e.message);
        setState('IDLE');
    }
}

// ── UI helpers ────────────────────────────────────────────────────────────────
function addMsg(type, content, isHtml = false) {
    const div = document.createElement('div');
    div.className = 'msg ' + type;
    if (type === 'correction') {
        const label = document.createElement('div');
        label.className = 'label';
        label.textContent = 'Correction';
        div.appendChild(label);
        const span = document.createElement('span');
        span.textContent = content;
        div.appendChild(span);
    } else if (isHtml) {
        div.innerHTML = content;
    } else {
        div.textContent = content;
    }
    conversation.appendChild(div);
    conversation.scrollTop = conversation.scrollHeight;
}

function setState(s) {
    appState = s;
    switch (s) {
        case 'IDLE':       setStatus('Tap mic to speak'); break;
        case 'RECORDING':  setStatus('Listening… tap to stop'); break;
        case 'PROCESSING': setStatus('Processing…'); break;
        case 'CORRECTION': setStatus('Now try again'); break;
    }
    updateActionBtn();
}
function setStatus(_t) { /* status display removed */ }

// ── Word tap → popup ──────────────────────────────────────────────────────────
conversation.addEventListener('click', e => {
    if (activePopup && !activePopup.contains(e.target)) closePopup();
    const wordEl = e.target.closest('.word[data-src]');
    if (!wordEl) return;
    if (wordEl === activePopup) { closePopup(); return; }
    if (activePopup) closePopup();

    const popup = document.createElement('span');
    popup.className = 'word-popup';
    const saveBtn = document.createElement('button');
    saveBtn.className = 'popup-save';
    saveBtn.textContent = '+ Save';
    popup.innerHTML = `<span class="popup-src">${wordEl.dataset.src}</span>`;
    popup.appendChild(saveBtn);
    wordEl.appendChild(popup);
    activePopup = wordEl;

    saveBtn.addEventListener('click', async ev => {
        ev.stopPropagation();
        const s = Settings.load();
        Flashcards.save({
            english:     wordEl.dataset.src,
            translation: wordEl.dataset.tr || wordEl.textContent.trim(),
            language:    s.language,
            pos:         wordEl.dataset.pos,
        });
        saveBtn.textContent = '✓';
        saveBtn.className   = 'popup-save saved';
    });
});
function closePopup() {
    if (!activePopup) return;
    activePopup.querySelector('.word-popup')?.remove();
    activePopup = null;
}

// ── TTS ───────────────────────────────────────────────────────────────────────
function speak(text, onEnd) {
    if (currentAudio) { currentAudio.pause(); currentAudio = null; }
    speakAI(text, onEnd);
}

async function speakAI(text, onEnd) {
    const s  = Settings.load();
    const fd = new FormData();
    fd.append('text',          text);
    fd.append('voice',         s.voice);
    fd.append('language',      s.language);
    fd.append('speaking_rate', s.speed);
    try {
        const res = await fetch('/api/speak', { method: 'POST', body: fd });
        if (!res.ok) throw new Error();
        const blob = await res.blob();
        const url  = URL.createObjectURL(blob);
        const audio = new Audio(url);
        currentAudio = audio;
        audio.onended = () => { URL.revokeObjectURL(url); currentAudio = null; onEnd?.(); };
        audio.onerror = () => { URL.revokeObjectURL(url); currentAudio = null; onEnd?.(); };
        audio.play();
    } catch {
        onEnd?.();
    }
}

function getSupportedMime() {
    for (const t of ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg'])
        if (MediaRecorder.isTypeSupported(t)) return t;
    return '';
}
