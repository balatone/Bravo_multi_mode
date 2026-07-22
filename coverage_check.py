import re

targets = [
    "FlyWithLua/Modules/bravo++/util.lua",
    "FlyWithLua/Modules/bravo++/log.lua",
    "FlyWithLua/Modules/bravo++/state.lua",
    "FlyWithLua/Modules/bravo++/debug.lua"
]

def calculate_coverage(stats_file, target_files):
    results = {}
    with open(stats_file, 'r') as f:
        for line in f:
            parts = line.split(':', 1)
            if len(parts) < 2:
                continue

            rest = parts[1].strip()
            sub_parts = rest.split()
            if not sub_parts:
                continue

            path = sub_parts[0]
            data_str = " ".join(sub_parts[1:])

            if path in target_files:
                try:
                    data = list(map(int, data_str.split()))
                    print(f"DEBUG: {path} has {len(data)} numbers")
                    total_hits = 0
                    total_misses = 0
                    for i in range(0, len(data), 2):
                        if i + 1 < len(data):
                            total_hits += data[i]
                            total_misses += data[i+1]

                    if total_hits + total_misses > 0:
                        coverage = (total_hits / (total_hits + total_misses)) * 100
                    else:
                        coverage = 0.0
                    results[path] = coverage
                except ValueError:
                    print(f"DEBUG: Error parsing data for {path}")
    return results

if __name__ == "__main__":
    res = calculate_coverage('luacov.stats.out', targets)
    for path, cov in res.items():
        print(f"{path}: {cov:.2f}%")
