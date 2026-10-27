"""Builds the artifact page for a Godot web export.
The wasm and pck are gzipped (artifact files must stay under 15MB) and
inflated in the browser with DecompressionStream before Godot sees them."""
import gzip, json, os, re, shutil, sys
src = sys.argv[1] if len(sys.argv) > 1 else '/home/claude/build/web'
out = sys.argv[2] if len(sys.argv) > 2 else '/home/claude/build/site'
os.makedirs(out, exist_ok=True)
html = open(os.path.join(src, 'index.html')).read()
cfg = json.loads(re.search(r'const GODOT_CONFIG = (\{.*?\});', html).group(1))
cfg['ensureCrossOriginIsolationHeaders'] = False
cfg.pop('serviceWorker', None)
for f in ['index.js', 'index.audio.worklet.js', 'index.audio.position.worklet.js']:
    if os.path.exists(os.path.join(src, f)): shutil.copy(os.path.join(src, f), os.path.join(out, f))
for f in ['index.wasm', 'index.pck']:
    data = open(os.path.join(src, f), 'rb').read()
    gz = os.path.join(out, f.replace('.', '-') + '.gz.wasm')
    with gzip.open(gz, 'wb', compresslevel=9) as g: g.write(data)
    print(f, len(data), '->', os.path.getsize(gz))
page = open(os.path.join(os.path.dirname(__file__), 'shell.html')).read().replace('/*GODOT_CONFIG*/{}', json.dumps(cfg))
open(os.path.join(out, 'index.html'), 'w').write(page)
print('shell ok')
