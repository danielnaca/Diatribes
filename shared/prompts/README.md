# Shared Prompts

System prompts as plain text — identical strings used by web and iOS.

## Files (todo: extract from server.py)

- `system_base.txt` — base conversation prompt
- `system_free_mix.txt` — free word mixing instructions
- `system_corrections.txt` — grammar correction logic

## Note

The prompts ARE the algorithm. They work identically whether called from
Python (web), Swift (iOS), or any other HTTP client. Keep them here so
both platforms stay in sync.
