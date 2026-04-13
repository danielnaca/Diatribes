#!/usr/bin/env python3
"""
Test POS-selector approach: one clean 2-pass for each combination of
nouns / verbs / adjectives / adverbs.
Pass 1: unconstrained natural response.
Pass 2: post-process finished text, swapping selected POS to French.
Judge scores accuracy_pct (0-100) rather than binary pass/fail.
"""

import json
import time
from dotenv import load_dotenv
from anthropic import Anthropic

load_dotenv()
client = Anthropic()

MODEL_CONV  = "claude-sonnet-4-20250514"
MODEL_FAST  = "claude-haiku-4-5-20251001"
LANGUAGE    = "French"

PROMPTS = [
    "What do you like to do on weekends?",
    "Tell me about your favorite food.",
    "Do you prefer the city or the countryside?",
    "What kind of music do you enjoy?",
]

# Combinations to test
COMBOS = [
    ["nouns"],
    ["verbs"],
    ["adjectives"],
    ["adverbs"],
    ["nouns", "verbs"],
    ["nouns", "adjectives"],
    ["nouns", "verbs", "adjectives"],
    ["nouns", "verbs", "adjectives", "adverbs"],
]

def build_rewrite_prompt(pos_list: list[str]) -> str:
    pos_str = " and ".join(pos_list)
    pos_bullets = "\n".join(
        f"- Replace every {p} with its {LANGUAGE} equivalent" for p in pos_list
    )
    keep = [p for p in ["nouns", "verbs", "adjectives", "adverbs"] if p not in pos_list]
    keep_str = ", ".join(keep) if keep else "nothing"

    examples = {
        frozenset(["nouns"]): (
            "Input:  'I love going to the market — the vegetables are always fresh!'\n"
            "Nouns:  market→marché, vegetables→légumes\n"
            "Output: 'I love going to the marché — the légumes are always fresh!'"
        ),
        frozenset(["verbs"]): (
            "Input:  'I love going to the market — the vegetables are always fresh!'\n"
            "Verbs:  love→adore, going→aller, are→sont\n"
            "Output: 'I adore aller to the market — the vegetables sont always fresh!'"
        ),
        frozenset(["adjectives"]): (
            "Input:  'It was a beautiful, quiet morning in the old city.'\n"
            "Adj:    beautiful→beau, quiet→silencieux, old→vieux\n"
            "Output: 'It was a beau, silencieux morning in the vieux city.'"
        ),
        frozenset(["adverbs"]): (
            "Input:  'I really enjoy music and absolutely love jazz.'\n"
            "Adv:    really→vraiment, absolutely→absolument\n"
            "Output: 'I vraiment enjoy music and absolument love jazz.'"
        ),
        frozenset(["nouns", "verbs"]): (
            "Input:  'I love going to the market — the vegetables are always fresh!'\n"
            "Nouns:  market→marché, vegetables→légumes\n"
            "Verbs:  love→adore, going→aller, are→sont\n"
            "Output: 'I adore aller to the marché — the légumes sont always fresh!'"
        ),
        frozenset(["nouns", "adjectives"]): (
            "Input:  'The beautiful city has amazing markets and fresh food.'\n"
            "Nouns:  city→ville, markets→marchés, food→nourriture\n"
            "Adj:    beautiful→belle, amazing→incroyables, fresh→fraîche\n"
            "Output: 'The belle ville has incroyables marchés and fraîche nourriture.'"
        ),
    }

    key = frozenset(pos_list)
    example = examples.get(key, examples.get(frozenset(["nouns", "verbs"]),
        "Input:  'I love the beautiful market in the old city.'\n"
        "Output: apply the rules above carefully."
    ))

    return (
        f"You are a linguistics post-processor. You will receive a completed English text.\n"
        f"Your task: identify all {pos_str} in the text and replace each with its {LANGUAGE} equivalent.\n"
        f"{pos_bullets}\n"
        f"Keep everything else in English: {keep_str}, plus articles, pronouns, prepositions, conjunctions.\n\n"
        f"Work through the sentence carefully — scan the whole thing before making changes.\n\n"
        f"Example:\n{example}\n\n"
        f"Return ONLY the final transformed text. No explanation."
    )

def build_judge_prompt(pos_list: list[str]) -> str:
    pos_str = " and ".join(pos_list)
    return (
        f"Evaluate this text. The rule was: replace all {pos_str} with {LANGUAGE} equivalents, "
        f"keep everything else in English.\n\n"
        f"1. List any {pos_str} that are STILL in English (missed)\n"
        f"2. List any non-{pos_str} that were INCORRECTLY changed to {LANGUAGE}\n"
        f"3. Give an accuracy_pct (0-100) for how well the rule was followed\n\n"
        f"Reply ONLY with JSON: {{\"missed\": [...], \"wrong\": [...], \"accuracy_pct\": <number>}}"
    )

def generate(prompt: str) -> tuple[str, int]:
    t0 = time.monotonic()
    r = client.messages.create(
        model=MODEL_CONV,
        max_tokens=150,
        system="You are a friendly conversational partner. Respond naturally in 2 sentences.",
        messages=[{"role": "user", "content": prompt}],
    )
    return r.content[0].text.strip(), round((time.monotonic() - t0) * 1000)

def rewrite(text: str, rewrite_sys: str) -> tuple[str, int]:
    t0 = time.monotonic()
    r = client.messages.create(
        model=MODEL_FAST,
        max_tokens=200,
        system=rewrite_sys,
        messages=[{"role": "user", "content": f"Text to transform:\n\n{text}"}],
    )
    return r.content[0].text.strip(), round((time.monotonic() - t0) * 1000)

def judge(text: str, judge_prompt: str) -> dict:
    r = client.messages.create(
        model=MODEL_FAST,
        max_tokens=200,
        system="You are a strict linguistics judge. Reply ONLY with valid JSON.",
        messages=[{"role": "user", "content": f"Text:\n\"{text}\"\n\n{judge_prompt}"}],
    )
    raw = r.content[0].text.strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        return json.loads(raw)
    except:
        return {"accuracy_pct": 0, "raw": raw[:100]}

def test_combo(pos_list: list[str]) -> dict:
    label = " + ".join(pos_list)
    rewrite_sys = build_rewrite_prompt(pos_list)
    judge_prompt = build_judge_prompt(pos_list)

    print(f"\n── {label} ──────────────────────────────────────────")
    scores = []
    gen_times = []
    rewrite_times = []

    for prompt in PROMPTS:
        text_1, ms_1 = generate(prompt)
        text_2, ms_2 = rewrite(text_1, rewrite_sys)
        verdict = judge(text_2, judge_prompt)
        acc = verdict.get("accuracy_pct", 0)
        missed = verdict.get("missed", [])
        wrong = verdict.get("wrong", [])
        scores.append(acc)
        gen_times.append(ms_1)
        rewrite_times.append(ms_2)

        print(f"  {acc:3.0f}%  orig:    {text_1[:70]}…")
        print(f"        result:  {text_2[:70]}…")
        if missed: print(f"        missed:  {missed}")
        if wrong:  print(f"        wrong:   {wrong}")

    avg_acc     = sum(scores) / len(scores)
    avg_gen     = sum(gen_times) / len(gen_times)
    avg_rewrite = sum(rewrite_times) / len(rewrite_times)
    print(f"\n  avg accuracy: {avg_acc:.0f}%  |  gen: {avg_gen:.0f}ms  rewrite: {avg_rewrite:.0f}ms")

    return {
        "combo": label,
        "avg_accuracy": avg_acc,
        "avg_gen_ms": avg_gen,
        "avg_rewrite_ms": avg_rewrite,
    }

def main():
    print(f"POS selector — clean 2-pass test ({LANGUAGE})")
    print("=" * 60)

    results = []
    for pos_list in COMBOS:
        results.append(test_combo(pos_list))

    print(f"\n\n{'='*60}")
    print("SUMMARY")
    print(f"{'Combo':<35} {'Accuracy':>10} {'Rewrite':>10}")
    print("-" * 58)
    for r in results:
        bar = "█" * int(r["avg_accuracy"] / 10)
        print(f"{r['combo']:<35} {r['avg_accuracy']:>9.0f}%  {r['avg_rewrite_ms']:>7.0f}ms  {bar}")

    with open("pos_results.json", "w") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)
    print("\nFull results → pos_results.json")

if __name__ == "__main__":
    main()
