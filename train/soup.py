"""Average several LoRA runs into one adapter ("model soup"), exactly.

Each run i adds a weight update B_i @ A_i. The average (1/n) * sum(B_i @ A_i) is itself a LoRA of rank n*r:
stack the A matrices side by side and the B matrices on top of each other, with B divided by n.
The Large tier is the soup of rounds 5, 6 and 7: each run alone scored 254-257/265 and failed *different*
sentences; the soup scored 262/265.

usage: python soup.py <out_dir> <adapter_dir> <adapter_dir> ...
"""
import json, sys
import mlx.core as mx

out, srcs = sys.argv[1], sys.argv[2:]
ws = [mx.load(f"{s}/adapters.safetensors") for s in srcs]
n = len(ws)
soup = {}
for k in ws[0]:
    if k.endswith("lora_a"):
        soup[k] = mx.concatenate([w[k] for w in ws], axis=1)
    elif k.endswith("lora_b"):
        soup[k] = mx.concatenate([w[k] for w in ws], axis=0) / n

import os
os.makedirs(out, exist_ok=True)
mx.save_safetensors(f"{out}/adapters.safetensors", soup)
cfg = json.load(open(f"{srcs[0]}/adapter_config.json"))
cfg["lora_parameters"]["rank"] *= n          # scale is fixed (not alpha/rank), so it stays as is
cfg["adapter_path"] = out
json.dump(cfg, open(f"{out}/adapter_config.json", "w"), indent=2)
print(f"{out}: {n} runs, rank {cfg['lora_parameters']['rank']}, {len(soup)} tensors")
