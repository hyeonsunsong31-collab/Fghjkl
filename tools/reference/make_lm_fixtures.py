#!/usr/bin/env python3
"""Generate reference fixtures for Jarvis' Deep-Think runtime tests.

1. A tiny random Qwen3 model, MLX-style affine 4-bit quantised (group 32),
   written as safetensors + config.json, and reference logits computed with an
   independent NumPy implementation of the Qwen3 decoder.
2. A small byte-level BPE tokenizer (Qwen pre-tokenizer regex, special tokens)
   trained with Hugging Face `tokenizers`, plus reference encodings.

Usage: python3 tools/reference/make_lm_fixtures.py Tests/JarvisCoreTests/Fixtures
"""
import json
import struct
import sys
from pathlib import Path

import numpy as np

QWEN_PATTERN = r"(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+"

CFG = dict(hidden_size=64, num_hidden_layers=2, num_attention_heads=4, num_key_value_heads=2, head_dim=16,
           intermediate_size=96, vocab_size=320, rms_norm_eps=1e-6, rope_theta=1000000.0,
           tie_word_embeddings=True, quantization={"group_size": 32, "bits": 4})


def bf16_round(a):
    """Round float32 → bfloat16 (returned as float32 values and uint16 bits)."""
    a = np.asarray(a, dtype=np.float32)
    bits = a.view(np.uint32).astype(np.uint64)
    rounded = ((bits + 0x7FFF + ((bits >> 16) & 1)) >> 16).astype(np.uint16)
    back = (rounded.astype(np.uint32) << 16).view(np.float32)
    return back, rounded


def quantize(w, group=32, bits=4):
    """MLX affine quantisation: w ≈ scale * q + bias per group."""
    out_f, in_f = w.shape
    g = w.reshape(out_f, in_f // group, group)
    w_min = g.min(axis=2)
    w_max = g.max(axis=2)
    scale = (w_max - w_min) / (2 ** bits - 1)
    scale = np.where(scale == 0, 1e-8, scale)
    scale, scale_bits = bf16_round(scale)
    bias, bias_bits = bf16_round(w_min)
    q = np.clip(np.round((g - bias[..., None]) / scale[..., None]), 0, 2 ** bits - 1).astype(np.uint32)
    deq = (q * scale[..., None] + bias[..., None]).reshape(out_f, in_f).astype(np.float32)
    q = q.reshape(out_f, in_f)
    per_word = 32 // bits
    packed = np.zeros((out_f, in_f // per_word), dtype=np.uint32)
    for k in range(per_word):
        packed |= q[:, k::per_word] << (bits * k)
    return packed, scale_bits.reshape(out_f, -1), bias_bits.reshape(out_f, -1), deq


def write_safetensors(path, tensors, misalign=False):
    header = {}
    blobs = []
    offset = 0
    for name, (dtype, shape, data) in tensors.items():
        raw = data.tobytes()
        header[name] = {"dtype": dtype, "shape": list(shape), "data_offsets": [offset, offset + len(raw)]}
        blobs.append(raw)
        offset += len(raw)
    h = json.dumps(header, separators=(",", ":")).encode()
    h += b" " * ((8 - len(h) % 8) % 8)
    if misalign:
        # Real MLX files often start their data at an odd offset; reproduce that.
        h += b" "
    with open(path, "wb") as f:
        f.write(struct.pack("<Q", len(h)))
        f.write(h)
        for b in blobs:
            f.write(b)


def rmsnorm(x, w, eps):
    return x / np.sqrt(np.mean(x * x) + eps) * w


def rope(v, heads, hd, pos, theta):
    half = hd // 2
    v = v.reshape(heads, hd).copy()
    i = np.arange(half)
    freq = 1.0 / (theta ** (2 * i / hd))
    ang = pos * freq
    c, s = np.cos(ang), np.sin(ang)
    a, b = v[:, :half].copy(), v[:, half:].copy()
    v[:, :half] = a * c - b * s
    v[:, half:] = b * c + a * s
    return v.reshape(-1)


def make_model(out_dir: Path):
    rng = np.random.default_rng(1234)
    c = CFG
    H, L, nh, nkv, hd, I, V = (c["hidden_size"], c["num_hidden_layers"], c["num_attention_heads"],
                               c["num_key_value_heads"], c["head_dim"], c["intermediate_size"], c["vocab_size"])
    tensors = {}
    deq = {}

    def add_linear(name, out_f, in_f, scale=0.15):
        w = (rng.standard_normal((out_f, in_f)) * scale).astype(np.float32)
        packed, s, b, d = quantize(w)
        tensors[name + ".weight"] = ("U32", packed.shape, packed)
        tensors[name + ".scales"] = ("BF16", s.shape, s)
        tensors[name + ".biases"] = ("BF16", b.shape, b)
        deq[name] = d

    def add_norm(name, n):
        w = (1.0 + 0.1 * rng.standard_normal(n)).astype(np.float32)
        tensors[name + ".weight"] = ("F32", w.shape, w)
        deq[name] = w

    add_linear("model.embed_tokens", V, H, 0.5)
    for l in range(L):
        p = f"model.layers.{l}."
        add_norm(p + "input_layernorm", H)
        add_norm(p + "post_attention_layernorm", H)
        add_norm(p + "self_attn.q_norm", hd)
        add_norm(p + "self_attn.k_norm", hd)
        add_linear(p + "self_attn.q_proj", nh * hd, H)
        add_linear(p + "self_attn.k_proj", nkv * hd, H)
        add_linear(p + "self_attn.v_proj", nkv * hd, H)
        add_linear(p + "self_attn.o_proj", H, nh * hd)
        add_linear(p + "mlp.gate_proj", I, H)
        add_linear(p + "mlp.up_proj", I, H)
        add_linear(p + "mlp.down_proj", H, I)
    add_norm("model.norm", H)

    out_dir.mkdir(parents=True, exist_ok=True)
    write_safetensors(out_dir / "model.safetensors", tensors)
    (out_dir / "config.json").write_text(json.dumps(c, indent=1))
    unaligned = out_dir.parent / (out_dir.name + "_unaligned")
    unaligned.mkdir(parents=True, exist_ok=True)
    write_safetensors(unaligned / "model.safetensors", tensors, misalign=True)
    (unaligned / "config.json").write_text(json.dumps(c, indent=1))

    # Reference forward pass.
    tokens = [5, 17, 200, 3, 99, 311]
    kc = [[] for _ in range(L)]
    vc = [[] for _ in range(L)]
    all_logits = []
    groups = nh // nkv
    for pos, t in enumerate(tokens):
        x = deq["model.embed_tokens"][t].copy()
        for l in range(L):
            p = f"model.layers.{l}."
            h = rmsnorm(x, deq[p + "input_layernorm"], c["rms_norm_eps"])
            q = deq[p + "self_attn.q_proj"] @ h
            k = deq[p + "self_attn.k_proj"] @ h
            v = deq[p + "self_attn.v_proj"] @ h
            q = np.concatenate([rmsnorm(q[i * hd:(i + 1) * hd], deq[p + "self_attn.q_norm"], c["rms_norm_eps"]) for i in range(nh)])
            k = np.concatenate([rmsnorm(k[i * hd:(i + 1) * hd], deq[p + "self_attn.k_norm"], c["rms_norm_eps"]) for i in range(nkv)])
            q = rope(q, nh, hd, pos, c["rope_theta"])
            k = rope(k, nkv, hd, pos, c["rope_theta"])
            kc[l].append(k)
            vc[l].append(v)
            K = np.stack(kc[l])
            Vv = np.stack(vc[l])
            out = np.zeros(nh * hd, dtype=np.float32)
            for head in range(nh):
                kvh = head // groups
                qh = q[head * hd:(head + 1) * hd]
                sc = K[:, kvh * hd:(kvh + 1) * hd] @ qh / np.sqrt(hd)
                w = np.exp(sc - sc.max())
                w /= w.sum()
                out[head * hd:(head + 1) * hd] = w @ Vv[:, kvh * hd:(kvh + 1) * hd]
            x = x + deq[p + "self_attn.o_proj"] @ out
            h2 = rmsnorm(x, deq[p + "post_attention_layernorm"], c["rms_norm_eps"])
            g = deq[p + "mlp.gate_proj"] @ h2
            u = deq[p + "mlp.up_proj"] @ h2
            x = x + deq[p + "mlp.down_proj"] @ (g / (1 + np.exp(-g)) * u)
        logits = deq["model.embed_tokens"] @ rmsnorm(x, deq["model.norm"], c["rms_norm_eps"])
        all_logits.append([float(v) for v in logits])
    (out_dir / "reference.json").write_text(json.dumps({"tokens": tokens, "logits": all_logits}))
    print("model fixture written:", out_dir)


def make_tokenizer(out_dir: Path):
    from tokenizers import Tokenizer, Regex, decoders, models, normalizers, pre_tokenizers, trainers
    corpus = [
        "Jarvis at your service, sir. Opening the 3D project space now.",
        "Make three red cubes and clone the second one twice.",
        "The quick brown fox jumps over the lazy dog. It's 14:30 in London.",
        "자비스, 3D 공간 열어줘. 빨간 큐브 세 개 만들어 주십시오.",
        "안녕하십니까? 오늘 서울 날씨는 맑습니다. 음악을 재생하겠습니다.",
        "I'll play Bohemian Rhapsody by Queen; you'd like it, wouldn't you?",
    ] * 40
    tok = Tokenizer(models.BPE())
    tok.normalizer = normalizers.NFC()
    tok.pre_tokenizer = pre_tokenizers.Sequence([
        pre_tokenizers.Split(Regex(QWEN_PATTERN), behavior="isolated"),
        pre_tokenizers.ByteLevel(add_prefix_space=False, use_regex=False),
    ])
    tok.decoder = decoders.ByteLevel()
    trainer = trainers.BpeTrainer(vocab_size=700, special_tokens=["<|endoftext|>", "<|im_start|>", "<|im_end|>"],
                                  initial_alphabet=pre_tokenizers.ByteLevel.alphabet(), show_progress=False)
    tok.train_from_iterator(corpus, trainer)
    tok.save(str(out_dir / "tiny_tokenizer.json"))
    samples = [
        "Jarvis at your service, sir.",
        "<|im_start|>user\nOpen the 3D space, please!<|im_end|>\n<|im_start|>assistant\n",
        "자비스, 빨간 큐브 세 개 만들어 주십시오.",
        "It's 14:30 — they're    here\n\nnew lines  and spaces ",
        "Ünïcödé café naïve 😀 mixed 한글 text 123456",
    ]
    ref = [{"text": s, "ids": tok.encode(s).ids} for s in samples]
    (out_dir / "tiny_tokenizer_reference.json").write_text(json.dumps(ref, ensure_ascii=False, indent=1))
    print("tokenizer fixture written")


if __name__ == "__main__":
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "Tests/JarvisCoreTests/Fixtures")
    make_model(out / "tiny_qwen3")
    make_tokenizer(out)
