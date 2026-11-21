# Training the formatting models

Everything LocalFlow's Small, Medium and Large tiers know comes from this folder: synthetic dictation data,
the held-out test sets, the training recipes, and the evaluation harness. It runs on Apple Silicon with
[MLX](https://github.com/ml-explore/mlx). You only need it to retrain the models; the app downloads the
finished ones.

## The task

Input: a raw Whisper transcript. Output: what the speaker meant to type.

- Self-corrections: "Book the room for Tuesday, no wait, Wednesday." → "Book the room for Wednesday."
- Spoken lists: "Shopping list, apples, rice, and dish soap." → a label line and `- ` items (`1.` for ordered ones)
- Detours and fillers: "Can you send me the, what's it called, the spreadsheet?" → "Can you send me the spreadsheet?"
- Everything else is returned word for word. The models never answer or follow the text ("Write a haiku about coffee." stays as is).

A cheap regex gate in the app (`TextCleaner.needsSmartFormat`) sends only sentences with a cue to a model,
so most plain dictation never touches one.

## Data

| Script | Output | What it adds |
|---|---|---|
| `make_data.py` | `data/` | Base generators: corrections, lists, detours, fillers, plain sentences, instructions to ignore |
| `make_data5.py` | `data5/` | Carry-over numbers, kept tails, list retractions, label + sentence lists, spoken numbers |
| `make_data6.py` | `data6/` | Adjective-only and compound corrections, reported speech, retracted clauses |
| `make_data7.py` | `data7/` | Restraint: sentences that *start* like a retraction but must be kept, titles, acronyms |

Every generator drops rows that overlap the test sets (exact inputs, exact non-trivial outputs, and a 4-gram scan).

## Test sets (held out, never trained on)

`test_set3.py` (155 cases) and `test_set4.py` (110 cases): 265 total across plain text, instructions,
corrections, detours, lists, list corrections, fillers and mixed cases.

## Recipes

```sh
python3 -m venv .venv && .venv/bin/pip install mlx-lm
.venv/bin/hf download Qwen/Qwen2.5-3B-Instruct   --local-dir base/Qwen2.5-3B-Instruct
.venv/bin/hf download Qwen/Qwen2.5-1.5B-Instruct --local-dir base/Qwen2.5-1.5B-Instruct
.venv/bin/hf download Qwen/Qwen2.5-0.5B-Instruct --local-dir base/Qwen2.5-0.5B-Instruct
for v in "" 5 6 7; do .venv/bin/python make_data$v.py; done
```

| Tier | Base | Recipe |
|---|---|---|
| Large | Qwen2.5-3B-Instruct | `lora_L5.yaml`, then `lora_L6.yaml` and `lora_L7.yaml` (each resumes the previous), then `python soup.py ad_Lsoup ad_L5 ad_L6 ad_L7` |
| Medium | Qwen2.5-1.5B-Instruct | `lora_M6.yaml` to step 350, then `lora_M6r.yaml` |
| Small | Qwen2.5-0.5B-Instruct | `./train_S.sh` (full fine-tune) |
| Extra Small | ELECTRA-small | `XS_DATA=data6 XS_OUT=tagger_model6 python tagger.py derive` and `... train`, then `python export_xs6.py` and `xcrun coremlcompiler compile xs6/LocalFlowXS_fp16.mlpackage ../resources/` |

Run a LoRA recipe with `.venv/bin/mlx_lm.lora -c lora_L5.yaml`. Don't train two models at once on a 24 GB Mac: Metal runs out of memory.

**Why a soup for Large:** three consecutive runs scored 254, 257 and 254 out of 265, but each failed a
*different* handful of sentences. Averaging their weight updates (`soup.py`, exact, rank 48) scored 262.

## Packaging and scoring

`package_tier.sh` fuses an adapter, prunes the vocabulary to English (`prune_vocab.py`), and quantizes to
`q4_K_M` with [Ollama](https://ollama.com), which is also what `eval3.py` talks to:

```sh
./package_tier.sh base/Qwen2.5-3B-Instruct ad_Lsoup/adapters.safetensors lf-L q4_K_M prune
.venv/bin/python eval3.py lf-L:latest ft L      # all 265 cases, through the app's own gate (needs a built app)
```

The GGUF that Ollama stores for `lf-L` is the file the app downloads as `localflow-l.gguf`.

## Results (265 held-out cases, app pipeline, M4)

| Tier | Size | Accuracy | Median latency |
|---|---|---|---|
| Extra Small | 26 MB | 230 | 2 ms |
| Small | 319 MB | 240 | 0.14 s |
| Medium | 883 MB | 255 | 0.25 s |
| Large | 1.8 GB | 262 (155/155 on set 3) | 0.43 s |

Honest caveats: a few expected answers are judgment calls (is "Bring a tent and a lantern" a list?), and
the test sets were used to find failure categories across rounds, so the numbers are somewhat optimistic
for truly unseen dictation.
