"""Score a tier on test_set3, both model-only and as the app runs it (cue gate in front).
usage: eval3.py <ollama-model> [ft|app]"""
import json, re, sys, time, difflib, urllib.request, subprocess
from test_set3 import TEST3, CATEGORY
from test_set4 import TEST4, CATEGORY4
import os
if os.environ.get("TESTSET", "all") == "all":   # 265 held-out cases (set 3 + set 4); TESTSET=3 for the old 155
    TEST3 = TEST3 + TEST4; CATEGORY = {**CATEGORY, **CATEGORY4}
PREFIX = "resall_" if os.environ.get("TESTSET", "all") == "all" else "res3_"
from make_data import SYSTEM as FT_SYSTEM, wrap

def norm(s):
    s = s.replace("’", "'").strip()
    return "\n".join(re.sub(r"[ \t]+", " ", l).strip().rstrip(".").lower() for l in s.split("\n"))

# The app's real gate (Swift), via the built binary (override with LOCALFLOW_BIN).
import os, pathlib
APP_BIN = os.environ.get("LOCALFLOW_BIN") or next(
    (str(p) for p in [pathlib.Path.home() / "Applications/LocalFlow.app/Contents/MacOS/LocalFlow",
                      pathlib.Path("/Applications/LocalFlow.app/Contents/MacOS/LocalFlow")] if p.exists()), "LocalFlow")
_gate_cache = {}
def gated(text):
    if text not in _gate_cache:
        r = subprocess.run([APP_BIN, "--gate", text], capture_output=True, text=True)
        _gate_cache[text] = r.stdout.strip() == "1"
    return _gate_cache[text]

def score_rows(name, rows):
    """rows: (inp, model_out, want, seconds)"""
    res = {"model": {}, "app": {}}
    for mode in ("model", "app"):
        ex = near = 0; cats = {}
        for inp, out, want, _ in rows:
            o = out if (mode == "model" or gated(inp)) else inp
            ok = norm(o) == norm(want); sim = difflib.SequenceMatcher(None, norm(o), norm(want)).ratio()
            ex += ok; near += (not ok and sim >= 0.9)
            c = cats.setdefault(CATEGORY[inp], [0, 0]); c[0] += ok; c[1] += 1
        res[mode] = {"exact": ex, "near": near, "n": len(rows), "cats": cats}
    lat = sorted(r[3] for r in rows)
    res["median_s"] = lat[len(lat) // 2]; res["p90_s"] = lat[int(len(lat) * .9)]
    a, m = res["app"], res["model"]
    print(f"== {name}: APP exact {a['exact']}/{a['n']} (near {a['near']})  model-only {m['exact']}/{m['n']}  |  median {res['median_s']:.2f}s p90 {res['p90_s']:.2f}s")
    print("   by category (app):", {k: f"{v[0]}/{v[1]}" for k, v in a["cats"].items()})
    res["fails"] = [(i, o, w) for i, o, w, _ in rows if norm(o if gated(i) else i) != norm(w)]
    json.dump(res, open(f"{PREFIX}{name.replace(':', '_')}.json", "w"), indent=1)
    if "-v" in sys.argv:
        for i, o, w in res["fails"]: print(f"  x {i!r}\n     got  {(o if gated(i) else i)!r}\n     want {w!r}")
    return res

def call(model, mode, text):
    if mode == "ft": msgs = [{"role": "system", "content": FT_SYSTEM}, {"role": "user", "content": wrap(text)}]
    else:
        src = open("../main.swift").read()
        sysm = re.search(r'static let system = """\n(.*?)\n    """', src, re.S).group(1).replace("\n    ", "\n").strip()
        msgs = [{"role": "system", "content": sysm}]
        for a, b in re.findall(r'\("((?:[^"\\]|\\.)*)", "((?:[^"\\]|\\.)*)"\),', src.split("static let shots")[1].split("]")[0]):
            msgs += [{"role": "user", "content": wrap(json.loads('"' + a + '"'))}, {"role": "assistant", "content": json.loads('"' + b + '"')}]
        msgs.append({"role": "user", "content": wrap(text)})
    body = json.dumps({"model": model, "messages": msgs, "stream": False, "think": False, "keep_alive": "10m", "options": {"temperature": 0}}).encode()
    t = time.time()
    r = json.load(urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:11434/api/chat", body, {"Content-Type": "application/json"})))
    out = re.sub(r"</?transcript>", "", r["message"]["content"]).strip()
    if not out or len(out) > len(text) * 1.4 + 30: out = text
    return out, time.time() - t

if __name__ == "__main__":
    model, mode = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] in ("ft", "app") else "ft")
    call(model, mode, "warm up")
    rows = []
    for inp, want in TEST3:
        out, dt = call(model, mode, inp); rows.append((inp, out, want, dt))
    score_rows(sys.argv[3] if len(sys.argv) > 3 and not sys.argv[3].startswith("-") else model, rows)
