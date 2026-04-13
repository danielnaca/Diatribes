const conversation = document.getElementById('conversation');
const micBtn = document.getElementById('mic-btn');
const statusEl = document.getElementById('status');
const slider = document.getElementById('slider');
const sliderValue = document.getElementById('slider-value');
const correctionToggle = document.getElementById('correction-toggle');
const textInput = document.getElementById('text-input');
const sendBtn = document.getElementById('send-btn');
const skipBtn = document.getElementById('skip-btn');
const wordsBtn = document.getElementById('words-btn');
const wordsPanel = document.getElementById('words-panel');
const wordsList = document.getElementById('words-list');
const closePanel = document.getElementById('close-panel');

let history = [];
let recorder = null;
let chunks = [];
let appState = 'IDLE';
let pending = null;
let troubleWords = [];

const MIC_SVG = '<svg viewBox="0 0 24 24" width="28" height="28"><path d="M12 14c1.66 0 3-1.34 3-3V5c0-1.66-1.34-3-3-3S9 3.34 9 5v6c0 1.66 1.34 3 3 3z"/><path d="M17 11c0 2.76-2.24 5-5 5s-5-2.24-5-5H5c0 3.53 2.61 6.43 6 6.92V21h2v-3.08c3.39-.49 6-3.39 6-6.92h-2z"/></svg>';
const STOP_SVG = '<svg viewBox="0 0 24 24" width="28" height="28"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>';

micBtn.innerHTML = MIC_SVG;

// Slider
slider.addEventListener('input', () => {
    sliderValue.textContent = slider.value + '%';
});

// Text input
sendBtn.addEventListener('click', () => {
    const t = textInput.value.trim();
    if (t && appState !== 'PROCESSING') {
        textInput.value = '';
        handleUserText(t);
    }
});
textInput.addEventListener('keydown', e => {
    if (e.key === 'Enter') sendBtn.click();
});

// Mic
micBtn.addEventListener('click', async () => {
    if (appState === 'PROCESSING') return;
    if (appState === 'RECORDING') { stopRecording(); return; }

    try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        startRecording(stream);
    } catch (e) {
        setStatus('Mic access denied');
    }
});

// Skip correction retry
skipBtn.addEventListener('click', () => {
    if (appState === 'CORRECTION' && pending) {
        speechSynthesis.cancel();
        skipBtn.hidden = true;
        addMsg('assistant', pending.response);
        history.push({ role: 'assistant', content: pending.response });
        setState('PROCESSING');
        speak(pending.response, () => setState('IDLE'));
        pending = null;
    }
});

// Words panel
wordsBtn.addEventListener('click', () => {
    wordsList.innerHTML = '';
    if (troubleWords.length === 0) {
        wordsList.innerHTML = '<li style="color:var(--text-dim)">No trouble words yet</li>';
    } else {
        troubleWords.forEach(w => {
            const li = document.createElement('li');
            li.textContent = w;
            wordsList.appendChild(li);
        });
    }
    wordsPanel.hidden = false;
});
closePanel.addEventListener('click', () => { wordsPanel.hidden = true; });

// Recording
function startRecording(stream) {
    chunks = [];
    const mime = getSupportedMime();
    recorder = new MediaRecorder(stream, mime ? { mimeType: mime } : {});
    recorder.ondataavailable = e => { if (e.data.size > 0) chunks.push(e.data); };
    recorder.onstop = () => {
        stream.getTracks().forEach(t => t.stop());
        const blob = new Blob(chunks, { type: recorder.mimeType });
        transcribeAudio(blob);
    };
    recorder.start();
    setState('RECORDING');
}

function stopRecording() {
    if (recorder && recorder.state !== 'inactive') recorder.stop();
    setState('PROCESSING');
}

async function transcribeAudio(blob) {
    setStatus('Transcribing...');
    try {
        const fd = new FormData();
        const ext = blob.type.includes('mp4') ? 'mp4' : blob.type.includes('ogg') ? 'ogg' : 'webm';
        fd.append('audio', blob, 'rec.' + ext);
        const res = await fetch('/api/transcribe', { method: 'POST', body: fd });
        if (!res.ok) throw new Error('Transcription failed');
        const data = await res.json();
        if (data.text) {
            handleUserText(data.text);
        } else {
            setStatus('No speech detected');
            setState('IDLE');
        }
    } catch (e) {
        setStatus('Transcription error - try typing instead');
        setState('IDLE');
    }
}

async function handleUserText(text) {
    // Retry after correction
    if (appState === 'CORRECTION') {
        addMsg('user', text);
        skipBtn.hidden = true;
        addMsg('assistant', pending.response);
        history.push({ role: 'assistant', content: pending.response });
        setState('PROCESSING');
        speak(pending.response, () => setState('IDLE'));
        pending = null;
        return;
    }

    addMsg('user', text);
    setState('PROCESSING');
    setStatus('Thinking...');

    try {
        const fd = new FormData();
        fd.append('user_text', text);
        fd.append('slider_value', slider.value);
        fd.append('correction_on', correctionToggle.checked);
        fd.append('conversation_history', JSON.stringify(history));

        const res = await fetch('/api/respond', { method: 'POST', body: fd });
        if (!res.ok) throw new Error('Request failed');
        const data = await res.json();

        history.push({ role: 'user', content: text });

        if (data.trouble_words) {
            data.trouble_words.forEach(w => {
                if (!troubleWords.includes(w.toLowerCase())) {
                    troubleWords.push(w.toLowerCase());
                }
            });
            wordsBtn.textContent = 'Words (' + troubleWords.length + ')';
        }

        if (data.correction && correctionToggle.checked) {
            addMsg('correction', data.correction);
            pending = data;
            skipBtn.hidden = false;
            speak(data.correction, () => setState('CORRECTION'));
        } else {
            addMsg('assistant', data.response);
            history.push({ role: 'assistant', content: data.response });
            speak(data.response, () => setState('IDLE'));
        }
    } catch (e) {
        setStatus('Error: ' + e.message);
        setState('IDLE');
    }
}

// UI
function addMsg(type, text) {
    const div = document.createElement('div');
    div.className = 'msg ' + type;
    if (type === 'correction') {
        const label = document.createElement('div');
        label.className = 'label';
        label.textContent = 'Correction';
        div.appendChild(label);
        const span = document.createElement('span');
        span.textContent = text;
        div.appendChild(span);
    } else {
        div.textContent = text;
    }
    conversation.appendChild(div);
    conversation.scrollTop = conversation.scrollHeight;
}

function setState(s) {
    appState = s;
    micBtn.classList.remove('recording', 'disabled');
    switch (s) {
        case 'IDLE':
            micBtn.innerHTML = MIC_SVG;
            micBtn.disabled = false;
            setStatus('Tap mic to speak');
            break;
        case 'RECORDING':
            micBtn.innerHTML = STOP_SVG;
            micBtn.classList.add('recording');
            setStatus('Listening... tap to stop');
            break;
        case 'PROCESSING':
            micBtn.innerHTML = MIC_SVG;
            micBtn.classList.add('disabled');
            micBtn.disabled = true;
            setStatus('Processing...');
            break;
        case 'CORRECTION':
            micBtn.innerHTML = MIC_SVG;
            micBtn.disabled = false;
            setStatus('Now try again');
            break;
    }
}

function setStatus(text) { statusEl.textContent = text; }

// TTS
function speak(text, onEnd) {
    if (!('speechSynthesis' in window)) { if (onEnd) onEnd(); return; }
    speechSynthesis.cancel();
    const utt = new SpeechSynthesisUtterance(text);
    const voices = speechSynthesis.getVoices();
    const esVoice = voices.find(v => v.lang.startsWith('es'));
    if (esVoice) utt.voice = esVoice;
    utt.rate = 0.9;
    utt.onend = () => { if (onEnd) onEnd(); };
    utt.onerror = () => { if (onEnd) onEnd(); };
    speechSynthesis.speak(utt);
}

function getSupportedMime() {
    const types = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg'];
    for (const t of types) { if (MediaRecorder.isTypeSupported(t)) return t; }
    return '';
}

// Preload voices
if ('speechSynthesis' in window) {
    speechSynthesis.getVoices();
    speechSynthesis.onvoiceschanged = () => speechSynthesis.getVoices();
}
