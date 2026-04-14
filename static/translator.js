// Uses DSWAP from dict-swap.js

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

function getEnabledPosSet() {
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

posBtns.forEach(b => b.addEventListener('click', () => b.classList.toggle('active')));

analyzeBtn.addEventListener('click', () => {
  const text = textarea.value.trim();
  if (!text) return;

  const lang       = getLang();
  const enabledPos = getEnabledPosSet();
  const { html, inventory } = DSWAP.swap(text, lang, enabledPos);

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
        tdEn.className   = `col-en ${pos}`;
        tdTr.textContent = item.tr;
        tdTr.className   = `col-tr ${pos}`;
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
analyzeBtn.disabled    = true;
analyzeBtn.textContent = 'Loading…';
DSWAP.load().then(() => {
  analyzeBtn.disabled    = false;
  analyzeBtn.textContent = 'Analyze →';
});
