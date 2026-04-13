# Diatribes — iOS

Swift/SwiftUI Xcode project lives here.

## Architecture notes

- All API calls (Whisper, Claude, OpenAI TTS) go direct from the app — no server
- POS tagging uses Apple's built-in `NLTagger` (zero download, ~95% accuracy)
- Dictionary loaded from `../shared/dict/` at build time (bundle resource)
- System prompts loaded from `../shared/prompts/`
- API keys: `.env` equivalent is a `Secrets.plist` (gitignored) or CloudKit for distribution

## Stack

- SwiftUI — UI
- AVAudioEngine / AVAudioRecorder — mic input
- AVAudioPlayer — TTS playback
- URLSession — API calls
- NaturalLanguage framework — POS tagging
- UserDefaults / CoreData — trouble word persistence
