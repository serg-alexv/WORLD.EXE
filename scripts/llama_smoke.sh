#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
MODEL_DIR="${RUNNER_TEMP:-/tmp}/world-qwen-23749fef"
export WORLD_MODEL_DIR="$MODEL_DIR"
python3 - <<'PY'
import hashlib,json,os,urllib.request
from pathlib import Path
m=json.loads(Path('Dependencies/models.json').read_text())['defaultModel']
r=Path(os.environ['WORLD_MODEL_DIR']);r.mkdir(parents=True,exist_ok=True);p=r/m['filename']
if not p.exists():
 tmp=p.with_suffix('.partial')
 try:
  with urllib.request.urlopen(m['url'],timeout=60) as src,tmp.open('wb') as dst:
   total=0
   while chunk:=src.read(1024*1024):
    total+=len(chunk)
    if total>m['bytes']:raise RuntimeError('Model exceeds pinned byte size')
    dst.write(chunk)
  tmp.replace(p)
 finally: tmp.unlink(missing_ok=True)
assert p.stat().st_size==m['bytes']
with p.open('rb') as f:assert hashlib.file_digest(f,'sha256').hexdigest()==m['sha256']
print('Verified pinned Qwen3 GGUF; weights excluded from build artifacts.')
PY
swift build --package-path LocalLlama -c release --product LlamaSmoke 2>&1 | tee build/llama-smoke-build.log
BIN=$(swift build --package-path LocalLlama -c release --show-bin-path)
sandbox-exec -p '(version 1) (allow default) (deny network*)' \
  "$BIN/LlamaSmoke" "$MODEL_DIR/Qwen3-0.6B-Q8_0.gguf" 2>&1 | tee build/llama-native-smoke.log
grep -q 'LLAMA_NATIVE_SMOKE_PASS' build/llama-native-smoke.log
