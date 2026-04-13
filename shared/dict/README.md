# Shared Dictionary

Language dictionaries in JSON format — consumed by both web and iOS.

## Format

```json
{
  "food":  { "pos": "noun", "es": "comida", "fr": "nourriture" },
  "run":   { "pos": "verb", "es": "correr", "fr": "courir" },
  ...
}
```

## Files

- `en_es_fr.json` — English source with Spanish + French translations (todo: export from web/static/translator.js)

## Todo

- Export current ~220-word dictionary from translator.js to en_es_fr.json
- Grow to ~5000 words using frequency-ranked source (Wiktionary / OPUS corpus)
- iOS: load as bundle resource, parse once at app launch, keep in memory (~300KB)
- Web: fetch once, cache in localStorage
