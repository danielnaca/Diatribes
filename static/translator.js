// Dictionary loaded from shared/dict/en_es_fr.json
let DICT = {};

async function loadDict() {
  const res = await fetch('/shared/dict/en_es_fr.json');
  DICT = await res.json();
}

// ── Lemmatizer ────────────────────────────────────────────────────────────────
function lemmatize(word) {
  if (DICT[word]) return word;

  // -ing: running→run, making→make
  if (word.length > 4 && word.endsWith('ing')) {
    const stem = word.slice(0, -3);
    if (DICT[stem]) return stem;
    // double consonant: running→runn→run
    if (stem.length > 2 && stem[stem.length - 1] === stem[stem.length - 2]) {
      const s = stem.slice(0, -1);
      if (DICT[s]) return s;
    }
    // dropped e: making→mak→make
    if (DICT[stem + 'e']) return stem + 'e';
  }

  // -ed: walked→walk, loved→love, stopped→stop
  if (word.length > 3 && word.endsWith('ed')) {
    const stem = word.slice(0, -2);
    if (DICT[stem]) return stem;
    if (DICT[stem + 'e']) return stem + 'e';
    if (stem.length > 1 && stem[stem.length - 1] === stem[stem.length - 2]) {
      const s = stem.slice(0, -1);
      if (DICT[s]) return s;
    }
  }

  // -es: watches→watch
  if (word.length > 3 && word.endsWith('es')) {
    const stem = word.slice(0, -2);
    if (DICT[stem]) return stem;
  }

  // -s: books→book, runs→run
  if (word.length > 2 && word.endsWith('s')) {
    const stem = word.slice(0, -1);
    if (DICT[stem]) return stem;
  }

  // -er / -est: nicer→nice, fastest→fast
  if (word.length > 4 && word.endsWith('est')) {
    const stem = word.slice(0, -3);
    if (DICT[stem]) return stem;
    if (DICT[stem + 'e']) return stem + 'e';
  }
  if (word.length > 3 && word.endsWith('er')) {
    const stem = word.slice(0, -2);
    if (DICT[stem]) return stem;
    if (DICT[stem + 'e']) return stem + 'e';
  }

  // -ly: handle adjective→adverb derivations
  if (word.length > 3 && word.endsWith('ly')) {
    const stem = word.slice(0, -2);
    if (DICT[stem]) return stem;
    if (DICT[stem + 'e']) return stem + 'e';
  }

  return null;
}

// ── Capitalize helper ─────────────────────────────────────────────────────────
function matchCase(original, translated) {
  if (original[0] === original[0].toUpperCase() && original[0] !== original[0].toLowerCase()) {
    return translated.charAt(0).toUpperCase() + translated.slice(1);
  }
  return translated;
}

// ── Core analyzer ─────────────────────────────────────────────────────────────
function analyzeText(text, lang, enabledPos) {
  const tokens = text.match(/([a-zA-Z']+|[^a-zA-Z']+)/g) || [];
  const inventory = { noun: [], verb: [], adj: [], adv: [] };
  const seen = new Set();
  let html = '';

  for (const token of tokens) {
    if (!/[a-zA-Z]/.test(token)) {
      html += escapeHtml(token);
      continue;
    }

    const lower = token.replace(/'/g, '').toLowerCase();
    const baseKey = lemmatize(lower);

    if (baseKey && DICT[baseKey] && enabledPos.has(DICT[baseKey].pos)) {
      const entry = DICT[baseKey];
      const translation = matchCase(token, entry[lang]);
      const posClass = entry.pos;

      html += `<span class="word ${posClass}">${escapeHtml(translation)}<span class="src">[${escapeHtml(token)}]</span></span>`;

      const key = `${entry.pos}:${baseKey}`;
      if (!seen.has(key)) {
        seen.add(key);
        inventory[entry.pos].push({ en: baseKey, tr: entry[lang] });
      }
    } else {
      html += escapeHtml(token);
    }
  }

  for (const pos of ['noun', 'verb', 'adj', 'adv']) {
    inventory[pos].sort((a, b) => a.en.localeCompare(b.en));
  }

  return { html, inventory };
}

function escapeHtml(str) {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// ── UI ────────────────────────────────────────────────────────────────────────
const tabs       = document.querySelectorAll('.tab-btn');
const panels     = document.querySelectorAll('.tab-panel');
const analyzeBtn = document.getElementById('analyze-btn');
const textarea   = document.getElementById('text-input');
const langBtns   = document.querySelectorAll('.lang-btn');
const posBtns    = document.querySelectorAll('.pos-btn');
const annotated  = document.getElementById('annotated-text');
const invTable   = document.getElementById('inv-tbody');
const countEl    = document.getElementById('word-count');

function switchTab(id) {
  tabs.forEach(t => t.classList.toggle('active', t.dataset.tab === id));
  panels.forEach(p => p.classList.toggle('active', p.id === 'panel-' + id));
}

tabs.forEach(t => t.addEventListener('click', () => switchTab(t.dataset.tab)));

function getLang() {
  return document.querySelector('.lang-btn.active')?.dataset.lang || 'es';
}

function getEnabledPos() {
  const set = new Set();
  document.querySelectorAll('.pos-btn.active').forEach(b => set.add(b.dataset.pos));
  return set;
}

langBtns.forEach(b => {
  b.addEventListener('click', () => {
    langBtns.forEach(x => x.classList.remove('active'));
    b.classList.add('active');
  });
});

posBtns.forEach(b => {
  b.addEventListener('click', () => b.classList.toggle('active'));
});

analyzeBtn.addEventListener('click', () => {
  const text = textarea.value.trim();
  if (!text) return;

  const lang = getLang();
  const enabledPos = getEnabledPos();
  const { html, inventory } = analyzeText(text, lang, enabledPos);

  annotated.innerHTML = html;

  const maxRows = Math.max(
    inventory.noun.length,
    inventory.verb.length,
    inventory.adj.length,
    inventory.adv.length
  );

  invTable.innerHTML = '';
  for (let i = 0; i < maxRows; i++) {
    const tr = document.createElement('tr');
    for (const pos of ['noun', 'verb', 'adj', 'adv']) {
      const tdEn = document.createElement('td');
      const tdTr = document.createElement('td');
      const item = inventory[pos][i];
      if (item) {
        tdEn.textContent = item.en;
        tdEn.className = `col-en ${pos}`;
        tdTr.textContent = item.tr;
        tdTr.className = `col-tr ${pos}`;
      }
      tr.appendChild(tdEn);
      tr.appendChild(tdTr);
    }
    invTable.appendChild(tr);
  }

  const total = inventory.noun.length + inventory.verb.length + inventory.adj.length + inventory.adv.length;
  countEl.textContent = `${total} word${total !== 1 ? 's' : ''} translated`;

  switchTab('results');
});

// Load dictionary then enable the button
analyzeBtn.disabled = true;
analyzeBtn.textContent = 'Loading…';
loadDict().then(() => {
  analyzeBtn.disabled = false;
  analyzeBtn.textContent = 'Analyze →';
});
