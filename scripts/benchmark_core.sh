#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build/core-benchmark
mkdir -p "$OUT"
{ swift --version; uname -srm; } > "$OUT/toolchain.txt"
sources=(WorldCore/Sources/WorldCore/*.swift)
for mode in O Osize; do
  swiftc -swift-version 5 "-$mode" -whole-module-optimization "${sources[@]}" Benchmarks/CompactCore/main.swift -o "$OUT/bench-$mode"
  "$OUT/bench-$mode" | tee "$OUT/$mode.log"
done
size "$OUT/bench-O" "$OUT/bench-Osize" | tee "$OUT/code-sections.txt"
python3 - <<'PY'
from pathlib import Path
import json, platform, re
root=Path('build/core-benchmark')
result={'host':platform.platform(),'scope':'Host kernel benchmark, not iPhone or whole-app performance','modes':{}}
for mode in ('O','Osize'):
    text=(root/(mode+'.log')).read_text()
    match=re.search(r'compact=([\d.]+) reference=([\d.]+) ratio=([\d.]+)',text)
    assert match and 'EQUIVALENCE_PASS' in text
    result['modes'][mode]={'median_ns_compact':float(match[1]),'median_ns_reference':float(match[2]),'ratio':float(match[3]),'harness_file_bytes':(root/('bench-'+mode)).stat().st_size}
(root/'results.json').write_text(json.dumps(result,indent=2))
PY
# Preserve actual compiler output for inspection instead of claiming hand-written ASM gains.
swiftc -swift-version 5 -Osize -whole-module-optimization -emit-assembly "${sources[@]}" Benchmarks/CompactCore/main.swift -o "$OUT/CompactCore-Osize.s"
gzip -f -9 "$OUT/CompactCore-Osize.s"
