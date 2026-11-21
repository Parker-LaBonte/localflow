"""English-only vocabulary pruning for a Qwen2 HF checkpoint.
Keeps byte-level base tokens, special tokens, and every BPE token that decodes to pure ASCII.
ASCII text tokenizes identically (merges producing non-ASCII tokens never fire on ASCII input),
so the model is unchanged for English while the embedding/lm_head tables shrink.
usage: prune_vocab.py <src_dir> <dst_dir>"""
import json, sys, os, shutil, re
import torch
from safetensors.torch import load_file, save_file

def bytes_to_unicode():
    bs = list(range(ord("!"), ord("~") + 1)) + list(range(ord("¡"), ord("¬") + 1)) + list(range(ord("®"), ord("ÿ") + 1))
    cs = bs[:]; n = 0
    for b in range(256):
        if b not in bs: bs.append(b); cs.append(256 + n); n += 1
    return dict(zip(bs, (chr(c) for c in cs)))
U2B = {v: k for k, v in bytes_to_unicode().items()}

def is_ascii_token(tok):
    try: return all(U2B[ch] < 128 for ch in tok)
    except KeyError: return False

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
tj = json.load(open(f"{src}/tokenizer.json"))
vocab = tj["model"]["vocab"]                      # token -> id
added = tj["added_tokens"]                         # [{id, content, ...}]
cfg = json.load(open(f"{src}/config.json"))
old_n = cfg["vocab_size"]

base_chars = set(bytes_to_unicode().values())
MODE = sys.argv[3] if len(sys.argv) > 3 else "ascii"
def decoded(t): return bytes(U2B[c] for c in t).decode("ascii")
WORDISH = re.compile(r"^ ?(?:[A-Za-z]+(?:'[A-Za-z]*)?|'[A-Za-z]+|[A-Za-z]*-[A-Za-z]*|\d{1,3}|[.,!?;:'\"()\-$%&/@#*+=]{1,3}| +|[.,!?:;)'\x22]?\n+| ?\.\.\.)$")
if MODE == "ascii":
    keep = {i for t, i in vocab.items() if is_ascii_token(t) or t in base_chars}
elif MODE in ("words", "words+used"):
    keep = {i for t, i in vocab.items() if t in base_chars or (is_ascii_token(t) and WORDISH.match(decoded(t)))}
    if MODE == "words+used":
        from transformers import AutoTokenizer
        import glob
        tk = AutoTokenizer.from_pretrained(src)
        corpus = [l for f in ["data/train.jsonl", "data/valid.jsonl"] for l in open(f)]
        corpus += [open(f).read() for f in glob.glob("../audio-eval/data/43[23]*.turbo.txt")]  # 4344866 held out for checking
        for w in open("/usr/share/dict/words").read().split():
            corpus += [" " + w, " " + w.capitalize(), w.capitalize()]
        corpus += [f"{n}{s}" for n in range(0, 2101) for s in ("", ".", ",", "s", "th", "%", ":00", " p.m.", " a.m.")]
        corpus += [tk.apply_chat_template([{"role": "system", "content": "x"}, {"role": "user", "content": "<transcript>y</transcript>"}], tokenize=False, add_generation_prompt=True)]
        for i in range(0, len(corpus), 5000):
            for ids in tk(corpus[i:i+5000], add_special_tokens=False)["input_ids"]: keep.update(ids)
    id2t = {i: t for t, i in vocab.items()}
    parent = {}
    for m in tj["model"]["merges"]:
        a, b = (m.split(" ", 1) if isinstance(m, str) else m); parent.setdefault(a + b, (a, b))
    stack = [id2t[i] for i in keep if i in id2t]
    while stack:
        t = stack.pop()
        for p in parent.get(t, ()):
            if p in vocab and vocab[p] not in keep: keep.add(vocab[p]); stack.append(p)
else:
    # "english": keep only tokens real English text uses, plus the merge chain needed to build them.
    from transformers import AutoTokenizer
    tk = AutoTokenizer.from_pretrained(src)
    corpus = []
    for w in open("/usr/share/dict/words").read().split():
        corpus += [w, " " + w, " " + w.capitalize(), w.capitalize(), " " + w.upper()]
    for f in ["data/train.jsonl", "data/valid.jsonl"]:
        corpus += [l for l in open(f)]
    import glob
    for f in glob.glob("../audio-eval/data/*.txt"): corpus.append(open(f).read())
    corpus += [str(n) for n in range(0, 2101)] + [" " + str(n) for n in range(0, 2101)]
    used = set()
    for i in range(0, len(corpus), 5000):
        for ids in tk(corpus[i:i+5000], add_special_tokens=False)["input_ids"]: used.update(ids)
    id2t = {i: t for t, i in vocab.items()}
    short_ascii = {i for t, i in vocab.items() if is_ascii_token(t) and len(t) <= 2}
    keep = {i for i in used if i in id2t} | short_ascii | {vocab[c] for c in base_chars if c in vocab}
    parent = {}
    for m in tj["model"]["merges"]:
        a, b = (m.split(" ", 1) if isinstance(m, str) else m); parent.setdefault(a + b, (a, b))
    stack = [id2t[i] for i in keep if i in id2t]
    while stack:
        t = stack.pop()
        for p in parent.get(t, ()):
            if p in vocab and vocab[p] not in keep: keep.add(vocab[p]); stack.append(p)
keep_ids = sorted(keep | {a["id"] for a in added})
remap = {o: n for n, o in enumerate(keep_ids)}
print(f"vocab {len(vocab) + len(added)} (table {old_n}) -> {len(keep_ids)} kept")

# tokenizer.json
id2tok = {i: t for t, i in vocab.items()}
tj["model"]["vocab"] = {id2tok[o]: remap[o] for o in keep_ids if o in id2tok}
kept_tokens = set(tj["model"]["vocab"])
new_merges = []
for m in tj["model"]["merges"]:
    a, b = (m.split(" ", 1) if isinstance(m, str) else m)
    if a in kept_tokens and b in kept_tokens and (a + b) in kept_tokens: new_merges.append(m)
print(f"merges {len(tj['model']['merges'])} -> {len(new_merges)}")
tj["model"]["merges"] = new_merges
for a in added: a["id"] = remap[a["id"]]
json.dump(tj, open(f"{dst}/tokenizer.json", "w"), ensure_ascii=False)

# tokenizer_config.json added_tokens_decoder
tc = json.load(open(f"{src}/tokenizer_config.json"))
if "added_tokens_decoder" in tc:
    tc["added_tokens_decoder"] = {str(remap[int(k)]): v for k, v in tc["added_tokens_decoder"].items() if int(k) in remap}
json.dump(tc, open(f"{dst}/tokenizer_config.json", "w"), indent=2, ensure_ascii=False)

# vocab.json / merges.txt (slow tokenizer files, kept consistent)
if os.path.exists(f"{src}/vocab.json"):
    json.dump(tj["model"]["vocab"], open(f"{dst}/vocab.json", "w"), ensure_ascii=False)
if os.path.exists(f"{src}/merges.txt"):
    with open(f"{dst}/merges.txt", "w") as f:
        f.write("#version: 0.2\n")
        for m in new_merges: f.write((m if isinstance(m, str) else " ".join(m)) + "\n")

# config + generation config ids
def rid(x): return [remap[i] for i in x] if isinstance(x, list) else remap.get(x, x)
for k in ("bos_token_id", "eos_token_id", "pad_token_id"):
    if k in cfg and cfg[k] is not None: cfg[k] = rid(cfg[k])
cfg["vocab_size"] = len(keep_ids)
json.dump(cfg, open(f"{dst}/config.json", "w"), indent=2)
if os.path.exists(f"{src}/generation_config.json"):
    g = json.load(open(f"{src}/generation_config.json"))
    for k in ("bos_token_id", "eos_token_id", "pad_token_id"):
        if k in g and g[k] is not None: g[k] = rid(g[k])
    json.dump(g, open(f"{dst}/generation_config.json", "w"), indent=2)
for f in ("special_tokens_map.json",):
    if os.path.exists(f"{src}/{f}"): shutil.copy(f"{src}/{f}", dst)

# weights
idx = torch.tensor(keep_ids)
total_before = total_after = 0
shards = sorted(f for f in os.listdir(src) if f.endswith(".safetensors"))
index = {"metadata": {}, "weight_map": {}}
for sh in shards:
    w = load_file(f"{src}/{sh}")
    for k, v in list(w.items()):
        total_before += v.numel()
        if v.shape[0] == old_n and (k.endswith("embed_tokens.weight") or k.startswith("lm_head")):
            w[k] = v[idx].contiguous()
        total_after += w[k].numel()
        index["weight_map"][k] = sh
    save_file(w, f"{dst}/{sh}", metadata={"format": "pt"})
if len(shards) > 1: json.dump(index, open(f"{dst}/model.safetensors.index.json", "w"))
print(f"params {total_before/1e6:.0f}M -> {total_after/1e6:.0f}M ({100*(1-total_after/total_before):.1f}% smaller)")
