import json
import os
import re
import sqlite3
import tempfile
import time
from datetime import datetime

from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse, Response
from fastapi.staticfiles import StaticFiles

load_dotenv()

from anthropic import Anthropic
from openai import OpenAI

app = FastAPI()

# ── Deterministic POS swapper ─────────────────────────────────────────────────
_DICT_PATH = os.path.join(os.path.dirname(__file__), "shared", "dict", "en_es_fr.json")
with open(_DICT_PATH, encoding="utf-8") as _f:
    POS_DICT: dict = json.load(_f)

LANG_CODE = {"Spanish": "es", "French": "fr"}

POS_MAP = {"nouns": "noun", "verbs": "verb", "adjectives": "adj", "adverbs": "adv"}

def _lemmatize(word: str):
    if word in POS_DICT:
        return word
    # -ing
    if len(word) > 4 and word.endswith("ing"):
        stem = word[:-3]
        if stem in POS_DICT: return stem
        if len(stem) > 2 and stem[-1] == stem[-2]:
            s = stem[:-1]
            if s in POS_DICT: return s
        if stem + "e" in POS_DICT: return stem + "e"
    # -ed
    if len(word) > 3 and word.endswith("ed"):
        stem = word[:-2]
        if stem in POS_DICT: return stem
        if stem + "e" in POS_DICT: return stem + "e"
        if len(stem) > 1 and stem[-1] == stem[-2]:
            s = stem[:-1]
            if s in POS_DICT: return s
    # -es
    if len(word) > 3 and word.endswith("es"):
        stem = word[:-2]
        if stem in POS_DICT: return stem
    # -s
    if len(word) > 2 and word.endswith("s"):
        stem = word[:-1]
        if stem in POS_DICT: return stem
    # -est / -er
    if len(word) > 4 and word.endswith("est"):
        stem = word[:-3]
        if stem in POS_DICT: return stem
        if stem + "e" in POS_DICT: return stem + "e"
    if len(word) > 3 and word.endswith("er"):
        stem = word[:-2]
        if stem in POS_DICT: return stem
        if stem + "e" in POS_DICT: return stem + "e"
    return None

def pos_swap(text: str, lang_code: str, enabled_pos: set[str]) -> str:
    tokens = re.findall(r"[a-zA-Z']+|[^a-zA-Z']+", text)
    out = []
    for token in tokens:
        if not any(c.isalpha() for c in token):
            out.append(token)
            continue
        lower = token.replace("'", "").lower()
        base = _lemmatize(lower)
        if base and POS_DICT.get(base, {}).get("pos") in enabled_pos:
            translation = POS_DICT[base].get(lang_code, token)
            # preserve capitalisation
            if token[0].isupper():
                translation = translation[0].upper() + translation[1:]
            out.append(translation)
        else:
            out.append(token)
    return "".join(out)

BUILD_TIME = datetime.now().strftime("%H:%M:%S")

anthropic_client = Anthropic()
openai_client = OpenAI()

# ── Words database ────────────────────────────────────────────────────────────
_DB_PATH = os.environ.get("DB_PATH", os.path.join(os.path.dirname(__file__), "words.db"))

def _db():
    conn = sqlite3.connect(_DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def _init_db():
    with _db() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS words (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                english     TEXT    NOT NULL,
                translation TEXT    NOT NULL,
                language    TEXT    NOT NULL,
                pos         TEXT    NOT NULL,
                date_saved  TEXT    NOT NULL DEFAULT (datetime('now')),
                tries       INTEGER NOT NULL DEFAULT 0,
                successes   INTEGER NOT NULL DEFAULT 0,
                hidden      INTEGER NOT NULL DEFAULT 0
            )
        """)
        conn.commit()

try:
    _init_db()
except Exception:
    pass


@app.post("/api/transcribe")
async def transcribe(audio: UploadFile = File(...)):
    audio_bytes = await audio.read()
    ext_map = {
        "audio/webm": ".webm",
        "audio/mp4": ".mp4",
        "audio/ogg": ".ogg",
        "audio/mpeg": ".mp3",
        "audio/wav": ".wav",
    }
    content_type = (audio.content_type or "audio/webm").split(";")[0]
    ext = ext_map.get(content_type, ".webm")

    with tempfile.NamedTemporaryFile(suffix=ext, delete=False) as f:
        f.write(audio_bytes)
        temp_path = f.name

    try:
        with open(temp_path, "rb") as audio_file:
            t0 = time.monotonic()
            transcript = openai_client.audio.transcriptions.create(
                model="whisper-1",
                file=audio_file,
            )
            whisper_ms = round((time.monotonic() - t0) * 1000)
        return {"text": transcript.text, "whisper_ms": whisper_ms}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        os.unlink(temp_path)


OPENAI_VOICES = {"alloy", "echo", "fable", "onyx", "nova", "shimmer"}

# Google Neural2 voice name → (languageCode, voiceName)
GOOGLE_VOICES = {
    "google-fr-a": ("fr-FR", "fr-FR-Neural2-A"),  # female
    "google-fr-b": ("fr-FR", "fr-FR-Neural2-B"),  # male
    "google-fr-c": ("fr-FR", "fr-FR-Neural2-C"),  # female
    "google-es-a": ("es-ES", "es-ES-Neural2-A"),  # female
    "google-es-b": ("es-ES", "es-ES-Neural2-B"),  # male
}

@app.post("/api/speak")
async def speak(text: str = Form(...), voice: str = Form(default="nova"), language: str = Form(default="French"), speaking_rate: float = Form(default=1.0)):
    # Strip bracket hints (immersion mode) and asterisks (translation pairs)
    text = re.sub(r'\s*\[.*?\]', '', text).strip()
    text = text.replace('*', '')

    if voice in GOOGLE_VOICES:
        lang_code, voice_name = GOOGLE_VOICES[voice]
        try:
            t0 = time.monotonic()
            resp = __import__('requests').post(
                f"https://texttospeech.googleapis.com/v1/text:synthesize?key={os.environ['GOOGLE_TTS_KEY']}",
                json={
                    "input": {"text": text},
                    "voice": {"languageCode": lang_code, "name": voice_name},
                    "audioConfig": {"audioEncoding": "MP3", "speakingRate": max(0.25, min(4.0, speaking_rate))},
                },
            )
            resp.raise_for_status()
            import base64
            audio = base64.b64decode(resp.json()["audioContent"])
            tts_ms = round((time.monotonic() - t0) * 1000)
            return Response(content=audio, media_type="audio/mpeg", headers={"X-TTS-Ms": str(tts_ms)})
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))

    # OpenAI fallback
    if voice not in OPENAI_VOICES:
        voice = "nova"
    try:
        t0 = time.monotonic()
        response = openai_client.audio.speech.create(
            model="gpt-4o-mini-tts",
            voice=voice,
            input=text,
            instructions=(
                f"Speak with a strong, authentic native {language} accent throughout. "
                f"You grew up in {language}-speaking country and have a thick {language} accent that never goes away. "
                f"Apply {language} phonology, rhythm, and intonation to every word — including English words. "
                f"For example: R's are pronounced the {language} way, vowels have {language} quality, stress patterns follow {language} rules. "
                f"Never slip into an American or British accent, not even for a single word."
            ),
        )
        tts_ms = round((time.monotonic() - t0) * 1000)
        return Response(
            content=response.content,
            media_type="audio/mpeg",
            headers={"X-TTS-Ms": str(tts_ms)},
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/respond")
async def respond(
    user_text: str = Form(...),
    length_value: int = Form(default=2),
    correction_on: bool = Form(default=True),
    language: str = Form(default="French"),
    conversation_history: str = Form(default="[]"),
    approach: str = Form(default="pos"),
    pos_selections: str = Form(default="[]"),
):
    history = json.loads(conversation_history)
    pos_list: list[str] = json.loads(pos_selections)

    if correction_on:
        correction_block = (
            f"CORRECTION TASK: Check the user's message for any {language} grammar, "
            f"vocabulary, or conjugation errors. If errors exist, provide the "
            f"corrected version of their FULL message in the 'correction' field. "
            f"If they spoke only English or their {language} was correct, set 'correction' "
            f"to null. List specific {language} words they misused in 'trouble_words'."
        )
    else:
        correction_block = (
            "Do NOT correct the user. Set 'correction' to null and 'trouble_words' to null."
        )

    length_instructions = {
        1: "Keep responses very short — 1 sentence maximum.",
        2: "Keep responses brief — 2 sentences maximum.",
        3: "Use 3–4 sentences.",
        4: "Give a fuller response of 4–6 sentences.",
        5: "Feel free to be expansive — go into detail, ask follow-ups, elaborate.",
    }

    # Build language rule based on approach
    L = language
    if approach == "pos":
        lang_rule = (
            f"OUTPUT LANGUAGE — THIS IS YOUR MOST IMPORTANT RULE: Write your response in English and English only. "
            f"You are strictly forbidden from using any {L} words, phrases, or sentences in the 'response' field. "
            f"It does not matter what language the user writes in. Even if they write entirely in {L}, you must respond in English. "
            f"The {L} word substitution is handled automatically by the app after you reply — you do not need to do it. "
            f"Your only job is to write natural, engaging English."
        )
    elif approach == "sentence_alt":
        lang_rule = (
            f"LANGUAGE RULE (highest priority): Alternate languages sentence by sentence. "
            f"The FIRST sentence must be in English. The SECOND in {L}. "
            f"The THIRD in English. And so on, strictly alternating. "
            f"Never mix languages within a single sentence."
        )
    elif approach == "immersion":
        lang_rule = (
            f"LANGUAGE RULE (highest priority): Respond entirely in {L}. "
            f"After any word that might be unfamiliar to an intermediate learner, "
            f"add its English translation in square brackets immediately after. "
            f"Example: 'Je vais au marché [market] ce soir pour acheter des légumes [vegetables] frais [fresh].'"
        )
    elif approach == "translation":
        lang_rule = (
            f"LANGUAGE RULE (highest priority): After every English sentence you write, "
            f"immediately follow it with the {L} translation in italics (use *asterisks*). "
            f"Pattern: English sentence. *{L} translation.* English sentence. *{L} translation.*"
        )
    else:
        lang_rule = "Respond naturally in English."

    pos_reminder = f"\nREMINDER: Your 'response' must be in English only — no {L} words whatsoever." if approach == "pos" else ""

    system_prompt = f"""{lang_rule}

You are a friendly conversational partner helping someone practice {language}. Have genuine, interesting conversations — be curious and engaged.

LENGTH: {length_instructions[max(1, min(5, length_value))]}

{correction_block}

Respond ONLY with valid JSON, no markdown fences:
{{"correction": "corrected full message or null", "response": "your reply", "trouble_words": ["words"] or null}}{pos_reminder}"""

    messages = history + [{"role": "user", "content": user_text}]

    t0 = time.monotonic()
    response = anthropic_client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=1024,
        system=system_prompt,
        messages=messages,
    )
    claude_ms = round((time.monotonic() - t0) * 1000)

    try:
        result = json.loads(response.content[0].text)
    except json.JSONDecodeError:
        result = {
            "correction": None,
            "response": response.content[0].text,
            "trouble_words": None,
        }

    # Second pass rewrite based on approach
    rewrite_ms = None

    # pos approach: swap handled on the frontend (deterministic dict lookup)
    # server returns plain English so Claude sees clean conversation history

    result["timings"] = {"claude_ms": claude_ms, "rewrite_ms": rewrite_ms}
    return result


@app.post("/api/words")
async def save_word(
    english: str = Form(...),
    translation: str = Form(...),
    language: str = Form(...),
    pos: str = Form(...),
):
    with _db() as conn:
        existing = conn.execute(
            "SELECT id FROM words WHERE english=? AND language=?",
            (english.lower(), language)
        ).fetchone()
        if existing:
            return {"id": existing["id"], "already_saved": True}
        cursor = conn.execute(
            "INSERT INTO words (english, translation, language, pos) VALUES (?,?,?,?)",
            (english.lower(), translation, language, pos)
        )
        conn.commit()
        return {"id": cursor.lastrowid, "already_saved": False}


@app.get("/api/words")
async def list_words(language: str = None):
    with _db() as conn:
        if language:
            rows = conn.execute(
                "SELECT * FROM words WHERE language=? ORDER BY date_saved DESC",
                (language,)
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM words ORDER BY date_saved DESC"
            ).fetchall()
        return {"words": [dict(r) for r in rows]}


@app.delete("/api/words/{word_id}")
async def delete_word(word_id: int):
    with _db() as conn:
        conn.execute("DELETE FROM words WHERE id=?", (word_id,))
        conn.commit()
    return {"ok": True}


@app.patch("/api/words/{word_id}")
async def update_word(
    word_id: int,
    tries: int = Form(default=None),
    successes: int = Form(default=None),
    hidden: int = Form(default=None),
):
    updates = {}
    if tries is not None: updates["tries"] = tries
    if successes is not None: updates["successes"] = successes
    if hidden is not None: updates["hidden"] = hidden
    if not updates:
        return {"ok": True}
    set_clause = ", ".join(f"{k}=?" for k in updates)
    with _db() as conn:
        conn.execute(f"UPDATE words SET {set_clause} WHERE id=?", (*updates.values(), word_id))
        conn.commit()
    return {"ok": True}


@app.get("/api/build-time")
async def get_build_time():
    static_dir = os.path.join(os.path.dirname(__file__), "static")
    latest = max(
        os.path.getmtime(os.path.join(static_dir, f))
        for f in os.listdir(static_dir)
        if f.endswith((".html", ".js", ".css"))
    )
    frontend_time = datetime.fromtimestamp(latest).strftime("%H:%M:%S")
    return {"server": BUILD_TIME, "frontend": frontend_time}



@app.post("/api/fetch-article")
async def fetch_article(url: str = Form(...)):
    import json as _json
    import trafilatura

    downloaded = trafilatura.fetch_url(url)
    if not downloaded:
        raise HTTPException(status_code=400, detail="Could not fetch URL")

    result = trafilatura.extract(downloaded, with_metadata=True, output_format="json",
                                  include_comments=False, include_tables=False)
    if not result:
        raise HTTPException(status_code=400, detail="Could not extract article content")

    data = _json.loads(result)
    title = data.get("title") or data.get("sitename") or url
    text  = data.get("text") or ""
    paragraphs = [p.strip() for p in text.split("\n") if p.strip()]
    excerpt = (paragraphs[0][:150] + "…") if paragraphs else ""
    return {"title": title, "url": url, "excerpt": excerpt, "paragraphs": paragraphs}


@app.post("/api/fetch-feed")
async def fetch_feed(url: str = Form(...)):
    import feedparser
    import requests as _req
    import re as _re
    import time as _time
    from html import unescape as _unescape
    from urllib.parse import urlparse

    headers = {"User-Agent": "Mozilla/5.0 (compatible; Diatribes/1.0)"}
    try:
        resp = _req.get(url, headers=headers, timeout=10)
        resp.raise_for_status()
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

    feed = feedparser.parse(resp.content)
    if not feed.entries:
        raise HTTPException(status_code=400, detail="No entries found in feed")

    site_url = feed.feed.get("link", url)
    domain = urlparse(site_url).netloc or urlparse(url).netloc
    favicon = f"https://www.google.com/s2/favicons?domain={domain}&sz=32"

    def strip_html(html_text: str) -> str:
        return _unescape(_re.sub(r"<[^>]+>", "", html_text)).strip()

    items = []
    for entry in feed.entries[:30]:
        summary = entry.get("summary", "")
        excerpt = ""
        if summary:
            text = strip_html(summary)
            excerpt = text[:150] + ("…" if len(text) > 150 else "")

        date_str = ""
        if getattr(entry, "published_parsed", None):
            try:
                date_str = _time.strftime("%Y-%m-%dT%H:%M:%SZ", entry.published_parsed)
            except Exception:
                date_str = entry.get("published", "")
        else:
            date_str = entry.get("published", "")

        items.append({
            "title": entry.get("title", "Untitled"),
            "url": entry.get("link", ""),
            "excerpt": excerpt,
            "date": date_str,
            "guid": entry.get("id", entry.get("link", "")),
        })

    return {
        "title": feed.feed.get("title", domain),
        "site_url": site_url,
        "favicon": favicon,
        "items": items,
    }


app.mount("/static", StaticFiles(directory="static"), name="static")
app.mount("/shared", StaticFiles(directory="shared"), name="shared")


@app.get("/")
async def root():
    return FileResponse("static/index.html")
