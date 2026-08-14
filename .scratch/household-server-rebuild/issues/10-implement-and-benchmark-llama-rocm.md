# Implement and benchmark lazy llama.cpp on ROCm

Status: needs-info
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

The safe pre-benchmark implementation was completed without selecting a model,
generating credentials, deploying, or making a physical ROCm claim. Production
remains disabled.

Implementation evidence:

- `packages/llama-cpp-rocm.nix` uses pinned nixpkgs llama.cpp 9190 with HIP,
  only `gfx1150`, and ROCm 7.2.3. The closure check verifies derivation flags,
  versions, `libggml-hip.so`, and the executable version.
- Pinned b9190 does not have an HIP UMA CMake switch. Its HIP build docs require
  runtime `GGML_CUDA_ENABLE_UNIFIED_MEMORY=1`; the service sets that exact value
  and does not guess `HSA_XNACK` or an HSA architecture override.
- b9190 `--sleep-idle-seconds` is sufficient: its server context calls
  `destroy()` on sleep, resetting the llama model/context owner and freeing the
  batch; upstream documents model and KV-memory unload plus lazy reload. The
  service therefore uses native `--sleep-idle-seconds 1800`, not a duplicate
  controller.
- `modules/llama.nix` defines one loopback-only, offline router with one loaded
  model maximum, one slot, 32768 context, F16 K/V, full GPU layers, prompt cache,
  metrics, disabled logs/UI, owner multi-key file authentication, required
  `/srv/models` mount, Radeon device access, and CPU/IO weight 100 below
  Jellyfin's 200. It has a benchmark-derived soft `MemoryHigh`, no
  `MemoryLow` protection competing with Jellyfin, and no guessed hard
  `MemoryMax`.
- The default has no unit, user, listener, route, firewall opening, or missing
  file read. Readiness requires one validated single-model preset below
  `/srv/models`, distinct Alex/Andreea owner-policy runtime key files, and a
  measured memory target.
- Raw TCP 8081 stays off LAN and Caddy. Issue 12 must provide stable owner
  container addresses and one source-restricted private forwarder per owner;
  no broad bridge listener or owner bind is defined early.
- The checked-in runbook/harness allows exactly the four specified candidates,
  rejects Qwen3.6/unknown files/hash mismatches, uses synthetic prompts, writes
  redacted measurements only under gitignored scratch, enforces correctness,
  tool/cache/throughput, memory/headroom, swap, kernel/GPU, thermal, soak, lazy
  cycle, and Jellyfin-contention gates, and never edits production selection.
- Evaluation and disposable VM tests cover disabled default, exact CLI and UMA
  environment, no raw ingress, missing-mount failure, distinct owner keys,
  compressed fake idle-sleep behavior, package flags/closure, and Jellyfin
  priority. The VM explicitly makes no ROCm runtime claim.

Exact remaining human gates:

1. On the physical host, obtain all four human-provided candidate GGUFs from
   verified primary publishers, record local SHA-256 values, predeclare thermal
   and throughput limits, and run the complete two-hour-plus benchmark and
   31-minute idle-release observation for every candidate. Record Jellyfin
   synthetic-transcode contention, at least 10 GiB host headroom, no swap
   activity/storm, no GPU reset/kernel errors, and reviewed temperatures. Do not
   choose a model that misses any gate.
2. Human-review the comparative evidence and explicitly select one passing
   candidate (or none). Author exactly one local `/srv/models` router preset and
   derive `memoryHighBytes` from measured peak inference memory plus a reviewed
   margin while preserving at least 10 GiB host headroom.
   The harness must not perform either action.
3. Complete issue 07 age/sops onboarding. Generate separate real Alex and
   Andreea API keys outside Nix and expose them through their exact owner-policy
   runtime roots. No plaintext/test key may be reused or committed.
4. Complete issue 12 stable private container addressing, per-owner
   source-restricted loopback forwarding, one-owner-only key mounts, firewall
   rules, and cross-owner isolation tests. A broad host bridge listener and raw
   Caddy route remain forbidden.
5. Rebuild and validate the ready closure and physical ROCm offload only after
   gates 1-4. Until then `readiness.ready` must remain false and issue 17 cannot
   onboard owner chat workflows.
