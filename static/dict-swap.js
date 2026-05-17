// Shared deterministic POS swap module
// Exposes window.DSWAP — used by both app.js and translator.js

const DSWAP = (() => {
  let dict = {};

  const LANG_CODE = {
    Spanish:    'es',
    French:     'fr',
    Italian:    'es', // fallback until Italian dict added
    German:     'es',
    Portuguese: 'es',
    Japanese:   'es',
    Mandarin:   'es',
    Arabic:     'es',
    Dutch:      'es',
    Russian:    'es',
    Korean:     'es',
  };

  // plural UI names → singular pos keys used in dict
  const POS_PLURAL = {
    nouns: 'noun', verbs: 'verb', adjectives: 'adj', adverbs: 'adv',
  };

  async function load() {
    if (Object.keys(dict).length > 0) return; // already loaded
    const res = await fetch('/shared/dict/en_es_fr.json');
    dict = await res.json();
  }

  function lemmatize(word) {
    if (dict[word]) return word;

    if (word.length > 4 && word.endsWith('ing')) {
      const stem = word.slice(0, -3);
      if (dict[stem]) return stem;
      if (stem.length > 2 && stem[stem.length - 1] === stem[stem.length - 2]) {
        const s = stem.slice(0, -1);
        if (dict[s]) return s;
      }
      if (dict[stem + 'e']) return stem + 'e';
    }
    if (word.length > 3 && word.endsWith('ed')) {
      const stem = word.slice(0, -2);
      if (dict[stem]) return stem;
      if (dict[stem + 'e']) return stem + 'e';
      if (stem.length > 1 && stem[stem.length - 1] === stem[stem.length - 2]) {
        const s = stem.slice(0, -1);
        if (dict[s]) return s;
      }
    }
    if (word.length > 3 && word.endsWith('es')) {
      const stem = word.slice(0, -2);
      if (dict[stem]) return stem;
    }
    if (word.length > 2 && word.endsWith('s')) {
      const stem = word.slice(0, -1);
      if (dict[stem]) return stem;
    }
    if (word.length > 4 && word.endsWith('est')) {
      const stem = word.slice(0, -3);
      if (dict[stem]) return stem;
      if (dict[stem + 'e']) return stem + 'e';
    }
    if (word.length > 3 && word.endsWith('er')) {
      const stem = word.slice(0, -2);
      if (dict[stem]) return stem;
      if (dict[stem + 'e']) return stem + 'e';
    }
    if (word.length > 3 && word.endsWith('ly')) {
      const stem = word.slice(0, -2);
      if (dict[stem]) return stem;
      if (dict[stem + 'e']) return stem + 'e';
    }
    return null;
  }

  function matchCase(original, translated) {
    if (original[0] === original[0].toUpperCase() && original[0] !== original[0].toLowerCase()) {
      return translated.charAt(0).toUpperCase() + translated.slice(1);
    }
    return translated;
  }

  function escapeHtml(str) {
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  // Core swap: returns { html, plain, inventory }
  // lang: 'es' | 'fr'
  // enabledPos: Set of 'noun' | 'verb' | 'adj' | 'adv'
  function swap(text, lang, enabledPos) {
    const tokens = text.match(/([a-zA-Z']+|[^a-zA-Z']+)/g) || [];
    const inventory = { noun: [], verb: [], adj: [], adv: [] };
    const seen = new Set();
    let html = '';
    let plain = '';

    for (const token of tokens) {
      if (!/[a-zA-Z]/.test(token)) {
        html  += escapeHtml(token);
        plain += token;
        continue;
      }

      const lower   = token.replace(/'/g, '').toLowerCase();
      const baseKey = lemmatize(lower);

      if (baseKey && dict[baseKey] && enabledPos.has(dict[baseKey].pos)) {
        const entry       = dict[baseKey];
        const translation = matchCase(token, entry[lang]);
        const posClass    = entry.pos;

        html  += `<span class="word ${posClass}" data-src="${escapeHtml(token)}" data-tr="${escapeHtml(translation)}" data-pos="${posClass}">${escapeHtml(translation)}</span>`;
        plain += translation;

        const key = `${entry.pos}:${baseKey}`;
        if (!seen.has(key)) {
          seen.add(key);
          inventory[entry.pos].push({ en: baseKey, tr: entry[lang] });
        }
      } else {
        html  += escapeHtml(token);
        plain += token;
      }
    }

    for (const pos of ['noun', 'verb', 'adj', 'adv']) {
      inventory[pos].sort((a, b) => a.en.localeCompare(b.en));
    }

    return { html, plain, inventory };
  }

  // Convenience wrapper: takes UI values directly
  function swapFromUI(text, languageName, posSelections) {
    const lang = LANG_CODE[languageName] || 'es';
    const enabledPos = new Set(posSelections.map(p => POS_PLURAL[p]).filter(Boolean));
    return swap(text, lang, enabledPos);
  }

  return { load, swap, swapFromUI };
})();
