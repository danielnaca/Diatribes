# Diatribes — Architecture & Platform Notes

## Current State (Web App)

The web app is the development/prototyping environment for iterating on the brain (prompts, language mixing, correction flow, TTS voice behavior). The web version runs as a Python/FastAPI server serving a vanilla HTML/CSS/JS frontend.

### API Stack
- **Speech-to-text:** OpenAI Whisper API
- **Conversation brain:** Claude Sonnet (Anthropic API)
- **Language mix rewrite:** Claude Haiku (second pass to hit target mix ratio)
- **Text-to-speech:** OpenAI gpt-4o-mini-tts (with accent instructions per language)

### Key Endpoints
- `POST /api/transcribe` — audio file → Whisper → text
- `POST /api/respond` — user text + settings → Claude → JSON (correction + response + trouble_words), then Haiku rewrite pass
- `POST /api/speak` — text + voice + language → OpenAI TTS → audio/mpeg
- `GET /api/trouble-words` — accumulated trouble words

---

## iOS App Plan

### Transportability

Almost everything transfers directly. The "algorithm" is entirely in the prompts and the API call sequence. The APIs don't care whether the request comes from Python or Swift.

**Transfers 1:1 (copy-paste portable):**
- All system prompts (language mixing instructions, correction logic, rewrite prompts)
- The conversation flow / state machine (IDLE → RECORDING → PROCESSING → CORRECTION → IDLE)
- The two-pass approach (Sonnet for conversation, Haiku for mix rewrite)
- API call payloads and response parsing
- Trouble word tracking logic

**Changes (just the wrapper):**
- Python `requests` / FastAPI → Swift `URLSession` (direct API calls from device, no server)
- Browser MediaRecorder → `AVAudioEngine` or `AVAudioRecorder`
- Browser audio playback → `AVAudioPlayer`
- HTML/CSS/JS → SwiftUI
- In-memory state → UserDefaults / CoreData / iCloud for persistence

### Auth & Accounts
- Use iCloud / Sign in with Apple — no custom account system
- Slider preferences, trouble words, conversation history all sync via iCloud

### API Keys — Development vs Distribution

**For personal use / TestFlight:**
- API keys can be embedded in the app. Not ideal but functional.

**For App Store release:**
- Need a thin proxy server between the app and the APIs
- Server holds the API keys, app never sees them
- Server also handles subscription verification

### Monetization

Two options (can offer both):

**Subscription:**
- User pays e.g. $10/month via Apple In-App Purchase
- Apple takes 30% → you keep $7
- Estimated API cost per active user: $2-5/month depending on usage
- Server verifies subscription receipt, then proxies API calls

**Credit packs (metered):**
- Consumable In-App Purchase (e.g. $5 = X words/characters of conversation)
- Track usage on server, show remaining balance with progress bar
- Build in 5-10% margin on pricing to account for variable response lengths and rewrite passes
- Good for casual users who don't want a recurring charge

### Server Requirements (for App Store release)

Thin proxy server that:
1. Verifies Apple subscription/purchase receipts
2. Tracks per-user usage (for credit packs)
3. Forwards requests to Whisper, Claude, and OpenAI TTS using server-held API keys
4. Returns responses to the app

The current FastAPI server is very close to what this would look like. Deploy on Railway, Render, or Fly.io.

---

## TTS Cost Comparison

For reference when choosing TTS provider:

| Provider | Cost | Mixed-language quality | Notes |
|---|---|---|---|
| OpenAI gpt-4o-mini-tts | ~$0.60/1M chars | Good, accent instructions work well | Currently using this |
| ElevenLabs | ~$5-99/mo (tiered by chars) | Best for mid-sentence switching | Expensive for heavy use |
| Google Cloud TTS (Neural2) | ~$16/1M chars (~$0.14/session) | Decent | Cheapest at scale |
| Browser Web Speech API | Free | Poor for mixed language | Fallback only |

---

## Development Strategy

1. **Now:** Keep iterating on prompts, mixing accuracy, and correction flow via the web app
2. **When the brain is solid:** Rebuild UI in SwiftUI, same API calls from Swift
3. **For TestFlight / personal use:** Embed keys directly, no server needed
4. **For App Store:** Add thin proxy server, integrate In-App Purchase
