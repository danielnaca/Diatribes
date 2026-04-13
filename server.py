import json
import os
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
    slider_value: int = Form(default=30),
    length_value: int = Form(default=2),
    correction_on: bool = Form(default=True),
    language: str = Form(default="French"),
    conversation_history: str = Form(default="[]"),
):
    history = json.loads(conversation_history)

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

    def mix_instruction(pct: int) -> str:
        L = language
        if pct == 0:
            return f"Respond ENTIRELY IN ENGLISH. Zero {L} words. Pure English only."
        elif pct <= 15:
            return (
                f"Respond in English. Drop in the occasional {L} word — a noun, a greeting, "
                f"a short phrase — maybe once per sentence at most. Mostly English."
            )
        elif pct <= 35:
            return (
                f"Respond mostly in English but weave in {L} words and phrases regularly. "
                f"Roughly 1 in 4 words should be {L} — nouns, adjectives, short clauses."
            )
        elif pct <= 65:
            return (
                f"Respond in a genuine half-and-half mix — {L} and English roughly equal, "
                f"blended naturally within sentences. Neither language should dominate."
            )
        elif pct <= 85:
            return (
                f"Respond primarily in {L}. English should be a minority — only a word or short phrase "
                f"per sentence at most. Most of each sentence should be {L}."
            )
        elif pct < 100:
            return (
                f"Respond almost entirely in {L}. You may use one or two English words total "
                f"in the whole response, no more. Everything else must be {L}."
            )
        else:
            return (
                f"Respond ENTIRELY IN {L.upper()}. Every single word must be {L}. "
                f"No English whatsoever — not even small words like 'I', 'a', 'the', 'and', 'is'. "
                f"You are a native {L} speaker responding naturally in your language."
            )

    system_prompt = f"""LANGUAGE RULE (highest priority — follow this above all else):
{mix_instruction(slider_value)}

You are a friendly conversational partner helping someone practice {language}. Have genuine, interesting conversations — be curious and engaged. This is NOT a language class, it's a real conversation.

LENGTH: {length_instructions[max(1, min(5, length_value))]}

{correction_block}

Respond ONLY with valid JSON, no markdown fences:
{{"correction": "corrected full message or null", "response": "your mixed-language reply", "trouble_words": ["words"] or null}}"""

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

    # Second pass: rewrite to hit the target mix ratio
    rewrite_ms = None
    if slider_value > 0:
        t1 = time.monotonic()
        rewrite = anthropic_client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=512,
            system=(
                f"You are a text rewriter. Rewrite the given text so that approximately {slider_value}% "
                f"of the words are in {language} and the rest in English. "
                f"Preserve the meaning and tone exactly. "
                f"At 100% use only {language}. At 0% use only English. "
                f"Return ONLY the rewritten text — no explanation, no quotes, nothing else."
            ),
            messages=[{"role": "user", "content": result["response"]}],
        )
        rewrite_ms = round((time.monotonic() - t1) * 1000)
        result["response"] = rewrite.content[0].text.strip()

    result["timings"] = {"claude_ms": claude_ms, "rewrite_ms": rewrite_ms}
    return result


@app.get("/api/trouble-words")
async def get_trouble_words():
    return {"words": trouble_words}


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


@app.get("/")
async def root():
    return FileResponse("static/index.html")
