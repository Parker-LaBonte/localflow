#!/bin/zsh
# Small tier: full fine-tune of Qwen2.5-0.5B-Instruct on data6 (LoRA underfits at this size).
cd "$(dirname "$0")"
.venv/bin/mlx_lm.lora --model base/Qwen2.5-0.5B-Instruct --train --data data6 --fine-tune-type full \
  --iters 700 --batch-size 8 --learning-rate 2e-5 --mask-prompt --steps-per-eval 700 --save-every 350 \
  --max-seq-length 512 --adapter-path ad_S6b
