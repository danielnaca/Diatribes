// Settings — read/write to localStorage
// Exposes window.Settings

const Settings = (() => {
    const KEY = 'diatribes-settings';

    const DEFAULTS = {
        language: 'French',
        voice: 'google-fr-a',
        speed: 1.0,
    };

    function load() {
        try {
            return { ...DEFAULTS, ...JSON.parse(localStorage.getItem(KEY) || '{}') };
        } catch {
            return { ...DEFAULTS };
        }
    }

    function save(patch) {
        const current = load();
        localStorage.setItem(KEY, JSON.stringify({ ...current, ...patch }));
    }

    function get(key) { return load()[key]; }

    // ── Wire up the Settings view UI ──────────────────────────────
    function initUI() {
        const s = load();

        // Language seg
        const langSeg = document.getElementById('lang-seg');
        langSeg.querySelectorAll('.seg-btn').forEach(btn => {
            if (btn.dataset.value === s.language) btn.classList.add('active');
            else btn.classList.remove('active');
            btn.addEventListener('click', () => {
                langSeg.querySelectorAll('.seg-btn').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                save({ language: btn.dataset.value });
            });
        });

        // Voice select
        const voiceEl = document.getElementById('voice-select');
        voiceEl.value = s.voice;
        voiceEl.addEventListener('change', () => save({ voice: voiceEl.value }));

    }

    return { load, save, get, initUI };
})();

Settings.initUI();
