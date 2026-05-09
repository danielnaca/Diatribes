const fileInput  = document.getElementById('file-input');
const uploadBtn  = document.getElementById('upload-btn');
const statusEl   = document.getElementById('status');
const chaptersEl = document.getElementById('chapters');

uploadBtn.addEventListener('click', () => fileInput.click());

fileInput.addEventListener('change', async () => {
    const file = fileInput.files && fileInput.files[0];
    if (!file) return;

    chaptersEl.innerHTML = '';
    setStatus(`Reading ${file.name}…`);
    uploadBtn.disabled = true;

    let chapters;
    try {
        const fd = new FormData();
        fd.append('file', file);
        const res = await fetch('/api/book/parse', { method: 'POST', body: fd });
        if (!res.ok) throw new Error(`parse failed: ${res.status}`);
        const data = await res.json();
        chapters = data.chapters || [];
    } catch (err) {
        setStatus(`Could not read file: ${err.message}`);
        uploadBtn.disabled = false;
        return;
    }

    if (chapters.length === 0) {
        setStatus('No content found in that file.');
        uploadBtn.disabled = false;
        return;
    }

    renderChapterShells(chapters);

    for (let i = 0; i < chapters.length; i++) {
        setStatus(`Summarizing chapter ${i + 1} of ${chapters.length}…`);
        await summarizeOne(chapters[i]);
    }

    setStatus(`Done. ${chapters.length} chapter${chapters.length === 1 ? '' : 's'} summarized.`);
    uploadBtn.disabled = false;
    fileInput.value = '';
});

function setStatus(msg) {
    statusEl.textContent = msg;
}

function renderChapterShells(chapters) {
    chaptersEl.innerHTML = '';
    for (const ch of chapters) {
        const li = document.createElement('li');
        li.className = 'chapter';
        li.dataset.index = String(ch.index);

        const h2 = document.createElement('h2');
        h2.textContent = ch.title;
        li.appendChild(h2);

        const p = document.createElement('p');
        p.className = 'summary placeholder';
        p.textContent = 'Summarizing…';
        li.appendChild(p);

        chaptersEl.appendChild(li);
    }
}

async function summarizeOne(chapter) {
    const li = chaptersEl.querySelector(`li[data-index="${chapter.index}"]`);
    const summaryEl = li.querySelector('.summary');
    summaryEl.className = 'summary placeholder';
    summaryEl.textContent = 'Summarizing…';
    const existingActions = li.querySelector('.actions');
    if (existingActions) existingActions.remove();

    try {
        const res = await fetch('/api/book/summarize', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ title: chapter.title, body: chapter.body }),
        });
        if (!res.ok) {
            const detail = await res.text();
            throw new Error(detail || `HTTP ${res.status}`);
        }
        const data = await res.json();
        summaryEl.className = 'summary';
        summaryEl.textContent = data.summary;
    } catch (err) {
        summaryEl.className = 'summary error';
        summaryEl.textContent = `Error: ${err.message}`;
        const actions = document.createElement('div');
        actions.className = 'actions';
        const retry = document.createElement('button');
        retry.className = 'ghost';
        retry.textContent = 'Retry';
        retry.addEventListener('click', () => summarizeOne(chapter));
        actions.appendChild(retry);
        li.appendChild(actions);
    }
}
