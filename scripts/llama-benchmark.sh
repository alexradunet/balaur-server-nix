#!/usr/bin/env bash
set -euo pipefail

readonly RESULT_ROOT=".scratch/llama-benchmark-results"
readonly HEADROOM_KIB=10485760
readonly REQUIRED_SOAK_SECONDS=7200
readonly REQUIRED_LAZY_CYCLES=10
readonly BENCHMARK_KEY="BALAUR_LOCAL_SYNTHETIC_BENCHMARK_KEY"
readonly CANDIDATES=(
  "Qwen3-30B-A3B-Instruct-2507-Q5_K_M"
  "Mistral-Small-3.2-24B-Q6_K"
  "Qwen2.5-Coder-32B-Q5_K_M"
  "gpt-oss-20b-MXFP4"
)

usage() {
  cat <<'EOF'
Usage:
  scripts/llama-benchmark.sh validate MANIFEST.tsv
  scripts/llama-benchmark.sh run MANIFEST.tsv CANDIDATE OUTPUT_DIR

MANIFEST.tsv must contain exactly four tab-separated rows, in the documented
order: candidate ID, absolute /srv/models GGUF path, and recorded SHA-256.

For run, set all of:
  THERMAL_LIMIT_C       reviewed physical hardware limit
  MIN_PROMPT_TPS        benchmark approval floor
  MIN_GENERATION_TPS    benchmark approval floor
  JELLYFIN_CONTENTION_CONFIRMED=1 after starting the synthetic contention test
Optional: LLAMA_SERVER, PORT (18081), SOAK_SECONDS (7200), LAZY_CYCLES (10).
EOF
}

known_candidate() {
  local wanted=$1 candidate
  for candidate in "${CANDIDATES[@]}"; do
    [[ $candidate == "$wanted" ]] && return 0
  done
  return 1
}

validate_filename() {
  local candidate=$1 name=${2##*/}
  case "$candidate" in
    Qwen3-30B-A3B-Instruct-2507-Q5_K_M)
      [[ $name =~ [Qq]wen3[-_.].*30[Bb].*[Aa]3[Bb].*[Ii]nstruct.*2507.*Q5_K_M.*\.gguf$ ]]
      ;;
    Mistral-Small-3.2-24B-Q6_K)
      [[ $name =~ [Mm]istral[-_.].*[Ss]mall.*3[._-]2.*24[Bb].*Q6_K.*\.gguf$ ]]
      ;;
    Qwen2.5-Coder-32B-Q5_K_M)
      [[ $name =~ [Qq]wen2[._-]5.*[Cc]oder.*32[Bb].*Q5_K_M.*\.gguf$ ]]
      ;;
    gpt-oss-20b-MXFP4)
      [[ $name =~ [Gg][Pp][Tt][-_].*[Oo][Ss][Ss].*20[Bb].*MXFP4.*\.gguf$ ]]
      ;;
    *) return 1 ;;
  esac
}

validate_manifest() {
  local manifest=$1 line=0 candidate path expected_hash actual_hash
  [[ $manifest == /srv/models/* ]] || {
    echo "manifest must be below /srv/models" >&2
    return 1
  }
  [[ -f $manifest ]] || {
    echo "manifest is not a regular file: $manifest" >&2
    return 1
  }

  while IFS=$'\t' read -r candidate path expected_hash extra; do
    ((line += 1))
    [[ -z ${extra:-} && $line -le ${#CANDIDATES[@]} ]] || return 1
    [[ $candidate == "${CANDIDATES[$((line - 1))]}" ]] || {
      echo "unknown or out-of-order candidate on manifest row $line" >&2
      return 1
    }
    [[ $candidate != *Qwen3.6* && $path != *Qwen3.6* && $path != *qwen3.6* ]] || return 1
    [[ $path == /srv/models/* && -f $path && ! -L $path ]] || return 1
    [[ $(realpath -e "$path") == /srv/models/* ]] || return 1
    validate_filename "$candidate" "$path" || {
      echo "filename does not identify the exact candidate/quantization: $path" >&2
      return 1
    }
    [[ $expected_hash =~ ^[0-9a-f]{64}$ ]] || return 1
    actual_hash=$(sha256sum "$path")
    actual_hash=${actual_hash%% *}
    [[ $actual_hash == "$expected_hash" ]] || {
      echo "SHA-256 mismatch for $candidate" >&2
      return 1
    }
  done < "$manifest"
  [[ $line -eq ${#CANDIDATES[@]} ]] || return 1
}

manifest_value() {
  local manifest=$1 wanted=$2 field=$3
  awk -F '\t' -v wanted="$wanted" -v field="$field" '$1 == wanted { print $field }' "$manifest"
}

json_request() {
  local url=$1 body=$2 output=$3
  curl --fail --silent --show-error \
    -H "Authorization: Bearer $BENCHMARK_KEY" \
    -H 'Content-Type: application/json' \
    --data-binary "@$body" "$url" > "$output"
}

metric_value() {
  local key=$1 file=$2
  jq -r "$key // 0" "$file"
}

sample_memory() {
  local router_pid=$1 output=$2 rss mem_available
  rss=$(ps -eo pid=,ppid=,rss= | awk -v pid="$router_pid" '$1 == pid || $2 == pid { total += $3 } END { print total + 0 }')
  mem_available=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
  printf '%(%s)T\t%s\t%s\n' -1 "$rss" "$mem_available" >> "$output"
}

sample_temperature() {
  local output=$1
  printf '\n--- %(%FT%T%z)T ---\n' -1 >> "$output"
  sensors >> "$output" 2>&1 || true
}

wait_model_status() {
  local port=$1 candidate=$2 expected=$3 attempt status
  for attempt in $(seq 1 300); do
    status=$(curl --fail --silent -H "Authorization: Bearer $BENCHMARK_KEY" \
      "http://127.0.0.1:$port/models" \
      | jq -r --arg model "$candidate" '.data[] | select(.id == $model) | .status.value')
    [[ $status == "$expected" ]] && return 0
    sleep 1
  done
  echo "model did not reach status $expected after $attempt checks" >&2
  return 1
}

write_requests() {
  local directory=$1 candidate=$2
  jq -n --arg model "$candidate" '{model:$model,messages:[{role:"user",content:"Return exactly BALAUR_SYNTHETIC_OK and nothing else."}],temperature:0,max_tokens:32}' > "$directory/correctness.json"
  jq -n --arg model "$candidate" '{model:$model,messages:[{role:"user",content:"A synthetic crate has 6 rows of 7 blue tokens. Reply with only the total number."}],temperature:0,max_tokens:32}' > "$directory/arithmetic.json"
  jq -n --arg model "$candidate" '{model:$model,messages:[{role:"user",content:"Use the provided function to look up synthetic widget 17."}],tools:[{type:"function",function:{name:"lookup_widget",description:"Look up a synthetic widget",parameters:{type:"object",properties:{id:{type:"integer"}},required:["id"]}}}],tool_choice:"auto",temperature:0,max_tokens:128}' > "$directory/tool.json"
  jq -n --arg model "$candidate" '{model:$model,messages:[{role:"user",content:"Cache fixture alpha beta gamma delta. Reply with only CACHE_OK."}],temperature:0,max_tokens:32,cache_prompt:true}' > "$directory/cache.json"
  jq -n --arg model "$candidate" '{model:$model,messages:[{role:"user",content:"Write twelve numbered, one-sentence facts about an imaginary clockwork orchard. Use only synthetic details."}],temperature:0,max_tokens:384}' > "$directory/throughput.json"
}

run_benchmark() {
  local manifest=$1 candidate=$2 output=$3
  local server=${LLAMA_SERVER:-llama-server} port=${PORT:-18081}
  local soak_seconds=${SOAK_SECONDS:-$REQUIRED_SOAK_SECONDS}
  local lazy_cycles=${LAZY_CYCLES:-$REQUIRED_LAZY_CYCLES}
  local model_path model_hash temp_dir server_pid start_iso
  local swap_in_before swap_out_before swap_in_after swap_out_after
  local min_headroom max_temp gpu_errors correctness arithmetic tool cache cache_answer pass=true
  local prompt_tps generation_tps first_cache_ms second_cache_ms

  known_candidate "$candidate" || {
    echo "refusing unknown candidate: $candidate" >&2
    return 1
  }
  [[ $candidate != *Qwen3.6* ]] || return 1
  [[ $output == "$RESULT_ROOT"/* && ! -e $output ]] || {
    echo "output must be a new directory below $RESULT_ROOT" >&2
    return 1
  }
  : "${THERMAL_LIMIT_C:?set reviewed THERMAL_LIMIT_C}"
  : "${MIN_PROMPT_TPS:?set MIN_PROMPT_TPS}"
  : "${MIN_GENERATION_TPS:?set MIN_GENERATION_TPS}"
  [[ ${JELLYFIN_CONTENTION_CONFIRMED:-0} == 1 ]] || {
    echo "start and verify the runbook's synthetic Jellyfin contention workload first" >&2
    return 1
  }
  [[ $THERMAL_LIMIT_C =~ ^[0-9]+([.][0-9]+)?$ ]]
  [[ $MIN_PROMPT_TPS =~ ^[0-9]+([.][0-9]+)?$ ]]
  [[ $MIN_GENERATION_TPS =~ ^[0-9]+([.][0-9]+)?$ ]]

  mkdir -p "$output"
  temp_dir=$(mktemp -d)
  trap 'kill "${server_pid:-}" 2>/dev/null || true; wait "${server_pid:-}" 2>/dev/null || true; rm -rf "${temp_dir:-}"' EXIT
  model_path=$(manifest_value "$manifest" "$candidate" 2)
  model_hash=$(manifest_value "$manifest" "$candidate" 3)
  write_requests "$temp_dir" "$candidate"
  printf '%s\n' "$BENCHMARK_KEY" > "$temp_dir/api-keys"
  cat > "$temp_dir/router.ini" <<EOF
version = 1
[$candidate]
model = $model_path
EOF

  start_iso=$(date --iso-8601=seconds)
  swap_in_before=$(awk '$1 == "pswpin" {print $2}' /proc/vmstat)
  swap_out_before=$(awk '$1 == "pswpout" {print $2}' /proc/vmstat)
  GGML_CUDA_ENABLE_UNIFIED_MEMORY=1 LLAMA_OFFLINE=1 LLAMA_CACHE="$temp_dir/empty-cache" \
    "$server" --host 127.0.0.1 --port "$port" --offline \
    --models-preset "$temp_dir/router.ini" --models-max 1 --models-autoload \
    --parallel 1 --ctx-size 32768 --cache-type-k f16 --cache-type-v f16 \
    --n-gpu-layers all --fit off --cache-prompt --metrics --no-slots --no-ui \
    --log-disable --sleep-idle-seconds 1800 --api-key-file "$temp_dir/api-keys" \
    > /dev/null 2>&1 &
  server_pid=$!
  for _ in $(seq 1 120); do
    curl --fail --silent "http://127.0.0.1:$port/health" > /dev/null 2>&1 && break
    sleep 1
  done
  kill -0 "$server_pid"

  printf 'epoch\tprocess_tree_rss_kib\thost_mem_available_kib\n' > "$output/memory.tsv"
  : > "$output/temperatures.txt"
  sample_memory "$server_pid" "$output/memory.tsv"
  sample_temperature "$output/temperatures.txt"

  json_request "http://127.0.0.1:$port/v1/chat/completions" "$temp_dir/correctness.json" "$temp_dir/correctness-response.json"
  correctness=$(jq -r '[.choices[0].message.content // ""] | any(. == "BALAUR_SYNTHETIC_OK")' "$temp_dir/correctness-response.json")
  json_request "http://127.0.0.1:$port/v1/chat/completions" "$temp_dir/arithmetic.json" "$temp_dir/arithmetic-response.json"
  arithmetic=$(jq -r '(.choices[0].message.content // "") | gsub("[^0-9]"; "") == "42"' "$temp_dir/arithmetic-response.json")
  json_request "http://127.0.0.1:$port/v1/chat/completions" "$temp_dir/tool.json" "$temp_dir/tool-response.json"
  tool=$(jq -r '(.choices[0].message.tool_calls[0].function.name // "") == "lookup_widget" and (((.choices[0].message.tool_calls[0].function.arguments // "{}") | fromjson | .id) == 17)' "$temp_dir/tool-response.json" 2>/dev/null || printf false)

  json_request "http://127.0.0.1:$port/v1/chat/completions" "$temp_dir/cache.json" "$temp_dir/cache-first.json"
  json_request "http://127.0.0.1:$port/v1/chat/completions" "$temp_dir/cache.json" "$temp_dir/cache-second.json"
  first_cache_ms=$(metric_value '.timings.prompt_ms' "$temp_dir/cache-first.json")
  second_cache_ms=$(metric_value '.timings.prompt_ms' "$temp_dir/cache-second.json")
  cache_answer=$(jq -r '(.choices[0].message.content // "") | contains("CACHE_OK")' "$temp_dir/cache-second.json")
  cache=$(awk -v first="$first_cache_ms" -v second="$second_cache_ms" -v answer="$cache_answer" 'BEGIN { print (answer == "true" && first > 0 && second <= first * 1.10) ? "true" : "false" }')

  json_request "http://127.0.0.1:$port/v1/chat/completions" "$temp_dir/throughput.json" "$temp_dir/throughput-response.json"
  prompt_tps=$(metric_value '.timings.prompt_per_second' "$temp_dir/throughput-response.json")
  generation_tps=$(metric_value '.timings.predicted_per_second' "$temp_dir/throughput-response.json")
  sample_memory "$server_pid" "$output/memory.tsv"

  for _ in $(seq 1 "$lazy_cycles"); do
    jq -n --arg model "$candidate" '{model:$model}' > "$temp_dir/model-operation.json"
    json_request "http://127.0.0.1:$port/models/unload" "$temp_dir/model-operation.json" "$temp_dir/model-operation-response.json"
    wait_model_status "$port" "$candidate" unloaded
    sample_memory "$server_pid" "$output/memory.tsv"
    json_request "http://127.0.0.1:$port/models/load" "$temp_dir/model-operation.json" "$temp_dir/model-operation-response.json"
    wait_model_status "$port" "$candidate" loaded
    sample_memory "$server_pid" "$output/memory.tsv"
  done

  end=$((SECONDS + soak_seconds))
  while ((SECONDS < end)); do
    json_request "http://127.0.0.1:$port/v1/chat/completions" "$temp_dir/throughput.json" "$temp_dir/soak-response.json"
    sample_memory "$server_pid" "$output/memory.tsv"
    sample_temperature "$output/temperatures.txt"
  done

  if ! journalctl -k --since "$start_iso" --no-pager > "$output/kernel.log" 2>&1; then
    pass=false
  fi
  [[ -s $output/kernel.log ]] || pass=false
  if grep -Eiq 'permission denied|not permitted|no journal files' "$output/kernel.log"; then
    pass=false
  fi
  systemctl show jellyfin.service -p ActiveState -p CPUWeight -p IOWeight > "$output/jellyfin.txt" 2>&1 || pass=false
  swap_in_after=$(awk '$1 == "pswpin" {print $2}' /proc/vmstat)
  swap_out_after=$(awk '$1 == "pswpout" {print $2}' /proc/vmstat)
  min_headroom=$(awk 'NR > 1 { if (min == 0 || $3 < min) min=$3 } END { print min + 0 }' "$output/memory.tsv")
  # Take only the primary reading after each sensor label. Parenthesized
  # high/critical thresholds often occur later on the same line and must not be
  # mistaken for measured temperatures.
  max_temp=$(awk 'match($0, /^[[:space:]]*[^:]+:[[:space:]]*\+?([0-9]+([.][0-9]+)?)°C/, value) { print value[1] }' "$output/temperatures.txt" | sort -nr | head -1 || true)
  max_temp=${max_temp:-0}
  gpu_errors=$(grep -Eic 'amdgpu.*(reset|timeout|ring.*stalled|gpu fault)|xid|kernel panic' "$output/kernel.log" || true)

  [[ $correctness == true && $arithmetic == true && $tool == true && $cache == true ]] || pass=false
  awk -v value="$prompt_tps" -v floor="$MIN_PROMPT_TPS" 'BEGIN { exit !(value >= floor) }' || pass=false
  awk -v value="$generation_tps" -v floor="$MIN_GENERATION_TPS" 'BEGIN { exit !(value >= floor) }' || pass=false
  ((min_headroom >= HEADROOM_KIB)) || pass=false
  ((swap_in_after == swap_in_before && swap_out_after == swap_out_before)) || pass=false
  ((gpu_errors == 0)) || pass=false
  awk -v value="$max_temp" -v limit="$THERMAL_LIMIT_C" 'BEGIN { exit !(value > 0 && value <= limit) }' || pass=false
  ((soak_seconds >= REQUIRED_SOAK_SECONDS && lazy_cycles >= REQUIRED_LAZY_CYCLES)) || pass=false
  grep -q '^ActiveState=active$' "$output/jellyfin.txt" || pass=false

  jq -n \
    --arg candidate "$candidate" --arg sha256 "$model_hash" --arg status "$pass" \
    --argjson correctness "$correctness" --argjson arithmetic "$arithmetic" \
    --argjson tool_call "$tool" --argjson cache_behavior "$cache" \
    --argjson prompt_tps "$prompt_tps" --argjson generation_tps "$generation_tps" \
    --argjson min_headroom_kib "$min_headroom" --argjson max_temp_c "$max_temp" \
    --argjson swap_in_delta "$((swap_in_after - swap_in_before))" \
    --argjson swap_out_delta "$((swap_out_after - swap_out_before))" \
    --argjson gpu_kernel_errors "$gpu_errors" --argjson soak_seconds "$soak_seconds" \
    --argjson lazy_cycles "$lazy_cycles" \
    '{candidate:$candidate,sha256:$sha256,pass:($status=="true"),correctness:$correctness,arithmetic:$arithmetic,tool_call:$tool_call,cache_behavior:$cache_behavior,prompt_tps:$prompt_tps,generation_tps:$generation_tps,min_host_headroom_kib:$min_headroom_kib,max_temperature_c:$max_temp_c,swap_in_delta:$swap_in_delta,swap_out_delta:$swap_out_delta,gpu_kernel_errors:$gpu_kernel_errors,soak_seconds:$soak_seconds,lazy_cycles:$lazy_cycles,jellyfin_contention_human_confirmed:true,prompt_bodies_recorded:false,production_selection_modified:false}' \
    > "$output/summary.json"
  chmod -R go-rwx "$output"
  [[ $pass == true ]]
}

[[ $# -ge 2 ]] || {
  usage
  exit 2
}
command=$1
manifest=$2
validate_manifest "$manifest"
case "$command" in
  validate) [[ $# -eq 2 ]] ;;
  run)
    [[ $# -eq 4 ]] || { usage; exit 2; }
    run_benchmark "$manifest" "$3" "$4"
    ;;
  *) usage; exit 2 ;;
esac
