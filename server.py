import json
import os
import re
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

trouble_words: list[str] = []


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


ALLOWED_VOICES = {"alloy", "echo", "fable", "onyx", "nova", "shimmer"}

@app.post("/api/speak")
async def speak(text: str = Form(...), voice: str = Form(default="nova"), language: str = Form(default="French")):
    if voice not in ALLOWED_VOICES:
        voice = "nova"
    # Strip bracket hints (immersion mode) and asterisks (translation pairs) that shouldn't be spoken
    text = re.sub(r'\s*\[.*?\]', '', text).strip()
    text = text.replace('*', '')
    try:
        t0 = time.monotonic()
        response = openai_client.audio.speech.create(
            model="gpt-4o-mini-tts",
            voice=voice,
            input=text,
            instructions=(
                f"You are a native {language} speaker who learned English as a second language. "
                f"Your {language} accent is always present — it never disappears, not even on a single word. "
                f"Every English word you say carries the full rhythm, intonation, and phonology of a native {language} speaker. "
                f"You cannot turn your accent off. Speak naturally, as if {language} is the only language you have ever truly lived in."
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
        lang_rule = "Respond naturally in English. Have a genuine, engaging conversation."
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

    system_prompt = f"""{lang_rule}

You are a friendly conversational partner helping someone practice {language}. Have genuine, interesting conversations — be curious and engaged.

LENGTH: {length_instructions[max(1, min(5, length_value))]}

{correction_block}

Respond ONLY with valid JSON, no markdown fences:
{{"correction": "corrected full message or null", "response": "your reply", "trouble_words": ["words"] or null}}"""

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

    if result.get("trouble_words"):
        for w in result["trouble_words"]:
            if w.lower() not in [tw.lower() for tw in trouble_words]:
                trouble_words.append(w)

    # Second pass rewrite based on approach
    rewrite_ms = None

    # pos approach: swap handled on the frontend (deterministic dict lookup)
    # server returns plain English so Claude sees clean conversation history

    result["timings"] = {"claude_ms": claude_ms, "rewrite_ms": rewrite_ms}
    return result


@app.get("/api/trouble-words")
async def get_trouble_words():
    return {"words": trouble_words}


# ── Book chapter summarizer ───────────────────────────────────────────────────
CHAPTER_PATTERNS = [
    re.compile(
        r"^\s*chapter\s+(?:\d+|[ivxlcdm]+|one|two|three|four|five|six|seven|eight|"
        r"nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|"
        r"eighteen|nineteen|twenty|twenty[-\s]one|twenty[-\s]two|twenty[-\s]three|"
        r"twenty[-\s]four|twenty[-\s]five)\b.*$",
        re.IGNORECASE | re.MULTILINE,
    ),
    re.compile(r"^\s*part\s+(?:\d+|[ivxlcdm]+)\b.*$", re.IGNORECASE | re.MULTILINE),
    re.compile(r"^\s*#{1,3}\s+\S.*$", re.MULTILINE),
]


def split_into_chapters(text: str) -> list[dict]:
    for pat in CHAPTER_PATTERNS:
        matches = list(pat.finditer(text))
        if len(matches) >= 2:
            chapters = []
            for i, m in enumerate(matches):
                start = m.start()
                end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
                title = m.group(0).strip().lstrip("#").strip()
                body = text[start:end].strip()
                chapters.append({"index": i, "title": title, "body": body})
            return chapters
    # Fallback: ~5000-word chunks
    words = text.split()
    if not words:
        return []
    chunks = [" ".join(words[i:i + 5000]) for i in range(0, len(words), 5000)]
    return [
        {"index": i, "title": f"Section {i + 1}", "body": c}
        for i, c in enumerate(chunks)
    ]


@app.post("/api/book/parse")
async def parse_book(file: UploadFile = File(...)):
    raw = await file.read()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("latin-1", errors="replace")
    chapters = split_into_chapters(text)
    return {"filename": file.filename, "chapters": chapters}


@app.post("/api/book/summarize")
async def summarize_chapter(payload: dict):
    title = (payload.get("title") or "Chapter").strip()
    body = (payload.get("body") or "").strip()
    if not body:
        raise HTTPException(400, "empty chapter body")
    body = body[:60000]
    response = anthropic_client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=600,
        system=(
            "You are a thoughtful literary editor. Summarize the given chapter in "
            "4–6 sentences. Capture key plot beats, character development, and "
            "tone. Plain prose, no bullet points, no preamble."
        ),
        messages=[{"role": "user", "content": f"Title: {title}\n\n{body}"}],
    )
    return {"summary": response.content[0].text.strip()}


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



app.mount("/static", StaticFiles(directory="static"), name="static")
app.mount("/shared", StaticFiles(directory="shared"), name="shared")


@app.get("/")
async def root():
    return FileResponse("static/index.html")
