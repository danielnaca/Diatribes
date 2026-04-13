#!/usr/bin/env python3
"""
Research: test different language mixing approaches.
For each approach, test single-pass accuracy, then 2nd-pass accuracy.
Use Claude Haiku as judge to evaluate how well each rule was followed.
"""

import json
import time
from dotenv import load_dotenv
from anthropic import Anthropic

load_dotenv()
client = Anthropic()

LANGUAGE = "French"
MODEL_CONV = "claude-sonnet-4-20250514"
MODEL_FAST = "claude-haiku-4-5-20251001"

PROMPTS = [
    "What do you like to do on weekends?",
    "Tell me about your favorite food.",
    "Do you prefer the city or the countryside?",
    "What kind of music do you enjoy?",
]

# ── Approach definitions ───────────────────────────────────────────────────────

APPROACHES = {

    "percentage_50": {
        "name": "Word percentage (50%)",
        "description": "50% of all words must be French, 50% English, mixed within sentences.",
        "system": (
            "LANGUAGE RULE (highest priority): Respond in a genuine half-and-half mix — "
            "French and English roughly equal, blended naturally within sentences. "
            "Neither language should dominate."
        ),
        "judge_question": (
            "Count the French words and the English words separately. "
            "Is the split roughly 50/50? "
            "Reply with JSON: {\"french_pct\": <number>, \"followed\": <true/false>, \"notes\": \"...\"}"
        ),
    },

    "pos_nouns": {
        "name": "POS: nouns in French",
        "description": "All nouns in French, everything else in English.",
        "system": (
            "LANGUAGE RULE (highest priority): Write in English but replace EVERY noun "
            "with its French equivalent. All verbs, adjectives, adverbs, pronouns, "
            "prepositions, and articles stay in English. Only nouns switch to French. "
            "Example: 'I love going to the marché on weekends — the légumes are always so fresh!'"
        ),
        "judge_question": (
            "Check: are all nouns (and only nouns) in French, with everything else in English? "
            "List any violations. "
            "Reply with JSON: {\"nouns_french\": <true/false>, \"violations\": [...], \"followed\": <true/false>}"
        ),
    },

    "pos_verbs_nouns": {
        "name": "POS: nouns + verbs in French",
        "description": "All nouns and verbs in French, everything else in English.",
        "system": (
            "LANGUAGE RULE (highest priority): Write in English but replace EVERY noun AND "
            "every verb with its French equivalent. Keep all adjectives, adverbs, pronouns, "
            "prepositions, and articles in English. "
            "Example: 'I adore aller to the marché — the légumes sont always so fresh!'"
        ),
        "judge_question": (
            "Check: are all nouns and verbs in French, with adjectives/adverbs/pronouns/articles in English? "
            "List violations. "
            "Reply with JSON: {\"followed\": <true/false>, \"violations\": [...], \"accuracy_pct\": <0-100>}"
        ),
    },

    "sentence_alternation": {
        "name": "Sentence alternation",
        "description": "Sentences strictly alternate: English, French, English, French...",
        "system": (
            "LANGUAGE RULE (highest priority): Alternate languages sentence by sentence. "
            "The FIRST sentence must be in English. The SECOND in French. "
            "The THIRD in English. And so on, strictly alternating. "
            "Never mix languages within a single sentence."
        ),
        "judge_question": (
            "Does each sentence strictly alternate between English and French, starting with English? "
            "Label each sentence E or F. "
            "Reply with JSON: {\"pattern\": [\"E\",\"F\",...], \"followed\": <true/false>, \"violations\": [...]}"
        ),
    },

    "clause_switching": {
        "name": "Clause-level switching",
        "description": "Each grammatical clause is in one language, switching at clause boundaries.",
        "system": (
            "LANGUAGE RULE (highest priority): Switch language at clause boundaries — "
            "each independent or dependent clause should be entirely in one language. "
            "Alternate which language each clause uses. Never mix languages mid-clause. "
            "Example: 'I went to the market, mais je n'ai rien trouvé, so I went home, mais c'était quand même une bonne journée.'"
        ),
        "judge_question": (
            "Does each clause stay in one language, alternating between English and French? "
            "List the clauses and their language. "
            "Reply with JSON: {\"followed\": <true/false>, \"clauses\": [{\"text\":\"...\",\"lang\":\"EN/FR\"},...], \"violations\": [...]}"
        ),
    },

    "immersion_hints": {
        "name": "Immersion with hints",
        "description": "Full French, but harder words get an English hint in brackets.",
        "system": (
            "LANGUAGE RULE (highest priority): Respond entirely in French. "
            "However, after any word that might be unfamiliar to an intermediate learner, "
            "add its English translation in square brackets. "
            "Example: 'Je vais au marché [market] ce soir pour acheter des légumes [vegetables] frais [fresh].'"
        ),
        "judge_question": (
            "Is the response primarily in French with English hints in brackets for harder words? "
            "Is it actually in French (not English with French hints)? "
            "Reply with JSON: {\"is_french_primary\": <true/false>, \"hint_count\": <number>, \"followed\": <true/false>}"
        ),
    },

    "translation_pairs": {
        "name": "Translation pairs",
        "description": "Every sentence is said in both languages: English first, then French translation.",
        "system": (
            "LANGUAGE RULE (highest priority): After every sentence you write in English, "
            "immediately follow it with the French translation of that sentence in italics (use *asterisks*). "
            "Pattern: English sentence. *Traduction française.* English sentence. *Traduction française.* "
            "Example: 'I love going to the market on weekends. *J'adore aller au marché le week-end.*'"
        ),
        "judge_question": (
            "Does every English sentence have a French translation immediately after it (in asterisks)? "
            "Reply with JSON: {\"pairs_found\": <number>, \"pairs_missing\": <number>, \"followed\": <true/false>}"
        ),
    },
}

# ── Test runner ────────────────────────────────────────────────────────────────

def generate_response(system: str, prompt: str) -> tuple[str, int]:
    t0 = time.monotonic()
    r = client.messages.create(
        model=MODEL_CONV,
        max_tokens=300,
        system=system + "\n\nRespond conversationally in 2-3 sentences.",
        messages=[{"role": "user", "content": prompt}],
    )
    ms = round((time.monotonic() - t0) * 1000)
    return r.content[0].text.strip(), ms


def rewrite_response(text: str, system: str) -> tuple[str, int]:
    """Second pass: rewrite to better follow the mixing rule."""
    t0 = time.monotonic()
    r = client.messages.create(
        model=MODEL_FAST,
        max_tokens=300,
        system=(
            f"Rewrite the following text to strictly follow this rule:\n{system}\n\n"
            "Preserve the meaning exactly. Return ONLY the rewritten text."
        ),
        messages=[{"role": "user", "content": text}],
    )
    ms = round((time.monotonic() - t0) * 1000)
    return r.content[0].text.strip(), ms


def judge(text: str, question: str) -> dict:
    r = client.messages.create(
        model=MODEL_FAST,
        max_tokens=200,
        system="You are a linguistics judge. Be strict and accurate. Reply ONLY with valid JSON.",
        messages=[{"role": "user", "content": f"Text to evaluate:\n\"{text}\"\n\nQuestion: {question}"}],
    )
    raw = r.content[0].text.strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        return json.loads(raw)
    except:
        return {"raw": raw, "followed": None}


def test_approach(key: str, approach: dict) -> dict:
    print(f"\n{'='*60}")
    print(f"APPROACH: {approach['name']}")
    print(f"{'='*60}")

    results = []
    for prompt in PROMPTS:
        # Single pass
        response_1, ms_1 = generate_response(approach["system"], prompt)
        verdict_1 = judge(response_1, approach["judge_question"])
        followed_1 = verdict_1.get("followed", None)

        # Second pass
        response_2, ms_2 = rewrite_response(response_1, approach["system"])
        verdict_2 = judge(response_2, approach["judge_question"])
        followed_2 = verdict_2.get("followed", None)

        results.append({
            "prompt": prompt,
            "response_1": response_1,
            "ms_1": ms_1,
            "followed_1": followed_1,
            "verdict_1": verdict_1,
            "response_2": response_2,
            "ms_2": ms_2,
            "followed_2": followed_2,
            "verdict_2": verdict_2,
        })

        f1 = "✓" if followed_1 else ("?" if followed_1 is None else "✗")
        f2 = "✓" if followed_2 else ("?" if followed_2 is None else "✗")
        print(f"\n  Prompt: {prompt}")
        print(f"  Pass 1 [{ms_1}ms] {f1}: {response_1[:90]}…")
        print(f"  Pass 2 [{ms_2}ms] {f2}: {response_2[:90]}…")

    valid = [r for r in results if r["followed_1"] is not None]
    acc_1 = sum(1 for r in valid if r["followed_1"]) / len(valid) * 100 if valid else 0
    valid2 = [r for r in results if r["followed_2"] is not None]
    acc_2 = sum(1 for r in valid2 if r["followed_2"]) / len(valid2) * 100 if valid2 else 0
    avg_ms_1 = sum(r["ms_1"] for r in results) / len(results)
    avg_ms_2 = sum(r["ms_2"] for r in results) / len(results)

    print(f"\n  SUMMARY: pass1={acc_1:.0f}% accurate ({avg_ms_1:.0f}ms avg)  |  pass2={acc_2:.0f}% accurate ({avg_ms_2:.0f}ms avg)")

    return {
        "key": key,
        "name": approach["name"],
        "acc_1": acc_1,
        "acc_2": acc_2,
        "avg_ms_1": avg_ms_1,
        "avg_ms_2": avg_ms_2,
        "results": results,
    }


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    print("Testing language mixing approaches...")
    all_results = []

    for key, approach in APPROACHES.items():
        r = test_approach(key, approach)
        all_results.append(r)

    print(f"\n\n{'='*60}")
    print("FINAL COMPARISON")
    print(f"{'='*60}")
    print(f"{'Approach':<30} {'1-pass':>8} {'2-pass':>8} {'Rewrite cost':>14} {'Needs 2nd?':>12}")
    print("-" * 76)
    for r in all_results:
        gain = r["acc_2"] - r["acc_1"]
        needs_2nd = "yes" if gain > 15 else ("maybe" if gain > 5 else "no")
        print(f"{r['name']:<30} {r['acc_1']:>7.0f}% {r['acc_2']:>7.0f}%  {r['avg_ms_2']:>8.0f}ms      {needs_2nd:>10}")

    with open("approach_results.json", "w") as f:
        json.dump(all_results, f, indent=2, ensure_ascii=False)
    print("\nFull results → approach_results.json")


if __name__ == "__main__":
    main()
