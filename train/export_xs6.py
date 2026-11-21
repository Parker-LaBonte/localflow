import torch, numpy as np, coremltools as ct, json
from transformers import AutoTokenizer, AutoModelForTokenClassification
tok = AutoTokenizer.from_pretrained("tagger_model6")
m = AutoModelForTokenClassification.from_pretrained("tagger_model6", return_dict=False).eval()
class W(torch.nn.Module):
    """Explicit forward (avoids HF mask helpers Core ML can't convert)."""
    def __init__(s, m): super().__init__(); s.m = m
    def forward(s, ids, mask):
        e = s.m.electra
        pos = torch.arange(ids.shape[1]).unsqueeze(0)
        h = e.embeddings(input_ids=ids, token_type_ids=torch.zeros_like(ids), position_ids=pos)
        if hasattr(e, "embeddings_project"): h = e.embeddings_project(h)
        ext = (1.0 - mask[:, None, None, :].float()) * -10000.0
        for layer in e.encoder.layer:
            out = layer(h, attention_mask=ext)
            h = out[0] if isinstance(out, tuple) else out
        return s.m.classifier(h)
ex = tok("hello world", return_tensors="pt")
tr = torch.jit.trace(W(m).eval(), (ex["input_ids"], ex["attention_mask"]))
shape = ct.Shape(shape=(1, ct.RangeDim(1, 256, default=32)))
ml = ct.convert(tr, inputs=[ct.TensorType(name="input_ids", shape=shape, dtype=np.int32),
                            ct.TensorType(name="attention_mask", shape=shape, dtype=np.int32)],
                outputs=[ct.TensorType(name="logits")], minimum_deployment_target=ct.target.macOS14,
                compute_precision=ct.precision.FLOAT16)
ml.save("xs6/LocalFlowXS_fp16.mlpackage")
from coremltools.optimize.coreml import linear_quantize_weights, OptimizationConfig, OpLinearQuantizerConfig
q = linear_quantize_weights(ml, OptimizationConfig(global_config=OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8")))
q.save("xs6/LocalFlowXS_int8.mlpackage")
# parity check vs torch on test inputs (CPU; also checks the Neural Engine path)
q = ct.models.MLModel("xs6/LocalFlowXS_int8.mlpackage", compute_units=ct.ComputeUnit.CPU_AND_NE)
from test_set3 import TEST3
import tagger
agree = 0
for inp, _ in TEST3:
    ws = tagger.words(inp); e = tagger.word_inputs(tok, ws)
    t_logits = m(input_ids=e["input_ids"], attention_mask=e["attention_mask"])[0][0].detach().numpy()
    c_logits = q.predict({"input_ids": e["input_ids"].numpy().astype(np.int32), "attention_mask": e["attention_mask"].numpy().astype(np.int32)})["logits"][0]
    w_logits = W(m)(e["input_ids"], e["attention_mask"])[0].detach().numpy()
    agree += (t_logits.argmax(-1) == c_logits.argmax(-1)).all()
    wrap_ok = (t_logits.argmax(-1) == w_logits.argmax(-1)).all(); assert wrap_ok, "wrapper differs from HF forward"
print(f"int8 Core ML agrees with PyTorch on {agree}/{len(TEST3)} sentences (every word label)")
