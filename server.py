import json
import os
import tempfile

from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

load_dotenv()

from anthropic import Anthropic
from openai import OpenAI

app = FastAPI()

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
            transcript = openai_client.audio.transcriptions.create(
                model="whisper-1",
                file=audio_file,
            )
        return {"text": transcript.text}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        os.unlink(temp_path)


@app.post("/api/respond")
async def respond(
    user_text: str = Form(...),
    slider_value: int = Form(default=30),
    correction_on: bool = Form(default=True),
    conversation_history: str = Form(default="[]"),
):
    history = json.loads(conversation_history)

    if correction_on:
        correction_block = (
            "CORRECTION TASK: Check the user's message for any Spanish grammar, "
            "vocabulary, or conjugation errors. If errors exist, provide the "
            "corrected version of their FULL message in the 'correction' field. "
            "If they spoke only English or their Spanish was correct, set 'correction' "
            "to null. List specific Spanish words they misused in 'trouble_words'."
        )
    else:
        correction_block = (
            "Do NOT correct the user. Set 'correction' to null and 'trouble_words' to null."
        )

    system_prompt = f"""You are a friendly, natural conversational partner helping someone practice Spanish. Have genuine, interesting conversations about whatever they want — be curious, thoughtful, and engaged. This is NOT a language class — it's a real conversation that happens to help with language practice.

LANGUAGE MIX: Approximately {slider_value}% of your response words should be in Spanish, the rest in English. Mix languages naturally WITHIN sentences.

Examples at different levels:
- 10%: "That's really cool! I think spending time with your familia is so important."
- 30%: "I love that! Going to the playa during verano is the best. Do you go with amigos?"
- 50%: "Que buena idea! Me encanta the way you think about it. Has tried making comida mexicana?"
- 70%: "Eso es genial! Me encanta hablar de these things. Que tipo de musica te gusta when you relax?"
- 90%: "Increible! Eso suena como una experiencia maravillosa. Me encantaria saber mas about what paso despues."

{correction_block}

Respond ONLY with valid JSON, no markdown fences:
{{"correction": "corrected full message or null", "response": "your mixed-language reply", "trouble_words": ["words"] or null}}"""

    messages = history + [{"role": "user", "content": user_text}]

    response = anthropic_client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=1024,
        system=system_prompt,
        messages=messages,
    )

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

    return result


@app.get("/api/trouble-words")
async def get_trouble_words():
    return {"words": trouble_words}


app.mount("/static", StaticFiles(directory="static"), name="static")


@app.get("/")
async def root():
    return FileResponse("static/index.html")
