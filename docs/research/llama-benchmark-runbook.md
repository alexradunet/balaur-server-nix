# llama.cpp ROCm physical benchmark runbook

Status: waiting for physical execution

This runbook records the only allowed path from the safe issue-10 implementation
to a production model decision. It does not contain model URLs, publisher
hashes, benchmark results, API keys, or a default selection. Do not run it from
an agent session. It reads physical GPU/thermal/kernel state and sustains a
heavy workload.

## Candidate allowlist

Benchmark exactly these four rows, in this order:

1. `Qwen3-30B-A3B-Instruct-2507-Q5_K_M`
2. `Mistral-Small-3.2-24B-Q6_K`
3. `Qwen2.5-Coder-32B-Q5_K_M`
4. `gpt-oss-20b-MXFP4`

Qwen3.6 is explicitly excluded because the confirmed spec records unresolved
recurrent-cache/correctness risk for this workload. The harness rejects unknown
candidate identifiers, extra rows, wrong quantization markers, paths outside
`/srv/models`, symlinks, and SHA-256 mismatches.

## Inputs prepared by a human

1. Obtain each file from a primary model publisher source outside this
   repository. Verify publisher identity and licensing. This document does not
   guess download locations or hashes.
2. Place human-provided GGUF files under `/srv/models/benchmarks/`. Do not put a
   model on md root, in the Nix store, or in a user home.
3. Compute SHA-256 locally after transfer. Create
   `/srv/models/benchmarks/manifest.tsv`, root-owned and mode 0600, with exactly
   three tab-separated fields in the allowlist order:

   ```text
   <candidate ID><TAB>/srv/models/benchmarks/<publisher filename>.gguf<TAB><64 lowercase hex SHA-256>
   ```

   There must be no header or extra row. This runtime manifest is not a tracked
   production selection.
4. Before any run, choose and record one reviewed hardware thermal limit, one
   minimum prompt-token/s floor, and one minimum generation-token/s floor.
   Apply identical floors to all candidates. These are human benchmark policy,
   not guessed repository defaults.
5. Generate a short, wholly synthetic Jellyfin clip (color bars, tone, and no
   personal content) and configure a temporary transcode playback. Confirm the
   client reports transcoding rather than direct play. Remove the fixture after
   all runs.

Validate the inventory without loading a model:

```sh
scripts/llama-benchmark.sh validate /srv/models/benchmarks/manifest.tsv
```

## Reproducible tools

Build the pinned package and run the harness from a shell containing its small
measurement dependencies:

```sh
nix build --no-link path:$PWD#llama-cpp-rocm
nix shell \
  path:$PWD#llama-cpp-rocm \
  nixpkgs#bash nixpkgs#coreutils nixpkgs#curl nixpkgs#gawk \
  nixpkgs#gnugrep nixpkgs#jq nixpkgs#procps nixpkgs#lm_sensors nixpkgs#systemd
```

Do not deploy or enable the production unit for benchmarking. The harness runs
an isolated loopback router with a documented non-production synthetic key,
`--offline`, a private temporary cache, the production context/KV/offload/slot
shape, and logging disabled. It never downloads a model.

## One candidate run

1. Record host revision, kernel, nixpkgs revision, llama version, ROCm package
   versions, firmware/BIOS revision, room temperature, and the preselected
   limits in a separate operator note. Do not record secrets or personal data.
2. Ensure no other inference workload is active. Jellyfin is the sole allowed
   competing GPU workload.
3. Start the synthetic Jellyfin transcode and verify it plays without a stall.
4. Run from the repository root. Use a new timestamped output directory every
   time:

   ```sh
   export THERMAL_LIMIT_C='<reviewed limit>'
   export MIN_PROMPT_TPS='<predeclared floor>'
   export MIN_GENERATION_TPS='<predeclared floor>'
   export JELLYFIN_CONTENTION_CONFIRMED=1
   scripts/llama-benchmark.sh run \
     /srv/models/benchmarks/manifest.tsv \
     Qwen3-30B-A3B-Instruct-2507-Q5_K_M \
     .scratch/llama-benchmark-results/<UTC timestamp>-qwen3-30b
   ```

5. Repeat with each of the other three exact IDs. Never reuse an output
   directory. Do not lower the soak below 7200 seconds or lazy cycles below 10
   for an approval run.
6. During every run, watch the synthetic playback for startup delay, buffering,
   dropped transcode sessions, audio/video corruption, and UI unresponsiveness.
   If any occurs, stop the run and mark Jellyfin contention failed even if the
   script exits successfully.
7. Stop immediately on thermal throttling, kernel GPU fault/reset, sustained
   swap-in/out, host instability, or less than 10 GiB available host memory.

The fixed request fixtures contain only synthetic arithmetic, tokens, a fake
widget tool, and an imaginary clockwork orchard. Request/response bodies remain
in a private temporary directory and are deleted on exit. Artifacts retain only
booleans, timings, counters, temperatures, kernel messages, service state, and
model SHA-256—not prompt bodies or generated prose.

## What is collected

The harness records or checks:

- exact-answer and arithmetic correctness;
- one structured `lookup_widget(id=17)` tool call;
- repeated-prompt cache behavior;
- prompt and generation token throughput;
- router/model-process RSS and host `MemAvailable` samples;
- at least 10 GiB steady-state host headroom;
- swap-in/swap-out deltas and swap-storm rejection;
- kernel amdgpu reset, timeout, ring-stall, and GPU-fault evidence;
- sensor maximum against the human-reviewed limit and any observed throttling;
- at least a two-hour sustained generation soak;
- at least ten router `/models/unload` and `/models/load` cycles;
- active Jellyfin state while the human checks synthetic transcode contention.

The unload/load cycles test router process teardown and reload. Separately,
production's b9190 `--sleep-idle-seconds 1800` source semantics release model and
KV resources while retaining a sleeping child process; after a candidate first
passes, perform one additional 31-minute idle observation and record `/models`
status plus before/after process and host memory. A candidate fails if it does
not enter `sleeping` around 1800 seconds or resources do not materially return.
Do not generate traffic from `/metrics`; in router mode it requires a model and
may affect interpretation, while `/health`, `/props`, and `/models` are source-
documented as idle-exempt.

## Pass/fail gates

A candidate passes only when every item is true:

- exact-answer, arithmetic, and tool-call structure checks pass;
- the second fixed cache request is no slower than 110% of the first and
  produces the expected answer;
- prompt and generation throughput meet the floors recorded before any run;
- minimum host `MemAvailable` is at least 10 GiB throughout steady state;
- `pswpin` and `pswpout` do not increase; any sustained swap activity is a fail;
- no amdgpu reset, timeout, ring stall, GPU fault, kernel panic, model crash, or
  failed lazy load/unload cycle occurs;
- temperature remains at or below the reviewed limit with no throttling;
- the full two-hour soak and ten lazy cycles complete;
- the extra 30-minute idle test reaches sleeping state and releases model/KV
  resources;
- the synthetic Jellyfin transcode has no startup failure, buffering, dropped
  session, corruption, or loss of household UI responsiveness.

A missing sensor reading, inaccessible kernel log, missing throughput field, or
unverified Jellyfin playback is **not** a pass. Investigate and rerun rather than
waiving evidence. A ROCm package/VM build proves none of these physical gates.

## Review and selection

Outputs live only under the gitignored
`.scratch/llama-benchmark-results/`. Review each `summary.json`, memory series,
temperatures, kernel log, operator note, and idle observation. Redact unexpected
identifiers before sharing.

The harness never edits Nix, creates owner credentials, writes a production
preset, or ranks/selects a candidate. After all four have comparable evidence,
a human may select one passing candidate (or none), record the rationale, copy
a reviewed soft ceiling—measured peak inference memory plus margin while still
preserving at least 10 GiB host headroom—into `memoryHighBytes`, and author one
single-model preset under `/srv/models`. If no candidate passes, keep the service
disabled and return issue 10 to design; do not silently relax the gates.
