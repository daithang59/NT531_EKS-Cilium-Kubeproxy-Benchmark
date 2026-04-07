import re, json
from pathlib import Path

content = Path('results/mode=A_kube-proxy/scenario=S1/load=L1/run=R1_2026-04-07T09-03-59+07-00/bench.log').read_text(errors='replace')

# Find "Run ended" JSON
m = re.search(r'"Run ended"', content)
if m:
    print('Found "Run ended" at:', m.start())
    start = m.start()
    depth = 0
    in_str = False
    esc = False
    json_end = 0
    for i in range(start, len(content)):
        c = content[i]
        if esc:
            esc = False
            continue
        if c == '\\':
            esc = True
            continue
        if c == '"' and not esc:
            in_str = not in_str
            continue
        if in_str:
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                json_end = i+1
                break

    json_text = content[start:json_end]
    print('JSON length:', len(json_text))
    data = json.loads(json_text)
    print('Keys:', sorted(data.keys()))
    h = data.get('Histogram') or data.get('h', {})
    print('Histogram type:', type(h).__name__)
    if isinstance(h, dict):
        print('Histogram keys:', sorted(h.keys()))
        p = h.get('Percentile', {})
        print('Percentile keys:', sorted(p.keys()) if isinstance(p, dict) else p)
        print('Max:', h.get('Max'))
        print('Avg:', h.get('Avg'))
    print()
    print('qps:', data.get('qps'))
    print('calls:', data.get('calls'))
    print('elapsed:', data.get('elapsed'))
    print('RequestedQPS:', data.get('RequestedQPS'))
    print('RunInfo:', data.get('RunInfo'))
