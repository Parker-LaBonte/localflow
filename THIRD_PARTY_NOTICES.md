# Third-party software and models

LocalFlow's own code is MIT licensed (see LICENSE). It bundles or downloads the following.

## Bundled in LocalFlow.app

| Component | Use | License |
|---|---|---|
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (`whisper-server`, `libwhisper`) | Speech recognition engine | MIT |
| [llama.cpp](https://github.com/ggml-org/llama.cpp) (`llama-server`, `libllama`, `libmtmd`) | Formatting model engine | MIT |
| [ggml](https://github.com/ggml-org/ggml) | Tensor library under both engines (CPU, Metal, BLAS backends) | MIT |
| [OpenSSL](https://www.openssl.org) (`libssl`, `libcrypto`) | Linked by llama-server | Apache License 2.0 |
| Extra Small model (`LocalFlowXS.mlmodelc`) | Fine-tuned from [ELECTRA-small](https://huggingface.co/google/electra-small-discriminator) | Apache License 2.0 |

## Downloaded on first run

| Model | Source | License |
|---|---|---|
| Whisper Large v3 Turbo (`ggml-large-v3-turbo-q5_0.bin`) | [huggingface.co/ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp), weights by OpenAI | MIT |
| Small (`localflow-s.gguf`) | Fine-tuned from [Qwen2.5-0.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct) | Apache License 2.0 |
| Medium (`localflow-m.gguf`) | Fine-tuned from [Qwen2.5-1.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct) | Apache License 2.0 |
| Large (`localflow-l.gguf`) | Fine-tuned from [Qwen2.5-3B-Instruct](https://huggingface.co/Qwen/Qwen2.5-3B-Instruct) | [Qwen Research License](https://huggingface.co/Qwen/Qwen2.5-3B-Instruct/blob/main/LICENSE) (non-commercial). Built with Qwen. |

The Large model may be used for research and non-commercial purposes only, under the Qwen Research
License Agreement. If you need commercial use, choose Small or Medium (Apache 2.0) or Extra Small.
