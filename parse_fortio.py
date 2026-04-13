import json, sys
path = sys.argv[1]
try:
    with open(path, encoding='utf-8', errors='replace') as fh:
        raw = fh.read()

    # Fortio curl outputs multiple JSON objects to stdout:
    #   1. Fortio internal log ({"ts":..., "level":"info", ...})
    #   2. The actual REST result ({"RunType": "HTTP", ...})
    # We need to find the one with "RunType" as top-level key.
    # Use brace-depth scanning so we don't break on internal { } in strings.
    depth = 0; start = -1; found = None
    for i, c in enumerate(raw):
        if c == 123:  # {
            if depth == 0: start = i
            depth += 1
        elif c == 125:  # }
            depth -= 1
            if depth == 0 and start >= 0:
                try:
                    obj_str = raw[start:i+1].decode('utf-8', errors='replace')
                    obj = json.loads(obj_str)
                    # Check if this is the Fortio result (has RunType top-level key)
                    if 'RunType' in obj:
                        found = obj
                        break
                except: pass
                start = -1

    if not found:
        print("[ERROR] No valid Fortio result JSON found in REST response")
        sys.exit(0)

    d = found
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
