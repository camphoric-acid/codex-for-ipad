#!/usr/bin/env bash
set -euo pipefail

if (( $# < 1 || $# > 2 )); then
  echo "usage: $0 BINARY [REPORT_OUTPUT]" >&2
  exit 2
fi

binary="$1"
report_output="${2:-}"
objdump_bin="${OBJDUMP:-objdump}"

test -f "$binary"
command -v file >/dev/null
command -v "$objdump_bin" >/dev/null

file_description="$(file -b "$binary")"
case "$file_description" in
  *"ELF 32-bit"*"Intel 80386"* | *"ELF 32-bit"*"Intel i386"*) ;;
  *)
    echo "error: expected an ELF32 x86 binary, got: $file_description" >&2
    exit 1
    ;;
esac

matches_file="$(mktemp)"
trap 'rm -f "$matches_file"' EXIT

# iSH's x86 interpreter does not implement SSE/SSE2. Most such instructions
# expose an XMM operand; the remaining list covers state, fence, cache, and
# MMX-form instructions introduced with SSE that can appear without one.
forbidden_pattern='\bxmm[0-9]+\b|\b(fxsave|fxrstor|ldmxcsr|stmxcsr|prefetchnta|prefetcht0|prefetcht1|prefetcht2|prefetchw|lfence|mfence|sfence|clflush|movnti|movntq|maskmovq|pavgb|pavgw|pextrw|pinsrw|pmaxsw|pmaxub|pminsw|pminub|pmovmskb|pmulhuw|psadbw|pshufw|rcpps|rsqrtps)\b'

set +e
LC_ALL=C "$objdump_bin" -d -M intel "$binary" \
  | grep -E -i -m 20 "$forbidden_pattern" > "$matches_file"
pipeline_status=("${PIPESTATUS[@]}")
set -e
objdump_status="${pipeline_status[0]}"
grep_status="${pipeline_status[1]}"
matches="$(<"$matches_file")"

if (( grep_status == 0 )); then
  echo "error: binary contains instructions or registers outside the iSH CPU baseline:" >&2
  printf '%s\n' "$matches" >&2
  exit 1
fi
if (( grep_status != 1 )); then
  echo "error: failed to inspect disassembly" >&2
  exit "$grep_status"
fi
if (( objdump_status != 0 )); then
  echo "error: disassembler exited with status $objdump_status" >&2
  exit "$objdump_status"
fi

report="Binary: $file_description
Disassembler: $($objdump_bin --version | head -n 1)
Forbidden SSE/XMM matches: 0"
if [[ -n "$report_output" ]]; then
  mkdir -p "$(dirname -- "$report_output")"
  printf '%s\n' "$report" | tee "$report_output"
else
  printf '%s\n' "$report"
fi
