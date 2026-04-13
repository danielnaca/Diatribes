# Diatribes - Spanish Language Practice App

A conversational AI app that helps you practice Spanish through natural conversations. The AI mixes English and Spanish mid-sentence, and you control the ratio with a slider.

## How it works

1. You speak (or type) about anything — this isn't a language class, it's a real conversation
2. If you make a Spanish grammar mistake, the AI corrects you and asks you to try again
3. After you retry, the AI gives its conversational response
4. The AI's response mixes English and Spanish based on where you set the slider
5. Words you struggle with are tracked

## Setup

### Prerequisites

- Python 3.10+
- An Anthropic API key (for Claude - the conversation brain)
- An OpenAI API key (for Whisper - speech-to-text)

### Install

```bash
git clone <repo-url>
cd Diatribes
pip install -r requirements.txt
```

### Configure API keys

Create a `.env` file in the project root:

```
ANTHROPIC_API_KEY=sk-ant-...your-key...
OPENAI_API_KEY=sk-proj-...your-key...
```

This file is gitignored and won't be committed.

### Run

```bash
uvicorn server:app --host 0.0.0.0 --port 8000
```

Then open in your browser:

- **On the same computer:** http://localhost:8000
- **On your phone (same Wi-Fi):** http://YOUR_COMPUTER_IP:8000
  - To find your IP: `ipconfig` (Windows) or `ifconfig` / `ip addr` (Mac/Linux)
  - Example: http://192.168.1.42:8000

**Important:** Microphone access requires either `localhost` or HTTPS. If accessing from your phone via IP, some browsers may block the mic. If that happens, you can still use the text input to chat, or set up HTTPS with a local cert.

## Using the app

### Controls

- **Slider (EN --- ES):** Controls how much Spanish the AI uses in its responses. All the way left = mostly English with a few Spanish words. All the way right = mostly Spanish.
- **Corrections toggle:** When on, the AI will correct your Spanish mistakes before responding. When off, it just responds normally.
- **Mic button:** Tap to start recording, tap again to stop. Your speech is transcribed and sent to the AI.
- **Text input:** Type instead of speaking. Useful for testing or if mic isn't available.
- **Words button:** Shows a list of Spanish words you've used incorrectly across the session.
- **Skip retry:** Appears after a correction. Tap if you don't want to re-speak the corrected sentence.

### Conversation flow (with corrections on)

1. Tap mic, say something (mix of English/Spanish is fine)
2. Your words appear as a message
3. If you made a Spanish error → a red correction message appears and is read aloud
4. Tap mic again and try saying it correctly
5. The AI then gives its conversational response (read aloud)

If you didn't make any errors, step 3-4 are skipped and you get the response directly.

## Tech stack

- **Backend:** Python / FastAPI
- **Speech-to-text:** OpenAI Whisper API
- **Conversation AI:** Claude (Anthropic)
- **Text-to-speech:** Browser Web Speech API (uses device's built-in voices)
- **Frontend:** Vanilla HTML/CSS/JS, mobile-first design

## Notes

- The TTS uses your device's Spanish voice. Quality varies by device — iOS tends to have good Spanish voices.
- Whisper handles mixed English/Spanish speech well, so speak naturally.
- Conversation history is kept in memory (browser session). Refreshing the page starts a new conversation.
- Trouble words are tracked server-side in memory. They reset when the server restarts.
