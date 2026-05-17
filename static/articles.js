// ── Articles ──────────────────────────────────────────────────────────────────

// ── Storage ───────────────────────────────────────────────────────────────────
const ArtStore = (() => {
    const SAVED_KEY = 'diatribes-articles-saved';
    const FEEDS_KEY = 'diatribes-articles-feeds';

    const getSaved = () => JSON.parse(localStorage.getItem(SAVED_KEY) || '[]');
    const setSaved = arr => localStorage.setItem(SAVED_KEY, JSON.stringify(arr));
    const getFeeds = () => JSON.parse(localStorage.getItem(FEEDS_KEY) || '[]');
    const setFeeds = arr => localStorage.setItem(FEEDS_KEY, JSON.stringify(arr));

    function addSaved(article) {
        const arr = getSaved();
        arr.unshift({ ...article, id: Date.now(), savedAt: new Date().toISOString() });
        setSaved(arr);
    }
    function removeSaved(id) { setSaved(getSaved().filter(a => a.id !== id)); }

    function addFeed(feed) {
        const arr = getFeeds();
        if (arr.some(f => f.rssUrl === feed.rssUrl)) return false;
        arr.unshift({ ...feed, id: Date.now(), addedAt: new Date().toISOString() });
        setFeeds(arr);
        return true;
    }
    function removeFeed(id) { setFeeds(getFeeds().filter(f => f.id !== id)); }

    return { getSaved, setSaved, getFeeds, setFeeds, addSaved, removeSaved, addFeed, removeFeed };
})();

// ── Articles settings ─────────────────────────────────────────────────────────
const ArtSettings = (() => {
    const KEY = 'diatribes-articles-settings';
    const DEFAULTS = { posSelections: ['nouns', 'verbs', 'adjectives', 'adverbs'], highlightsOff: false };
    const load = () => ({ ...DEFAULTS, ...JSON.parse(localStorage.getItem(KEY) || '{}') });
    const save = patch => localStorage.setItem(KEY, JSON.stringify({ ...load(), ...patch }));
    return { load, save };
})();

// ── State ─────────────────────────────────────────────────────────────────────
let artCurrentTab     = 'saved';
let artFeedsLevel     = 'subscriptions'; // 'subscriptions' | 'articles'
let artSelectedFeedId = null;            // null = All
let artCurrentArticle = null;
let artActivePopup    = null;

// ── Elements ──────────────────────────────────────────────────────────────────
const artOptBtn     = document.getElementById('art-options-btn');
const artOptOverlay = document.getElementById('art-options-overlay');
const artOptSheet   = document.getElementById('art-options-sheet');
const readerOverlay = document.getElementById('reader-overlay');
const readerBack    = document.getElementById('reader-back');
const readerTitle   = document.getElementById('reader-title');
const readerSource  = document.getElementById('reader-source');
const readerBody    = document.getElementById('reader-body');
const readerOptBtn  = document.getElementById('reader-options-btn');

// ── Tab switching ─────────────────────────────────────────────────────────────
document.querySelectorAll('.art-tab').forEach(tab => {
    tab.addEventListener('click', () => {
        document.querySelectorAll('.art-tab').forEach(t => t.classList.remove('active'));
        tab.classList.add('active');
        artCurrentTab = tab.dataset.tab;
        document.getElementById('art-pane-saved').hidden = artCurrentTab !== 'saved';
        document.getElementById('art-pane-feeds').hidden = artCurrentTab !== 'feeds';
    });
});

// ── Saved articles ────────────────────────────────────────────────────────────
const artUrlInput = document.getElementById('art-url-input');
const artAddBtn   = document.getElementById('art-add-btn');

artAddBtn.addEventListener('click', addSavedArticle);
artUrlInput.addEventListener('keydown', e => { if (e.key === 'Enter') addSavedArticle(); });

async function addSavedArticle() {
    const url = artUrlInput.value.trim();
    if (!url) return;
    artAddBtn.textContent = '…';
    artAddBtn.disabled = true;
    try {
        const fd = new FormData();
        fd.append('url', url);
        const res = await fetch('/api/fetch-article', { method: 'POST', body: fd });
        if (!res.ok) throw new Error((await res.json()).detail || 'Failed');
        const data = await res.json();
        ArtStore.addSaved({ ...data, url });
        artUrlInput.value = '';
        renderSavedList();
    } catch (e) {
        alert('Could not fetch article: ' + e.message);
    } finally {
        artAddBtn.textContent = 'Save';
        artAddBtn.disabled = false;
    }
}

function renderSavedList() {
    const list  = document.getElementById('art-saved-list');
    const empty = document.getElementById('art-saved-empty');
    const articles = ArtStore.getSaved();
    list.innerHTML = '';
    if (articles.length === 0) { empty.hidden = false; return; }
    empty.hidden = true;
    articles.forEach(a => list.appendChild(createSavedItem(a)));
}

function createSavedItem(article) {
    const div = document.createElement('div');
    div.className = 'art-item';
    div.innerHTML = `<div class="art-item-title">${escHtml(article.title)}</div>
        ${article.excerpt ? `<div class="art-item-excerpt">${escHtml(article.excerpt)}</div>` : ''}`;
    div.addEventListener('click', () => {
        artCurrentArticle = { title: article.title, url: article.url, paragraphs: article.paragraphs, source: null };
        readerTitle.textContent = article.title;
        readerSource.textContent = '';
        readerBody.innerHTML = '';
        readerOverlay.removeAttribute('hidden');
        renderReader();
    });
    return div;
}

// ── Feeds ─────────────────────────────────────────────────────────────────────
const feedUrlInput = document.getElementById('feed-url-input');
const feedAddBtn   = document.getElementById('feed-add-btn');

feedAddBtn.addEventListener('click', addFeed);
feedUrlInput.addEventListener('keydown', e => { if (e.key === 'Enter') addFeed(); });

async function addFeed() {
    const url = feedUrlInput.value.trim();
    if (!url) return;
    feedAddBtn.textContent = '…';
    feedAddBtn.disabled = true;
    try {
        const fd = new FormData();
        fd.append('url', url);
        const res = await fetch('/api/fetch-feed', { method: 'POST', body: fd });
        if (!res.ok) throw new Error((await res.json()).detail || 'Failed');
        const data = await res.json();
        if (!ArtStore.addFeed({ ...data, rssUrl: url })) { alert('Feed already added'); return; }
        feedUrlInput.value = '';
        artFeedsLevel = 'subscriptions';
        artSelectedFeedId = null;
        renderFeedList();
    } catch (e) {
        alert('Could not add feed: ' + e.message);
    } finally {
        feedAddBtn.textContent = 'Add';
        feedAddBtn.disabled = false;
    }
}

function renderFeedList() {
    const list     = document.getElementById('art-feeds-list');
    const empty    = document.getElementById('art-feeds-empty');
    const addBar   = document.getElementById('feed-add-bar');
    const feeds    = ArtStore.getFeeds();
    list.innerHTML = '';

    if (artFeedsLevel === 'subscriptions') {
        addBar.hidden = false;
        if (feeds.length === 0) { empty.hidden = false; return; }
        empty.hidden = true;

        // "All" row
        const totalCount = feeds.reduce((n, f) => n + f.items.length, 0);
        list.appendChild(createSubItem(null, 'All articles', null, totalCount));

        // Per-feed rows
        feeds.forEach(feed => list.appendChild(createSubItem(feed.id, feed.title, feed.favicon, feed.items.length)));

    } else {
        addBar.hidden = true;
        empty.hidden  = true;

        // Back row
        const selectedFeed = feeds.find(f => f.id === artSelectedFeedId);
        const backLabel = artSelectedFeedId === null ? 'All articles' : (selectedFeed?.title || '');
        const backRow = document.createElement('div');
        backRow.className = 'feed-nav-back';
        backRow.innerHTML = `<svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor"><path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z"/></svg><span>${escHtml(backLabel)}</span>`;
        backRow.addEventListener('click', () => {
            artFeedsLevel = 'subscriptions';
            artSelectedFeedId = null;
            renderFeedList();
        });
        list.appendChild(backRow);

        // Articles
        let items = [];
        if (artSelectedFeedId === null) {
            feeds.forEach(feed => {
                feed.items.forEach(item => items.push({ ...item, feedTitle: feed.title, feedFavicon: feed.favicon }));
            });
            items.sort((a, b) => {
                const da = new Date(a.date), db = new Date(b.date);
                if (isNaN(da)) return 1; if (isNaN(db)) return -1;
                return db - da;
            });
        } else if (selectedFeed) {
            items = selectedFeed.items.map(item => ({ ...item, feedTitle: selectedFeed.title, feedFavicon: selectedFeed.favicon }));
        }

        items.forEach(item => list.appendChild(createFeedItem(item)));
    }
}

function createSubItem(feedId, title, favicon, count) {
    const div = document.createElement('div');
    div.className = 'art-item feed-sub-item';

    const left = document.createElement('div');
    left.className = 'feed-sub-left';

    if (favicon) {
        const img = document.createElement('img');
        img.src = favicon;
        img.className = 'feed-sub-favicon';
        left.appendChild(img);
    } else {
        const dot = document.createElement('div');
        dot.className = 'feed-sub-all-icon';
        left.appendChild(dot);
    }

    const titleEl = document.createElement('span');
    titleEl.className = 'feed-sub-title';
    titleEl.textContent = title;
    left.appendChild(titleEl);
    div.appendChild(left);

    const right = document.createElement('div');
    right.className = 'feed-sub-right';
    right.innerHTML = `<span class="feed-sub-count">${count}</span><svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><path d="M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z"/></svg>`;
    div.appendChild(right);

    div.addEventListener('click', () => {
        artFeedsLevel = 'articles';
        artSelectedFeedId = feedId;
        renderFeedList();
    });
    return div;
}

function createFeedItem(item) {
    const div = document.createElement('div');
    div.className = 'art-item';

    if (artSelectedFeedId === null && item.feedTitle) {
        const meta = document.createElement('div');
        meta.className = 'art-item-meta';
        if (item.feedFavicon) {
            const img = document.createElement('img');
            img.src = item.feedFavicon;
            img.className = 'art-item-favicon';
            meta.appendChild(img);
        }
        const src = document.createElement('span');
        src.className = 'art-item-source';
        src.textContent = item.feedTitle;
        meta.appendChild(src);
        div.appendChild(meta);
    }

    const title = document.createElement('div');
    title.className = 'art-item-title';
    title.textContent = item.title;
    div.appendChild(title);

    if (item.excerpt) {
        const excerpt = document.createElement('div');
        excerpt.className = 'art-item-excerpt';
        excerpt.textContent = item.excerpt;
        div.appendChild(excerpt);
    }

    div.addEventListener('click', () => openFeedArticle(item));
    return div;
}

async function openFeedArticle(item) {
    readerTitle.textContent = item.title;
    readerSource.textContent = item.feedTitle || '';
    readerBody.innerHTML = '<p class="reader-loading">Loading…</p>';
    readerOverlay.removeAttribute('hidden');

    try {
        const fd = new FormData();
        fd.append('url', item.url);
        const res = await fetch('/api/fetch-article', { method: 'POST', body: fd });
        if (!res.ok) throw new Error();
        const data = await res.json();
        artCurrentArticle = { title: item.title, url: item.url, paragraphs: data.paragraphs, source: item.feedTitle };
        renderReader();
    } catch {
        readerBody.innerHTML = '<p class="reader-loading">Could not load article.</p>';
    }
}

// ── Reader ────────────────────────────────────────────────────────────────────
function renderReader() {
    if (!artCurrentArticle?.paragraphs) return;

    const s        = ArtSettings.load();
    const langCode = Settings.load().language === 'Spanish' ? 'es' : 'fr';
    const doSwap   = !s.highlightsOff && s.posSelections.length > 0;
    const enabledPos = doSwap
        ? new Set(s.posSelections.map(p => ({ nouns: 'noun', verbs: 'verb', adjectives: 'adj', adverbs: 'adv' }[p])).filter(Boolean))
        : new Set();

    readerBody.innerHTML = artCurrentArticle.paragraphs.map(para => {
        if (!doSwap) return `<p>${escHtml(para)}</p>`;
        const { html } = DSWAP.swap(para, langCode, enabledPos);
        return `<p>${html}</p>`;
    }).join('');

    readerBody.scrollTop = 0;
    readerBody.classList.toggle('highlights-off', s.highlightsOff);
}

readerBack.addEventListener('click', () => {
    readerOverlay.setAttribute('hidden', '');
    artCurrentArticle = null;
    closeArtPopup();
});

// ── Word tap popup in reader ──────────────────────────────────────────────────
readerBody.addEventListener('click', e => {
    if (artActivePopup && !artActivePopup.contains(e.target)) closeArtPopup();
    const wordEl = e.target.closest('.word[data-src]');
    if (!wordEl) return;
    if (wordEl === artActivePopup) { closeArtPopup(); return; }
    if (artActivePopup) closeArtPopup();

    const popup = document.createElement('span');
    popup.className = 'word-popup';
    const saveBtn = document.createElement('button');
    saveBtn.className = 'popup-save';
    saveBtn.textContent = '+ Save';
    popup.innerHTML = `<span class="popup-src">${wordEl.dataset.src}</span>`;
    popup.appendChild(saveBtn);
    wordEl.appendChild(popup);
    artActivePopup = wordEl;

    saveBtn.addEventListener('click', ev => {
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

function closeArtPopup() {
    if (!artActivePopup) return;
    artActivePopup.querySelector('.word-popup')?.remove();
    artActivePopup = null;
}

// ── Articles options sheet ────────────────────────────────────────────────────
function openArtOptions() {
    const s = ArtSettings.load();
    document.querySelectorAll('#art-pos-pills input').forEach(cb => {
        cb.checked = s.posSelections.includes(cb.value);
    });
    const hlSeg = document.getElementById('art-highlight-seg');
    hlSeg.querySelectorAll('.seg-btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.value === (s.highlightsOff ? 'off' : 'on'));
    });
    artOptOverlay.removeAttribute('hidden');
    artOptSheet.removeAttribute('hidden');
}

function closeArtOptions() {
    artOptOverlay.setAttribute('hidden', '');
    artOptSheet.setAttribute('hidden', '');
    if (!readerOverlay.hasAttribute('hidden') && artCurrentArticle) renderReader();
}

artOptBtn.addEventListener('click', openArtOptions);
artOptOverlay.addEventListener('click', closeArtOptions);
readerOptBtn.addEventListener('click', openArtOptions);

document.querySelectorAll('#art-pos-pills input').forEach(cb => {
    cb.addEventListener('change', () => {
        const selected = Array.from(document.querySelectorAll('#art-pos-pills input:checked')).map(c => c.value);
        ArtSettings.save({ posSelections: selected });
    });
});

initSeg(document.getElementById('art-highlight-seg'));
document.getElementById('art-highlight-seg').addEventListener('click', () => {
    const off = segValue(document.getElementById('art-highlight-seg')) === 'off';
    ArtSettings.save({ highlightsOff: off });
});

// ── Helpers ───────────────────────────────────────────────────────────────────
function escHtml(str) {
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// ── Init ──────────────────────────────────────────────────────────────────────
renderSavedList();
renderFeedList();
