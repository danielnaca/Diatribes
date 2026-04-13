#!/usr/bin/env python3
"""
Re-judge any results that have parse_error in their verdict.
Loads test_results.json, fixes bad verdicts, saves back, regenerates report.html.
"""

import json, re, time, sys
from dotenv import load_dotenv
from anthropic import Anthropic

load_dotenv()
client = Anthropic()
MODEL_FAST = "claude-haiku-4-5-20251001"

def _parse_json(raw):
    raw = raw.strip()
    raw = re.sub(r'^```(?:json)?\s*\n?', '', raw)
    raw = re.sub(r'\n?```\s*$', '', raw).strip()
    try:
        return json.loads(raw)
    except:
        m = re.search(r'\{.*\}', raw, re.DOTALL)
        if m:
            try:
                return json.loads(m.group(0))
            except:
                pass
        return {"accuracy_pct": 0, "parse_error": raw[:120]}

def _call_judge(content):
    r = client.messages.create(
        model=MODEL_FAST, max_tokens=300,
        system="You are a strict linguistics judge. Reply ONLY with valid JSON. No explanation, no markdown.",
        messages=[{"role": "user", "content": content}],
    )
    return _parse_json(r.content[0].text)

def judge_free_mix(text, language, target_pct):
    return _call_judge(
        f'Text: "{text}"\n\n'
        f"Estimate what percentage of the words are in {language} (not English). "
        f"The target was {target_pct}%. Score accuracy_pct as: 100 if actual % is within 5 points of target, "
        f"decreasing by 5 for each additional 5 points of deviation (0 if off by 50+).\n"
        f'Reply: {{"foreign_pct": <0-100>, "accuracy_pct": <0-100>, "note": "brief observation"}}'
    )

def judge_pos(text, language, pos_list):
    pos_str = " and ".join(pos_list)
    return _call_judge(
        f'Text: "{text}"\n\n'
        f"Rule: all {pos_str} should be in {language}, everything else in English.\n"
        f"List any {pos_str} still in English (missed), and any non-{pos_str} wrongly in {language}.\n"
        f"accuracy_pct: 100 = perfect, subtract 10 per missed/wrong word.\n"
        f'Reply: {{"missed": [], "wrong": [], "accuracy_pct": <0-100>}}'
    )

def judge_sentence_alt(text, language):
    return _call_judge(
        f'Text: "{text}"\n\n'
        f"Rule: sentences must strictly alternate English / {language}, starting with English.\n"
        f"Label each sentence EN or FL. Check for violations.\n"
        f"accuracy_pct: 100 = perfect, 0 = no alternation at all.\n"
        f'Reply: {{"sentences": [{{"text": "...", "lang": "EN/FL"}}], "accuracy_pct": <0-100>, "violations": []}}'
    )

def judge_immersion(text, language):
    return _call_judge(
        f'Text: "{text}"\n\n'
        f"Rule: respond entirely in {language} with English hints in [brackets] for harder words.\n"
        f"accuracy_pct: 100 = fully in {language} with useful bracketed hints, 0 = mostly English.\n"
        f'Reply: {{"is_target_language": true, "hint_count": <n>, "accuracy_pct": <0-100>, "note": "..."}}'
    )

def judge_translation(text, language):
    return _call_judge(
        f'Text: "{text}"\n\n'
        f"Rule: every English sentence must be immediately followed by its {language} translation in *asterisks*.\n"
        f"accuracy_pct: 100 = all sentences translated, 0 = none.\n"
        f'Reply: {{"english_sentences": <n>, "translations_found": <n>, "accuracy_pct": <0-100>}}'
    )

def rejudge_result(r, approach, language, variant):
    text = r.get("final") or r.get("rewritten") or r.get("generated", "")
    if not text:
        return r

    if approach == "free_mix":
        verdict = judge_free_mix(text, language, variant.get("pct", 50))
    elif approach == "pos":
        verdict = judge_pos(text, language, variant.get("pos", []))
    elif approach == "sentence_alt":
        verdict = judge_sentence_alt(text, language)
    elif approach == "immersion":
        verdict = judge_immersion(text, language)
    elif approach == "translation":
        verdict = judge_translation(text, language)
    else:
        return r

    r["verdict"] = verdict
    r["accuracy_pct"] = verdict.get("accuracy_pct", 0)
    return r

def main():
    with open("test_results.json") as f:
        all_groups = json.load(f)

    total_fixed = 0
    for group in all_groups:
        approach = group["approach"]
        language = group["language"]
        variant = group.get("variant") or {}

        fixed_in_group = 0
        for r in group.get("results", []):
            if "parse_error" in r.get("verdict", {}):
                print(f"  Re-judging [{approach}/{language}]: {r['prompt'][:50]}...", end=" ", flush=True)
                rejudge_result(r, approach, language, variant)
                if "parse_error" not in r.get("verdict", {}):
                    fixed_in_group += 1
                    print(f"→ {r['accuracy_pct']:.0f}%")
                else:
                    print("still failed")
                time.sleep(0.3)

        for d in group.get("dialogues", []):
            for t in d.get("turns", []):
                if "parse_error" in t.get("verdict", {}):
                    print(f"  Re-judging dialogue turn [{approach}/{language}]: {t['prompt'][:50]}...", end=" ", flush=True)
                    rejudge_result(t, approach, language, variant)
                    if "parse_error" not in t.get("verdict", {}):
                        fixed_in_group += 1
                        print(f"→ {t['accuracy_pct']:.0f}%")
                    else:
                        print("still failed")
                    time.sleep(0.3)
            # Recompute dialogue avg
            if d.get("turns"):
                d["avg_accuracy"] = sum(t["accuracy_pct"] for t in d["turns"]) / len(d["turns"])

        # Recompute group avg
        scores = [r["accuracy_pct"] for r in group.get("results", [])]
        if scores:
            group["avg_accuracy"] = sum(scores) / len(scores)

        total_fixed += fixed_in_group
        if fixed_in_group:
            print(f"  ✓ Fixed {fixed_in_group} in {approach}/{language}, new avg: {group['avg_accuracy']:.0f}%")

    print(f"\nTotal fixed: {total_fixed}")
    with open("test_results.json", "w") as f:
        json.dump(all_groups, f, indent=2, ensure_ascii=False)
    print("Saved test_results.json")

    # Regenerate report
    print("Regenerating report.html...")
    import run_tests
    with open("test_results.json") as f:
        results = json.load(f)
    html = run_tests.generate_html(results)
    with open("report.html", "w") as f:
        f.write(html)
    print("Done → report.html")

if __name__ == "__main__":
    main()
