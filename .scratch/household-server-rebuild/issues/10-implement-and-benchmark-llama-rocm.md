# Implement and benchmark lazy llama.cpp on ROCm

Status: ready-for-agent
Blocked by: 03, 06, 07, 08, 09

## Objective

Provide one shared, lazy, private inference backend and select a model only after hardware validation.

## Work

- Pin/build llama.cpp for ROCm `gfx1150` with verified unified-memory support.
- Use router mode, autoload, one slot, 32K context, F16 KV, and 30-minute idle unload.
- Keep the raw API private; issue separate owner proxy credentials and disable prompt-body logging.
- Store models only in the disposable models dataset.
- Benchmark the four candidates listed in the spec for correctness, tools, cache behavior, memory, thermals, soak stability, lazy cycles, and Jellyfin contention.

## Acceptance criteria

- Package and host closure build reproducibly.
- No production model is selected before passing the benchmark gate.
- At least 10 GiB steady-state host memory headroom is targeted and swap storms/GPU resets are rejected.
- Qwen3.6 is not selected.
- Benchmark artifacts contain no personal prompts or secrets.

## Comments
