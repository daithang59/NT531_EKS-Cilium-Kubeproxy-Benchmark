import json, sys
path = sys.argv[1]
try:
    with open(path, encoding='utf-8', errors='replace') as fh:
        raw = fh.read()
    lines = [l for l in raw.splitlines() if not l.strip().startswith('HTTP/')]
    text = '\n'.join(lines)
    first, last = text.find('{'), text.rfind('}')
    if first < 0 or last <= first:
        print("[ERROR] No JSON found")
        sys.exit(0)
    d = json.loads(text[first:last+1])
    dur = d.get('ActualDuration', 0)
    qps = d.get('RequestedQPS', 0)
    dur_s = dur / 1e9
    dh = d.get('DurationHistogram', {})
    avg_s = dh.get('Avg', 0)
    avg_ms = avg_s * 1000
    pct_list = dh.get('Percentiles', [])
    pct_map = {p['Percentile']: p['Value'] for p in pct_list}
    codes = d.get('RetCodes', {})
    total = sum(codes.values())
    ok200 = codes.get('200', 0)
    print(f"All done {total} calls ({dur_s:.1f}s) qps={qps}")
    print(f"  avg_ms={avg_ms:.3f}")
    for p in [50, 75, 90, 99, 99.9]:
        v = pct_map.get(p, 0)
        if v:
            print(f"  p{p}={v*1000:.3f}ms")
    print(f"  Code 200: {ok200} ({round(100*ok200/total,1) if total else 0}%)")
    if total - ok200 > 0:
        print(f"  Errors: {total - ok200}")
    print("SUCCESS!")
except Exception as e:
    print(f"[ERROR] {e}")
