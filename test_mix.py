#!/usr/bin/env python3
"""
Test language mix accuracy at different slider values.
Uses Claude Haiku to measure actual French word percentage in responses.
"""

import json
import re
import requests
from dotenv import load_dotenv
from anthropic import Anthropic

load_dotenv()

BASE_URL = "http://localhost:8000"
client = Anthropic()

TEST_PROMPTS = [
    "What do you like to do on weekends?",
    "Tell me about your favorite food.",
    "What's the weather like today?",
    "Do you like to travel?",
    "What kind of music do you enjoy?",
]

SLIDER_VALUES = [0, 25, 50, 75, 100]


def measure_french_percentage(text: str) -> tuple[float, str]:
    """Use Claude Haiku to count French vs English words. Returns (percentage, explanation)."""
    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=300,
        messages=[{
            "role": "user",
            "content": f"""Analyze this text word by word. Count:
- Total words
- French words (words belonging to French: le, la, les, de, du, est, je, tu, il, etc.)
- English words (words belonging to English: the, a, is, I, you, it, etc.)

Proper nouns and numbers are neutral — don't count them.

Reply ONLY with valid JSON:
{{"total": 0, "french": 0, "english": 0, "pct_french": 0.0, "sample_french": [], "sample_english": []}}

Text: "{text}"
""",
        }]
    )

    raw = response.content[0].text.strip()
    # strip markdown fences if present
    raw = re.sub(r"^```[a-z]*\n?", "", raw)
    raw = re.sub(r"\n?```$", "", raw)

    try:
        data = json.loads(raw)
        pct = data.get("pct_french", 0.0)
        fr_samples = data.get("sample_french", [])[:5]
        en_samples = data.get("sample_english", [])[:5]
        detail = f"FR: {fr_samples} | EN: {en_samples}"
        return float(pct), detail
    except Exception as e:
        # fallback: search for pct_french
        m = re.search(r'"pct_french":\s*([\d.]+)', raw)
        if m:
            return float(m.group(1)), "(parse fallback)"
        print(f"    [PARSE ERROR] {e}\n    Raw: {raw[:200]}")
        return 0.0, "parse error"


def call_server(prompt: str, slider_value: int) -> str:
    resp = requests.post(
        f"{BASE_URL}/api/respond",
        data={
            "user_text": prompt,
            "slider_value": slider_value,
            "length_value": 2,
            "correction_on": False,
            "conversation_history": "[]",
        },
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json().get("response", "")


def test_slider(slider_value: int) -> dict:
    print(f"\n── {slider_value}% French target ──────────────────────────")
    measurements = []

    for prompt in TEST_PROMPTS:
        try:
            response_text = call_server(prompt, slider_value)
            actual_pct, detail = measure_french_percentage(response_text)
            error = abs(slider_value - actual_pct)
            measurements.append({"prompt": prompt, "response": response_text,
                                  "actual": actual_pct, "error": error})
            print(f"  {actual_pct:5.1f}% (err {error:4.1f}) | {response_text[:70]}…")
            print(f"           {detail}")
        except Exception as e:
            print(f"  ERROR: {e}")

    if not measurements:
        return {"target": slider_value, "avg_actual": 0.0, "avg_error": 0.0, "measurements": []}

    avg_actual = sum(m["actual"] for m in measurements) / len(measurements)
    avg_error = sum(m["error"] for m in measurements) / len(measurements)
    print(f"  → avg actual: {avg_actual:.1f}%  avg error: {avg_error:.1f}%")
    return {"target": slider_value, "avg_actual": avg_actual, "avg_error": avg_error,
            "measurements": measurements}


def main():
    print("Language mix accuracy test")
    print("=" * 60)

    all_results = []
    for v in SLIDER_VALUES:
        all_results.append(test_slider(v))

    print("\n\n═══ SUMMARY ═══════════════════════════════")
    print(f"{'Target':>8} │ {'Actual':>8} │ {'Error':>8}")
    print("─" * 34)
    for r in all_results:
        bar = "█" * int(r["avg_actual"] / 5)
        print(f"{r['target']:>7}% │ {r['avg_actual']:>7.1f}% │ {r['avg_error']:>7.1f}%  {bar}")

    mae = sum(r["avg_error"] for r in all_results) / len(all_results)
    print(f"\nMean absolute error across all targets: {mae:.1f}%")

    with open("mix_test_results.json", "w") as f:
        json.dump(all_results, f, indent=2, ensure_ascii=False)
    print("Full results → mix_test_results.json")


if __name__ == "__main__":
    main()
