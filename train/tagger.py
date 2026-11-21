"""XS tier: ELECTRA-small word tagger. Can only keep/delete/punctuate/structure the speaker's own words
(no generation => no hallucination).
  python tagger.py derive   -> data/tagger_{train,valid}.jsonl (labels derived from the LLM training pairs)
  python tagger.py train    -> tagger_model/
  python tagger.py eval     -> score on test_set3
"""
import json, re, sys, difflib, random, os
DATA = os.environ.get("XS_DATA", "data")      # LLM training pairs to derive labels from
OUT = os.environ.get("XS_OUT", "tagger_model")

LABELS = ["K", "C", "E", "D", "B", "N", "L"]
# K keep as-is | C keep, strip trailing punctuation | E keep, end sentence with "." | D delete
# B keep + starts "- " item | N keep + starts numbered item | L keep + ends list label (":" + newline)
L2I = {l: i for i, l in enumerate(LABELS)}
PUNCT = ",.;:!?"

def words(text):
    return re.findall(r"\n+|[^\s]+", text)

def core(w):
    return re.sub(r"[^\w']", "", w.lower())

def derive_labels(inp, out):
    """Return per-word labels for inp so that render(inp, labels) ~= out, or None if out needs words not in inp."""
    iw = words(inp)
    lines = out.split("\n")
    is_list = len(lines) > 1 and lines[0].rstrip().endswith(":") and re.match(r"^(- |\d+\. )", lines[1] or "")
    out_tokens = []  # (word, role) role in {None, "B", "N", "L"}
    if is_list:
        lab = lines[0].rstrip()[:-1].split()
        for j, w in enumerate(lab): out_tokens.append((w, "L" if j == len(lab) - 1 else None))
        for line in lines[1:]:
            if not line.strip(): continue
            m = re.match(r"^(- |\d+\. )(.*)$", line)
            if not m: return None
            role = "B" if m.group(1) == "- " else "N"
            for j, w in enumerate(m.group(2).split()): out_tokens.append((w, role if j == 0 else None))
    else:
        for w in words(out): out_tokens.append((w, None))
    a = [core(w) or w for w in iw]; b = [core(w) or w for w, _ in out_tokens]
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    labels = ["D"] * len(iw)
    covered = 0
    for blk in sm.get_matching_blocks():
        for k in range(blk.size):
            i, j = blk.a + k, blk.b + k
            src, (dst, role) = iw[i], out_tokens[j]
            covered += 1
            if role: labels[i] = role
            elif src == dst or src.startswith("\n"): labels[i] = "K"
            elif dst.endswith(".") and not src.endswith("."): labels[i] = "E"
            elif src.rstrip(PUNCT) == dst.rstrip(PUNCT) and len(dst) < len(src): labels[i] = "C"
            else: labels[i] = "K"
    if covered < len(out_tokens): return None  # output contains words the input never said (rewrite) -> skip
    return labels

def render(inp, labels):
    iw = words(inp)
    kept = [(w, l) for w, l in zip(iw, labels) if l != "D"]
    if not kept: return inp
    if any(l in "BN" for _, l in kept):
        label_words, items, cur = [], [], None
        for w, l in kept:
            if l in "BN":
                cur = [l, [w]]; items.append(cur)
            elif cur is None: label_words.append(w)
            else: cur[1].append(w)
        def clean(ws):
            s = " ".join(ws).strip()
            s = re.sub(r"[,.;:]+$", "", s)
            return s[:1].upper() + s[1:]
        out = []
        if label_words: out.append(clean(label_words) + ":")
        n = 0
        for kind, ws in items:
            n += 1
            out.append(("- " if kind == "B" else f"{n}. ") + clean(ws))
        return "\n".join(out)
    toks = []
    for w, l in kept:
        if w.startswith("\n"): toks.append(w); continue
        if l == "C": w = w.rstrip(PUNCT) or w
        if l == "E": w = w.rstrip(PUNCT) + "."
        toks.append(w)
    s = ""
    for t in toks:
        s += t if (not s or s.endswith("\n") or t.startswith("\n")) else " " + t
    s = re.sub(r"\s+([,.!?])", r"\1", s)
    s = re.sub(r"[,;]\s*([.!?])", r"\1", s)
    s = re.sub(r",\s*$", ".", s.strip())
    if inp.rstrip()[-1:] in ".!?" and s[-1:] not in ".!?": s += inp.rstrip()[-1]
    # capitalize sentence starts
    s = re.sub(r"(^|[.!?]\s+|\n)([a-z])", lambda m: m.group(1) + m.group(2).upper(), s)
    return s

def derive():
    rows = [json.loads(l) for f in (f"{DATA}/train.jsonl", f"{DATA}/valid.jsonl") for l in open(f)]
    ok = skipped = 0; out = []
    for r in rows:
        inp = re.sub(r"</?transcript>", "", r["messages"][1]["content"]); tgt = r["messages"][2]["content"]
        lab = derive_labels(inp, tgt)
        if lab is None: skipped += 1; continue
        ok += 1; out.append({"words": words(inp), "labels": lab, "target": tgt})
    random.seed(1); random.shuffle(out)
    nv = len(out) // 12
    for name, part in (("valid", out[:nv]), ("train", out[nv:])):
        with open(f"{DATA}/tagger_{name}.jsonl", "w") as f:
            for x in part: f.write(json.dumps(x) + "\n")
    # how faithful is the label scheme itself? (render with gold labels)
    exact = sum(1 for x in out if render(" ".join(x["words"]).replace(" \n", "\n").replace("\n ", "\n"), x["labels"]).strip() == x["target"].strip())
    print(f"derived {ok}, skipped (needs rewriting) {skipped}; gold-label render exact {exact}/{ok}")

def word_inputs(tok, ws):
    ws2 = ["[unused1]" if w.startswith("\n") else w for w in ws]
    return tok(ws2, is_split_into_words=True, truncation=True, max_length=256, return_tensors="pt")

def train():
    import torch
    from transformers import AutoTokenizer, AutoModelForTokenClassification
    tok = AutoTokenizer.from_pretrained("base/electra-small")
    model = AutoModelForTokenClassification.from_pretrained("base/electra-small", num_labels=len(LABELS))
    data = [json.loads(l) for l in open(f"{DATA}/tagger_train.jsonl")]
    valid = [json.loads(l) for l in open(f"{DATA}/tagger_valid.jsonl")]
    def enc(x):
        e = word_inputs(tok, x["words"]); wid = e.word_ids(0); lab = []; prev = None
        for w in wid:
            lab.append(-100 if w is None or w == prev else L2I[x["labels"][w]]); prev = w
        e["labels"] = torch.tensor([lab]); return e
    opt = torch.optim.AdamW(model.parameters(), lr=1e-4, weight_decay=0.01)
    epochs = 12; steps = epochs * len(data); step = 0
    sched = torch.optim.lr_scheduler.LambdaLR(opt, lambda s: min(1, s / 200) * max(0.0, 1 - s / steps))
    torch.manual_seed(0)
    for ep in range(epochs):
        model.train(); random.shuffle(data); tot = 0
        for x in data:
            loss = model(**enc(x)).loss; loss.backward(); opt.step(); sched.step(); opt.zero_grad(); tot += loss.item(); step += 1
        model.eval(); good = 0
        with torch.no_grad():
            for x in valid:
                if predict_words(tok, model, x["words"]) == x["labels"]: good += 1
        print(f"epoch {ep+1}: train loss {tot/len(data):.4f}  valid exact-labels {good}/{len(valid)}", flush=True)
    model.save_pretrained(OUT); tok.save_pretrained(OUT)

def predict_words(tok, model, ws):
    import torch
    e = word_inputs(tok, ws)
    with torch.no_grad(): logits = model(**e).logits[0]
    wid = e.word_ids(0); out = ["K"] * len(ws); prev = None
    for t, w in enumerate(wid):
        if w is not None and w != prev: out[w] = LABELS[int(logits[t].argmax())]
        prev = w
    return out

def format_text(tok, model, text):
    return render(text, predict_words(tok, model, words(text)))

def evaluate():
    import time, torch
    from transformers import AutoTokenizer, AutoModelForTokenClassification
    sys.path.insert(0, ".")
    from eval3 import TEST3
    from eval3 import score_rows
    tok = AutoTokenizer.from_pretrained(OUT); model = AutoModelForTokenClassification.from_pretrained(OUT).eval()
    rows = []
    for inp, want in TEST3:
        t = time.time(); out = format_text(tok, model, inp); rows.append((inp, out, want, time.time() - t))
    score_rows("XS-tagger", rows)

if __name__ == "__main__":
    {"derive": derive, "train": train, "eval": evaluate}[sys.argv[1]]()
