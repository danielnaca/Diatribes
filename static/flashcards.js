// ── Flashcards ────────────────────────────────────────────────────────────────

const Flashcards = (() => {
    const KEY = 'diatribes-flashcards';

    function loadAll() {
        try { return JSON.parse(localStorage.getItem(KEY) || '[]'); } catch { return []; }
    }
    function saveAll(words) {
        localStorage.setItem(KEY, JSON.stringify(words));
    }

    function save(word) {
        const words = loadAll();
        const exists = words.find(w => w.english === word.english && w.language === word.language);
        if (exists) return;
        words.unshift({ id: Date.now(), ...word, dateSaved: new Date().toISOString(), tries: 0, successes: 0 });
        saveAll(words);
        renderList();
    }

    function remove(id) {
        saveAll(loadAll().filter(w => w.id !== id));
        renderList();
    }

    // ── List rendering ────────────────────────────────────────────
    const listEl   = document.getElementById('fc-list');
    const emptyEl  = document.getElementById('fc-empty');
    const filterBtns = document.querySelectorAll('.filter-btn');
    let activeFilter = 'all';

    filterBtns.forEach(btn => {
        btn.addEventListener('click', () => {
            filterBtns.forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            activeFilter = btn.dataset.pos;
            renderList();
        });
    });

    function renderList() {
        let words = loadAll();
        if (activeFilter !== 'all') words = words.filter(w => w.pos === activeFilter);

        listEl.innerHTML = '';
        if (!words.length) {
            emptyEl.removeAttribute('hidden');
            return;
        }
        emptyEl.setAttribute('hidden', '');

        words.forEach(w => {
            const card = document.createElement('div');
            card.className = 'fc-card';
            card.innerHTML = `
                <span class="fc-foreign">${esc(w.translation)}</span>
                <span class="fc-english">${esc(w.english)}</span>
                <span class="fc-pos-badge ${w.pos}">${w.pos}</span>
                <button class="fc-del" title="Remove">×</button>`;
            card.querySelector('.fc-del').addEventListener('click', () => remove(w.id));
            listEl.appendChild(card);
        });
    }

    function esc(s) {
        return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    }

    // ── Review mode ───────────────────────────────────────────────
    const reviewBtn     = document.getElementById('review-btn');
    const reviewOverlay = document.getElementById('review-overlay');
    const reviewClose   = document.getElementById('review-close');
    const dirPick       = document.getElementById('review-dir-pick');
    const reviewCard    = document.getElementById('review-card');
    const cardFront     = document.getElementById('card-front');
    const cardBack      = document.getElementById('card-back');
    const revealBtn     = document.getElementById('reveal-btn');
    const gradeBtns     = document.getElementById('grade-btns');
    const reviewDone    = document.getElementById('review-done');
    const reviewAgain   = document.getElementById('review-again');
    const progressEl    = document.getElementById('review-progress');

    let queue = [];
    let currentIdx = 0;
    let direction = 'foreign-to-english';

    reviewBtn.addEventListener('click', () => {
        const words = loadAll();
        if (!words.length) return;
        reviewOverlay.removeAttribute('hidden');
        dirPick.removeAttribute('hidden');
        reviewCard.setAttribute('hidden', '');
        reviewDone.setAttribute('hidden', '');
    });

    reviewClose.addEventListener('click', () => reviewOverlay.setAttribute('hidden', ''));

    document.querySelectorAll('.dir-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            direction = btn.dataset.dir;
            startReview();
        });
    });

    function startReview() {
        let words = loadAll();
        if (direction === 'both') {
            // duplicate each word in both directions
            words = words.flatMap(w => [
                { ...w, _dir: 'foreign-to-english' },
                { ...w, _dir: 'english-to-foreign' },
            ]);
        } else {
            words = words.map(w => ({ ...w, _dir: direction }));
        }
        // shuffle
        queue = words.sort(() => Math.random() - 0.5);
        currentIdx = 0;

        dirPick.setAttribute('hidden', '');
        reviewDone.setAttribute('hidden', '');
        reviewCard.removeAttribute('hidden');
        showCard();
    }

    function showCard() {
        if (currentIdx >= queue.length) {
            reviewCard.setAttribute('hidden', '');
            reviewDone.removeAttribute('hidden');
            return;
        }
        const w   = queue[currentIdx];
        const dir = w._dir || direction;
        progressEl.textContent = `${currentIdx + 1} / ${queue.length}`;

        cardFront.textContent  = dir === 'foreign-to-english' ? w.translation : w.english;
        cardBack.textContent   = dir === 'foreign-to-english' ? w.english     : w.translation;

        cardBack.setAttribute('hidden', '');
        revealBtn.removeAttribute('hidden');
        gradeBtns.setAttribute('hidden', '');
    }

    revealBtn.addEventListener('click', () => {
        cardBack.removeAttribute('hidden');
        revealBtn.setAttribute('hidden', '');
        gradeBtns.removeAttribute('hidden');
    });

    document.querySelectorAll('.grade-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const w     = queue[currentIdx];
            const words = loadAll();
            const entry = words.find(x => x.id === w.id);
            if (entry) {
                entry.tries++;
                if (btn.dataset.grade === 'easy') entry.successes++;
                saveAll(words);
            }
            if (btn.dataset.grade === 'hard') {
                // push to back of queue
                queue.push({ ...w });
            }
            currentIdx++;
            showCard();
        });
    });

    reviewAgain.addEventListener('click', startReview);

    // ── Init ──────────────────────────────────────────────────────
    renderList();

    return { save, remove, loadAll };
})();
