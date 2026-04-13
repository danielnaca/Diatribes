#!/usr/bin/env python3
"""
Exhaustive test of all Diatribes language-mixing approaches.
Languages: French, Spanish
Saves results to test_results.json and generates report.html
"""

import json, os, re, time, sys
from datetime import datetime
from dotenv import load_dotenv
from anthropic import Anthropic

load_dotenv()
client = Anthropic()

MODEL_CONV  = "claude-sonnet-4-20250514"
MODEL_FAST  = "claude-haiku-4-5-20251001"
RESULTS_FILE = "test_results.json"
REPORT_FILE  = "report.html"

LANGUAGES = ["French", "Spanish"]

# ─────────────────────────────────────────────────────────────────
# TEST PROMPTS
# ─────────────────────────────────────────────────────────────────

CHAT_PROMPTS = [
    "What do you like to do on weekends?",
    "Tell me about your favorite food.",
    "Do you prefer the city or the countryside?",
    "What kind of music do you enjoy?",
    "What's a hobby you've recently picked up?",
    "How do you usually unwind after a long day?",
]

DESCRIBE_PROMPTS = [
    "Describe your ideal vacation destination in as much detail as possible.",
    "What does your perfect morning look like from the moment you wake up?",
    "Describe the most beautiful place you've ever been or can imagine.",
    "Paint me a vivid picture of your favorite season and why you love it.",
]

STORY_PROMPTS = [
    "Tell me a short story about an unexpected encounter with a stranger while traveling.",
    "Describe a meal you'll never forget — where, what, and why it was special.",
    "Tell me about a moment when something completely changed your way of thinking.",
]

DIALOGUES = [
    {
        "name": "Paris trip planning",
        "turns": [
            "Hi! I'm planning my very first trip to Paris next spring. Any advice?",
            "That sounds wonderful! Which neighborhood would you recommend I stay in?",
            "I love food. What French dish absolutely must I try while I'm there?",
        ],
    },
    {
        "name": "Learning to cook",
        "turns": [
            "I want to start cooking at home more instead of ordering takeout. Where should I begin?",
            "What's a dish that looks really impressive but isn't too hard for a beginner?",
            "My sauces always turn out too thin or too salty. Any tips to fix that?",
        ],
    },
    {
        "name": "Stress and wellbeing",
        "turns": [
            "I've been feeling really stressed and overwhelmed lately. How do you deal with it?",
            "Do you actually meditate? Does it really work for you?",
            "I struggle to stick to any new habits. How do you stay consistent?",
        ],
    },
]

# ─────────────────────────────────────────────────────────────────
# APPROACH VARIANTS
# ─────────────────────────────────────────────────────────────────

FREE_MIX_VARIANTS = [
    {"label": "25%",  "pct": 25},
    {"label": "50%",  "pct": 50},
    {"label": "75%",  "pct": 75},
    {"label": "100%", "pct": 100},
]

POS_VARIANTS = [
    {"label": "Nouns only",      "pos": ["nouns"]},
    {"label": "Verbs only",      "pos": ["verbs"]},
    {"label": "Adjectives only", "pos": ["adjectives"]},
    {"label": "Adverbs only",    "pos": ["adverbs"]},
    {"label": "Nouns + Verbs",   "pos": ["nouns", "verbs"]},
    {"label": "All four",        "pos": ["nouns", "verbs", "adjectives", "adverbs"]},
]

# ─────────────────────────────────────────────────────────────────
# SYSTEM PROMPT BUILDERS
# ─────────────────────────────────────────────────────────────────

JSON_FMT = '\nRespond ONLY with valid JSON, no markdown fences:\n{"correction": null, "response": "...", "trouble_words": null}'

def free_mix_rule(language, pct):
    L = language
    if pct <= 15:
        return f"Respond in English with occasional {L} words or short phrases — maybe once per sentence. Mostly English."
    elif pct <= 35:
        return f"Respond mostly in English but weave in {L} words and phrases. Roughly 1 in 4 words should be {L}."
    elif pct <= 65:
        return f"Respond in a genuine half-and-half mix — {L} and English roughly equal, blended naturally within sentences."
    elif pct <= 85:
        return f"Respond primarily in {L}. English should be a minority — only a word or short phrase per sentence."
    elif pct < 100:
        return f"Respond almost entirely in {L}. Only one or two English words total. Everything else must be {L}."
    else:
        return f"Respond ENTIRELY IN {L.upper()}. Every single word must be {L}. No English whatsoever — not even 'I', 'a', 'the'."

def build_system(language, approach, variant=None):
    base = "You are a friendly conversational partner. Have genuine, interesting conversations — be curious and engaged."
    if approach == "free_mix":
        rule = free_mix_rule(language, variant["pct"])
        return f"LANGUAGE RULE (highest priority — follow above all else):\n{rule}\n\n{base}{JSON_FMT}"
    elif approach == "pos":
        return f"Respond naturally in English. Have a genuine, engaging conversation.\n{base}{JSON_FMT}"
    elif approach == "sentence_alt":
        return (f"LANGUAGE RULE (highest priority): Alternate languages sentence by sentence. "
                f"First sentence: English. Second: {language}. Third: English. And so on — never break this pattern. "
                f"Never mix languages within a single sentence.\n\n{base}{JSON_FMT}")
    elif approach == "immersion":
        return (f"LANGUAGE RULE (highest priority): Respond entirely in {language}. "
                f"After any word that may be unfamiliar to an intermediate learner, "
                f"add its English translation in [brackets] immediately after the word. "
                f"Example: 'Je vais au marché [market] acheter des légumes [vegetables] frais [fresh].'\n\n{base}{JSON_FMT}")
    elif approach == "translation":
        return (f"LANGUAGE RULE (highest priority): Write each sentence in English, then "
                f"immediately follow it with its {language} translation in *asterisks*. "
                f"Example: 'I love going to the market on weekends. *J'adore aller au marché le week-end.*'\n\n{base}{JSON_FMT}")

# ─────────────────────────────────────────────────────────────────
# REWRITERS
# ─────────────────────────────────────────────────────────────────

def rewrite_free_mix(text, language, pct):
    r = client.messages.create(
        model=MODEL_FAST, max_tokens=512,
        system=(f"You are a text rewriter. Rewrite the given text so that approximately {pct}% "
                f"of the words are in {language} and the rest in English. "
                f"Preserve meaning and tone exactly. At 100% use only {language}. "
                f"Return ONLY the rewritten text — no explanation, no quotes."),
        messages=[{"role": "user", "content": text}],
    )
    return r.content[0].text.strip()

def rewrite_pos(text, language, pos_list):
    pos_str = " and ".join(pos_list)
    keep = [p for p in ["nouns", "verbs", "adjectives", "adverbs"] if p not in pos_list]
    keep_str = ", ".join(keep) if keep else "nothing"
    r = client.messages.create(
        model=MODEL_FAST, max_tokens=512,
        system=(f"You are a linguistics post-processor. You will receive English text.\n"
                f"Your task: identify all {pos_str} and replace each with its {language} equivalent.\n"
                f"Keep everything else in English: {keep_str}, plus articles, pronouns, prepositions, conjunctions.\n"
                f"Scan the whole text first, then make changes.\n"
                f"Return ONLY the final transformed text. No explanation."),
        messages=[{"role": "user", "content": f"Text to transform:\n\n{text}"}],
    )
    return r.content[0].text.strip()

# ─────────────────────────────────────────────────────────────────
# JUDGES
# ─────────────────────────────────────────────────────────────────

def _call_judge(content):
    r = client.messages.create(
        model=MODEL_FAST, max_tokens=300,
        system="You are a strict linguistics judge. Reply ONLY with valid JSON.",
        messages=[{"role": "user", "content": content}],
    )
    raw = r.content[0].text.strip()
    # Strip markdown code fences properly
    raw = re.sub(r'^```(?:json)?\s*\n?', '', raw)
    raw = re.sub(r'\n?```\s*$', '', raw).strip()
    try:
        return json.loads(raw)
    except:
        # Try to extract a JSON object anywhere in the response
        m = re.search(r'\{.*\}', raw, re.DOTALL)
        if m:
            try:
                return json.loads(m.group(0))
            except:
                pass
        return {"accuracy_pct": 0, "parse_error": raw[:120]}

def judge_free_mix(text, language, target_pct):
    return _call_judge(
        f'Text: "{text}"\n\n'
        f"Estimate what percentage of the words are in {language} (not English). "
        f"The target was {target_pct}%. Score accuracy_pct as: 100 if the actual % is within 5 points of target, "
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
        f'Reply: {{"missed": [...], "wrong": [...], "accuracy_pct": <0-100>}}'
    )

def judge_sentence_alt(text, language):
    return _call_judge(
        f'Text: "{text}"\n\n'
        f"Rule: sentences must strictly alternate English / {language}, starting with English.\n"
        f"Label each sentence EN or FL. Check for violations.\n"
        f"accuracy_pct: 100 = perfect, 0 = no alternation at all.\n"
        f'Reply: {{"sentences": [{{"text": "...", "lang": "EN/FL"}}], "accuracy_pct": <0-100>, "violations": [...]}}'
    )

def judge_immersion(text, language):
    return _call_judge(
        f'Text: "{text}"\n\n'
        f"Rule: respond entirely in {language} with English hints in [brackets] for harder words.\n"
        f"Is the main text in {language}? How many bracket hints are there? Are they appropriate?\n"
        f"accuracy_pct: 100 = fully in {language} with useful bracketed hints, 0 = mostly English.\n"
        f'Reply: {{"is_target_language": true/false, "hint_count": <n>, "accuracy_pct": <0-100>, "note": "..."}}'
    )

def judge_translation(text, language):
    return _call_judge(
        f'Text: "{text}"\n\n'
        f"Rule: every English sentence must be immediately followed by its {language} translation in *asterisks*.\n"
        f"Count English sentences and translation pairs found.\n"
        f"accuracy_pct: 100 = all sentences translated, 0 = none.\n"
        f'Reply: {{"english_sentences": <n>, "translations_found": <n>, "accuracy_pct": <0-100>}}'
    )

def run_judge(approach, text, language, variant):
    if approach == "free_mix":
        return judge_free_mix(text, language, variant["pct"])
    elif approach == "pos":
        return judge_pos(text, language, variant["pos"])
    elif approach == "sentence_alt":
        return judge_sentence_alt(text, language)
    elif approach == "immersion":
        return judge_immersion(text, language)
    elif approach == "translation":
        return judge_translation(text, language)
    return {"accuracy_pct": 0}

# ─────────────────────────────────────────────────────────────────
# CORE TEST RUNNER
# ─────────────────────────────────────────────────────────────────

def call_generate(system, prompt, history):
    msgs = history + [{"role": "user", "content": prompt}]
    r = client.messages.create(model=MODEL_CONV, max_tokens=500, system=system, messages=msgs)
    raw = r.content[0].text.strip()
    try:
        return json.loads(raw)["response"]
    except:
        # Try to extract response field with regex
        m = re.search(r'"response"\s*:\s*"((?:[^"\\]|\\.)*)"', raw)
        return m.group(1) if m else raw

def run_one(approach, variant, language, prompt, history=[], prompt_type="chat"):
    system = build_system(language, approach, variant)
    t0 = time.monotonic()
    generated = call_generate(system, prompt, history)
    gen_ms = round((time.monotonic() - t0) * 1000)

    rewritten = None
    rewrite_ms = None
    if approach == "free_mix":
        t1 = time.monotonic()
        rewritten = rewrite_free_mix(generated, language, variant["pct"])
        rewrite_ms = round((time.monotonic() - t1) * 1000)
    elif approach == "pos" and variant.get("pos"):
        t1 = time.monotonic()
        rewritten = rewrite_pos(generated, language, variant["pos"])
        rewrite_ms = round((time.monotonic() - t1) * 1000)

    final = rewritten if rewritten else generated
    verdict = run_judge(approach, final, language, variant or {})

    return {
        "prompt": prompt,
        "prompt_type": prompt_type,
        "generated": generated,
        "rewritten": rewritten,
        "final": final,
        "verdict": verdict,
        "accuracy_pct": verdict.get("accuracy_pct", 0),
        "gen_ms": gen_ms,
        "rewrite_ms": rewrite_ms,
    }

def run_dialogue_test(approach, variant, language, dialogue):
    history = []
    system = build_system(language, approach, variant)
    turns = []
    for turn_prompt in dialogue["turns"]:
        t0 = time.monotonic()
        generated = call_generate(system, turn_prompt, history)
        gen_ms = round((time.monotonic() - t0) * 1000)

        rewritten = None
        rewrite_ms = None
        if approach == "free_mix":
            t1 = time.monotonic()
            rewritten = rewrite_free_mix(generated, language, variant["pct"])
            rewrite_ms = round((time.monotonic() - t1) * 1000)
        elif approach == "pos" and variant.get("pos"):
            t1 = time.monotonic()
            rewritten = rewrite_pos(generated, language, variant["pos"])
            rewrite_ms = round((time.monotonic() - t1) * 1000)

        final = rewritten if rewritten else generated
        verdict = run_judge(approach, final, language, variant or {})

        history.append({"role": "user", "content": turn_prompt})
        history.append({"role": "assistant", "content": final})

        turns.append({
            "prompt": turn_prompt,
            "generated": generated,
            "rewritten": rewritten,
            "final": final,
            "verdict": verdict,
            "accuracy_pct": verdict.get("accuracy_pct", 0),
            "gen_ms": gen_ms,
            "rewrite_ms": rewrite_ms,
        })
    return {"dialogue_name": dialogue["name"], "turns": turns,
            "avg_accuracy": sum(t["accuracy_pct"] for t in turns) / len(turns)}

def safe_run(fn, *args, retries=2, **kwargs):
    for attempt in range(retries + 1):
        try:
            return fn(*args, **kwargs)
        except Exception as e:
            if attempt < retries:
                print(f"    ⚠ Error ({e}), retrying in 5s...")
                time.sleep(5)
            else:
                print(f"    ✗ Failed after {retries+1} attempts: {e}")
                return None

# ─────────────────────────────────────────────────────────────────
# TEST ORCHESTRATION
# ─────────────────────────────────────────────────────────────────

def collect_prompts():
    prompts = (
        [(p, "chat") for p in CHAT_PROMPTS] +
        [(p, "describe") for p in DESCRIBE_PROMPTS] +
        [(p, "story") for p in STORY_PROMPTS]
    )
    return prompts

def run_approach_variant(approach, variant, language, all_prompts):
    label = variant.get("label", "default") if variant else "default"
    print(f"\n  [{language}] {approach} / {label}")
    results = []
    for prompt, ptype in all_prompts:
        print(f"    → {prompt[:60]}...", end=" ", flush=True)
        r = safe_run(run_one, approach, variant, language, prompt, [], ptype)
        if r:
            results.append(r)
            print(f"{r['accuracy_pct']:.0f}%")
        time.sleep(0.5)
    # Run one dialogue
    dialogue = DIALOGUES[0]  # Paris trip for all variants (keeps it comparable)
    print(f"    → [dialogue] {dialogue['name']}", end=" ", flush=True)
    dr = safe_run(run_dialogue_test, approach, variant, language, dialogue)
    dialogues = [dr] if dr else []
    if dr:
        print(f"avg {dr['avg_accuracy']:.0f}%")

    acc_scores = [r["accuracy_pct"] for r in results]
    avg = sum(acc_scores) / len(acc_scores) if acc_scores else 0

    return {
        "approach": approach,
        "variant_label": label,
        "variant": variant,
        "language": language,
        "avg_accuracy": avg,
        "results": results,
        "dialogues": dialogues,
    }

def run_all():
    all_results = []
    all_prompts = collect_prompts()

    approach_configs = [
        ("free_mix",     FREE_MIX_VARIANTS),
        ("pos",          POS_VARIANTS),
        ("sentence_alt", [{"label": "default"}]),
        ("immersion",    [{"label": "default"}]),
        ("translation",  [{"label": "default"}]),
    ]

    for approach, variants in approach_configs:
        print(f"\n{'='*60}\nAPPROACH: {approach}\n{'='*60}")
        for variant in variants:
            for language in LANGUAGES:
                result = run_approach_variant(approach, variant, language, all_prompts)
                all_results.append(result)
                # Save intermediate
                with open(RESULTS_FILE, "w") as f:
                    json.dump(all_results, f, indent=2, ensure_ascii=False)
                print(f"    ✓ avg accuracy: {result['avg_accuracy']:.0f}%")
                time.sleep(1)

    return all_results

# ─────────────────────────────────────────────────────────────────
# HTML REPORT GENERATOR
# ─────────────────────────────────────────────────────────────────

APPROACH_META = {
    "free_mix": {
        "name": "Free Mix",
        "desc": "Words from both languages blended freely at a target ratio.",
        "how": "Two-pass: Claude generates naturally, then Haiku rewrites to hit the target percentage. Slider controls the ratio from 0% (pure English) to 100% (pure target language).",
        "icon": "⇌",
        "color": "#4a90e2",
    },
    "pos": {
        "name": "POS Swap",
        "desc": "Specific parts of speech are swapped into the target language.",
        "how": "Two-pass: Claude generates in English, then Haiku post-processes as a linguistics engine — identifying and replacing selected parts of speech (nouns, verbs, adjectives, adverbs) with their target-language equivalents.",
        "icon": "⟨N⟩",
        "color": "#e2844a",
    },
    "sentence_alt": {
        "name": "Sentence Alternation",
        "desc": "Sentences strictly alternate between English and the target language.",
        "how": "Single-pass: Claude is instructed to alternate languages sentence by sentence, starting with English. No rewrite pass (testing showed it hurt accuracy).",
        "icon": "E / F",
        "color": "#7c4ae2",
    },
    "immersion": {
        "name": "Immersion with Hints",
        "desc": "Fully in the target language, with English hints in [brackets] for harder words.",
        "how": "Single-pass: Claude responds entirely in the target language, adding English translations in square brackets after unfamiliar vocabulary. Brackets are stripped before text-to-speech.",
        "icon": "[≈]",
        "color": "#4ae28a",
    },
    "translation": {
        "name": "Translation Pairs",
        "desc": "Every English sentence is immediately followed by its translation.",
        "how": "Single-pass: Claude writes each sentence in English then immediately follows it with the target-language translation in *asterisks*. Asterisks are stripped for text-to-speech.",
        "icon": "EN→",
        "color": "#e24a7c",
    },
}

def score_color(pct):
    if pct >= 80: return "#4ae28a"
    if pct >= 60: return "#e2c94a"
    if pct >= 40: return "#e2844a"
    return "#e24a4a"

def score_bar(pct, color="#e94560"):
    return f'<div class="score-bar"><div class="score-fill" style="width:{pct}%;background:{color}"></div><span class="score-num">{pct:.0f}%</span></div>'

def render_example(r, language, approach):
    verdict = r.get("verdict", {})
    acc = r.get("accuracy_pct", 0)
    color = score_color(acc)
    extra = ""
    if approach == "free_mix":
        fp = verdict.get("foreign_pct", "?")
        extra = f'<span class="tag">Actual {language}: {fp}%</span>'
    elif approach == "pos":
        missed = verdict.get("missed", [])
        wrong = verdict.get("wrong", [])
        if missed: extra += f'<span class="tag warn">Missed: {", ".join(missed[:5])}</span>'
        if wrong: extra += f'<span class="tag warn">Wrong: {", ".join(wrong[:5])}</span>'
    elif approach == "sentence_alt":
        sents = verdict.get("sentences", [])
        if sents:
            pattern = " ".join(f'<b style="color:{"#4a90e2" if s["lang"]=="EN" else "#e2844a"}">{s["lang"]}</b>' for s in sents[:6])
            extra = f'<span class="pattern">{pattern}</span>'
    elif approach == "immersion":
        extra = f'<span class="tag">Hints: {verdict.get("hint_count","?")}</span>'
    elif approach == "translation":
        en = verdict.get("english_sentences", "?")
        tr = verdict.get("translations_found", "?")
        extra = f'<span class="tag">{tr}/{en} translated</span>'

    gen_html = ""
    if r.get("rewritten"):
        gen_html = f'<div class="ex-field"><span class="ex-label">Generated (raw)</span><div class="ex-text muted">{r["generated"]}</div></div>'

    return f'''<div class="example" style="border-left:3px solid {color}">
  <div class="ex-prompt">Q: {r["prompt"]}</div>
  {gen_html}
  <div class="ex-field"><span class="ex-label">Final output</span><div class="ex-text">{r["final"]}</div></div>
  <div class="ex-meta">{score_bar(acc, color)}{extra}<span class="tag">{r.get("gen_ms","?")}ms gen{(" · "+str(r["rewrite_ms"])+"ms rewrite") if r.get("rewrite_ms") else ""}</span></div>
</div>'''

def render_dialogue(dr, language, approach):
    if not dr: return ""
    turns_html = ""
    for t in dr["turns"]:
        acc = t.get("accuracy_pct", 0)
        color = score_color(acc)
        turns_html += f'''<div class="dial-turn">
  <div class="dial-q">Q: {t["prompt"]}</div>
  <div class="dial-a">{t["final"]}</div>
  <div class="dial-score">{score_bar(acc, color)}</div>
</div>'''
    return f'''<div class="dialogue-block">
  <div class="dial-name">Dialogue: {dr["dialogue_name"]} — avg {dr["avg_accuracy"]:.0f}%</div>
  {turns_html}
</div>'''

def generate_html(all_results):
    # Build summary table data
    approach_order = ["free_mix", "pos", "sentence_alt", "immersion", "translation"]
    lang_order = LANGUAGES

    # Group results
    grouped = {}  # approach -> variant_label -> language -> result
    for r in all_results:
        a = r["approach"]
        v = r["variant_label"]
        l = r["language"]
        grouped.setdefault(a, {}).setdefault(v, {})[l] = r

    # Summary section
    summary_rows = ""
    for approach in approach_order:
        meta = APPROACH_META[approach]
        variants = grouped.get(approach, {})
        for vlabel, langs in variants.items():
            cols = ""
            for lang in lang_order:
                res = langs.get(lang)
                avg = res["avg_accuracy"] if res else 0
                cols += f'<td><div class="cell-score" style="color:{score_color(avg)}">{avg:.0f}%</div></td>'
            summary_rows += f'<tr><td><span class="approach-badge" style="background:{meta["color"]}20;color:{meta["color"]}">{meta["name"]}</span></td><td class="variant-col">{vlabel}</td>{cols}</tr>'

    summary_header = "".join(f"<th>{l}</th>" for l in lang_order)

    # Approach sections
    approach_sections = ""
    for approach in approach_order:
        meta = APPROACH_META[approach]
        variants = grouped.get(approach, {})

        variant_blocks = ""
        for vlabel, langs in variants.items():
            lang_tabs = ""
            lang_content = ""
            for i, lang in enumerate(lang_order):
                res = langs.get(lang)
                if not res: continue
                avg = res["avg_accuracy"]
                active = "active" if i == 0 else ""
                tab_id = f"{approach}_{vlabel}_{lang}".replace(" ", "_").replace("%", "pct")
                lang_tabs += f'<button class="lang-tab {active}" onclick="showTab(this,\'{tab_id}\')">{lang} <span style="color:{score_color(avg)}">{avg:.0f}%</span></button>'

                examples_html = "".join(render_example(r, lang, approach) for r in res["results"][:5])
                dialogues_html = "".join(render_dialogue(d, lang, approach) for d in res.get("dialogues", []))
                lang_content += f'<div class="tab-pane {active}" id="{tab_id}">{examples_html}{dialogues_html}</div>'

            variant_blocks += f'''<div class="variant-block">
  <div class="variant-label">{vlabel}</div>
  <div class="lang-tabs">{lang_tabs}</div>
  <div class="tab-panes">{lang_content}</div>
</div>'''

        approach_sections += f'''<section class="approach-section" id="approach-{approach}">
  <div class="approach-header" style="border-left:4px solid {meta["color"]}">
    <div class="approach-icon" style="color:{meta["color"]}">{meta["icon"]}</div>
    <div>
      <h2>{meta["name"]}</h2>
      <p class="approach-desc">{meta["desc"]}</p>
    </div>
  </div>
  <div class="how-it-works"><strong>How it works:</strong> {meta["how"]}</div>
  {variant_blocks}
</section>'''

    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    total_tests = sum(len(r["results"]) for r in all_results)

    return f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Diatribes — Approach Test Report</title>
<style>
  :root {{
    --bg: #0d0d0d; --surface: #161616; --surface2: #1f1f1f;
    --border: #2a2a2a; --text: #e8e8e8; --muted: #888; --faint: #555;
    --accent: #e94560;
  }}
  * {{ margin:0; padding:0; box-sizing:border-box; }}
  body {{ font-family:-apple-system,BlinkMacSystemFont,"SF Pro",system-ui,sans-serif; background:var(--bg); color:var(--text); font-size:14px; line-height:1.6; }}
  a {{ color:var(--accent); text-decoration:none; }}

  /* Layout */
  .shell {{ display:flex; min-height:100vh; }}
  nav {{ width:220px; flex-shrink:0; background:var(--surface); border-right:1px solid var(--border); padding:24px 0; position:sticky; top:0; height:100vh; overflow-y:auto; }}
  main {{ flex:1; max-width:900px; padding:40px 32px; }}

  /* Nav */
  .nav-logo {{ padding:0 20px 24px; font-size:18px; font-weight:700; color:var(--accent); letter-spacing:-0.5px; }}
  .nav-section {{ font-size:10px; text-transform:uppercase; letter-spacing:1px; color:var(--faint); padding:16px 20px 6px; }}
  nav a {{ display:block; padding:7px 20px; color:var(--muted); font-size:13px; border-left:2px solid transparent; transition:all 0.15s; }}
  nav a:hover, nav a.active {{ color:var(--text); border-left-color:var(--accent); background:rgba(233,69,96,0.06); }}

  /* Header */
  .report-header {{ margin-bottom:40px; }}
  .report-header h1 {{ font-size:28px; font-weight:700; letter-spacing:-0.5px; margin-bottom:6px; }}
  .report-header .meta {{ color:var(--muted); font-size:13px; }}
  .report-header .meta span {{ margin-right:20px; }}

  /* Summary table */
  .summary-card {{ background:var(--surface); border:1px solid var(--border); border-radius:10px; overflow:hidden; margin-bottom:48px; }}
  .summary-card h3 {{ padding:16px 20px; border-bottom:1px solid var(--border); font-size:13px; text-transform:uppercase; letter-spacing:0.5px; color:var(--muted); }}
  table {{ width:100%; border-collapse:collapse; }}
  th {{ padding:10px 16px; text-align:left; font-size:11px; text-transform:uppercase; letter-spacing:0.5px; color:var(--muted); border-bottom:1px solid var(--border); }}
  td {{ padding:10px 16px; border-bottom:1px solid var(--border); font-size:13px; }}
  tr:last-child td {{ border-bottom:none; }}
  .cell-score {{ font-size:16px; font-weight:600; }}
  .approach-badge {{ display:inline-block; padding:2px 8px; border-radius:4px; font-size:12px; font-weight:500; }}
  .variant-col {{ color:var(--muted); font-size:12px; }}

  /* Approach sections */
  .approach-section {{ margin-bottom:60px; }}
  .approach-header {{ display:flex; align-items:flex-start; gap:16px; padding:20px; background:var(--surface); border-radius:10px 10px 0 0; border:1px solid var(--border); border-bottom:none; margin-bottom:0; }}
  .approach-icon {{ font-size:22px; font-family:monospace; min-width:48px; text-align:center; padding-top:2px; }}
  .approach-header h2 {{ font-size:20px; font-weight:700; margin-bottom:4px; }}
  .approach-desc {{ color:var(--muted); font-size:13px; }}
  .how-it-works {{ background:var(--surface2); border:1px solid var(--border); border-top:none; padding:14px 20px; font-size:13px; color:var(--muted); line-height:1.7; }}

  /* Variant blocks */
  .variant-block {{ border:1px solid var(--border); border-top:none; }}
  .variant-block:last-child {{ border-radius:0 0 10px 10px; }}
  .variant-label {{ padding:10px 20px; background:var(--surface2); border-bottom:1px solid var(--border); font-size:12px; font-weight:600; text-transform:uppercase; letter-spacing:0.5px; color:var(--muted); }}
  .lang-tabs {{ display:flex; gap:2px; padding:10px 16px; border-bottom:1px solid var(--border); background:var(--surface); }}
  .lang-tab {{ background:none; border:1px solid var(--border); color:var(--muted); padding:4px 14px; border-radius:20px; font-size:12px; cursor:pointer; transition:all 0.15s; }}
  .lang-tab.active {{ border-color:var(--accent); color:var(--text); background:rgba(233,69,96,0.1); }}
  .tab-pane {{ display:none; padding:16px 20px; }}
  .tab-pane.active {{ display:block; }}

  /* Examples */
  .example {{ background:var(--surface2); border-radius:6px; border-left:3px solid var(--border); padding:14px 16px; margin-bottom:12px; }}
  .ex-prompt {{ font-size:12px; font-weight:600; color:var(--muted); margin-bottom:10px; }}
  .ex-field {{ margin-bottom:8px; }}
  .ex-label {{ font-size:10px; text-transform:uppercase; letter-spacing:0.5px; color:var(--faint); display:block; margin-bottom:3px; }}
  .ex-text {{ font-size:13px; line-height:1.6; }}
  .ex-text.muted {{ color:var(--muted); font-style:italic; }}
  .ex-meta {{ display:flex; align-items:center; gap:8px; flex-wrap:wrap; margin-top:10px; }}
  .tag {{ font-size:11px; background:var(--surface); border:1px solid var(--border); padding:2px 8px; border-radius:10px; color:var(--muted); }}
  .tag.warn {{ border-color:#e2844a; color:#e2844a; }}
  .pattern {{ font-size:12px; }}

  /* Score bar */
  .score-bar {{ display:flex; align-items:center; gap:8px; min-width:120px; }}
  .score-fill {{ height:4px; border-radius:2px; min-width:2px; }}
  .score-num {{ font-size:12px; font-weight:600; white-space:nowrap; }}

  /* Dialogues */
  .dialogue-block {{ background:var(--surface); border:1px solid var(--border); border-radius:8px; margin-top:16px; overflow:hidden; }}
  .dial-name {{ padding:10px 16px; background:var(--surface2); border-bottom:1px solid var(--border); font-size:12px; font-weight:600; color:var(--muted); }}
  .dial-turn {{ padding:12px 16px; border-bottom:1px solid var(--border); }}
  .dial-turn:last-child {{ border-bottom:none; }}
  .dial-q {{ font-size:12px; color:var(--muted); margin-bottom:6px; }}
  .dial-a {{ font-size:13px; margin-bottom:8px; }}
  .dial-score {{ }}

  @media (max-width: 768px) {{
    nav {{ display:none; }}
    main {{ padding:20px 16px; }}
  }}
</style>
</head>
<body>
<div class="shell">
<nav>
  <div class="nav-logo">Diatribes</div>
  <div class="nav-section">Report</div>
  <a href="#summary">Summary</a>
  <div class="nav-section">Approaches</div>
  <a href="#approach-free_mix">Free Mix</a>
  <a href="#approach-pos">POS Swap</a>
  <a href="#approach-sentence_alt">Alternating</a>
  <a href="#approach-immersion">Immersion</a>
  <a href="#approach-translation">Translations</a>
</nav>
<main>
  <div class="report-header">
    <h1>Approach Test Report</h1>
    <div class="meta">
      <span>Generated {now}</span>
      <span>{total_tests} test cases</span>
      <span>{len(lang_order)} languages: {", ".join(lang_order)}</span>
    </div>
  </div>

  <div id="summary" class="summary-card">
    <h3>Summary — Average Accuracy by Approach &amp; Language</h3>
    <table>
      <tr><th>Approach</th><th>Variant</th>{summary_header}</tr>
      {summary_rows}
    </table>
  </div>

  {approach_sections}
</main>
</div>

<script>
function showTab(btn, id) {{
  const panes = btn.closest('.variant-block');
  panes.querySelectorAll('.lang-tab').forEach(b => b.classList.remove('active'));
  panes.querySelectorAll('.tab-pane').forEach(p => p.classList.remove('active'));
  btn.classList.add('active');
  document.getElementById(id).classList.add('active');
}}

// Highlight active nav on scroll
const sections = document.querySelectorAll('section[id], div[id]');
const navLinks = document.querySelectorAll('nav a');
window.addEventListener('scroll', () => {{
  let current = '';
  sections.forEach(s => {{ if (window.scrollY >= s.offsetTop - 120) current = s.id; }});
  navLinks.forEach(a => {{
    a.classList.toggle('active', a.getAttribute('href') === '#' + current);
  }});
}});
</script>
</body>
</html>'''

# ─────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────

def main():
    print(f"Diatribes Exhaustive Approach Tests")
    print(f"Languages: {', '.join(LANGUAGES)}")
    print(f"Started: {datetime.now().strftime('%H:%M:%S')}")
    print("=" * 60)

    # Resume from saved results if available
    if os.path.exists(RESULTS_FILE):
        with open(RESULTS_FILE) as f:
            existing = json.load(f)
        print(f"Found {len(existing)} existing results — continuing from where we left off")
    else:
        existing = []

    all_results = run_all() if not existing else existing

    print(f"\n\nGenerating HTML report → {REPORT_FILE}")
    html = generate_html(all_results)
    with open(REPORT_FILE, "w") as f:
        f.write(html)
    print(f"Done. Open {REPORT_FILE} in a browser.")
    print(f"Finished: {datetime.now().strftime('%H:%M:%S')}")

if __name__ == "__main__":
    main()
