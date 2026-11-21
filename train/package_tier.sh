#!/bin/zsh
# usage: package_tier.sh <base_dir> <adapter_file> <ollama_name> <quant: q4_K_M|q8_0|f16|...> [prune]
set -e
cd "$(dirname "$0")"
BASE=$1; AD=$2; NAME=$3; Q=$4; PRUNE=$5
W=work_$NAME; rm -rf $W; mkdir -p $W/ad
cp $(dirname $AD)/adapter_config.json $W/ad/; cp $AD $W/ad/adapters.safetensors
.venv/bin/mlx_lm.fuse --model $BASE --adapter-path $W/ad --save-path $W/fused --dequantize >/dev/null 2>&1
SRC=$W/fused
if [[ "$PRUNE" == "prune" ]]; then .venv/bin/python prune_vocab.py $W/fused $W/pruned words+used 2>&1 | grep -E "kept|params"; SRC=$W/pruned; fi
{ echo "FROM $PWD/$SRC"; printf 'TEMPLATE """%s"""\n' "$(cat template.txt)"; echo 'PARAMETER stop "<|im_end|>"'; echo 'PARAMETER temperature 0'; echo 'PARAMETER num_ctx 1024'; } > $W/Modelfile
if [[ "$Q" == "f16" ]]; then ollama create $NAME -f $W/Modelfile 2>&1 | tail -1; else ollama create $NAME -f $W/Modelfile --quantize $Q 2>&1 | tr "\r" "\n" | grep -iE "error|success" | tail -1; fi
rm -rf $W/fused $W/pruned
ollama list | grep "^$NAME:" | awk "{print \$1, \$3, \$4}"
