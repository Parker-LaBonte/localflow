"""Score XS exactly as the app runs it: the built binary's Swift Core ML tagger (LocalFlow --xs) on all held-out cases."""
import json, subprocess, time, pathlib
from eval3 import TEST3, score_rows, APP_BIN
BIN = APP_BIN
rows = []
for inp, want in TEST3:
    t = time.time()
    out = subprocess.run([BIN, "--xs", inp], capture_output=True, text=True).stdout.strip()
    out = json.loads(out.replace("\\'", "'")) if out.startswith('"') else out
    rows.append((inp, out, want, time.time() - t))
score_rows("XS-app", rows)
