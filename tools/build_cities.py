"""Convert GeoNames cities15000.txt into the compact cities.tsv bundled with the app.

Usage: python3 -I tools/build_cities.py path/to/cities15000.txt Avida/cities.tsv
Source: https://download.geonames.org/export/dump/cities15000.zip (CC BY 4.0, GeoNames)
Output columns (tab-separated, no header): name, country code, latitude, longitude, population
Skips neighborhoods (PPLX, e.g. "Times Square") and historical, abandoned or destroyed places,
so labels read as cities.
"""
import sys

SKIP_FEATURE_CODES = {"PPLX", "PPLH", "PPLQ", "PPLW"}

src, dst = sys.argv[1], sys.argv[2]
rows = []
with open(src, encoding="utf-8") as f:
    for line in f:
        cols = line.rstrip("\n").split("\t")
        name, lat, lon, cc, pop = cols[1], float(cols[4]), float(cols[5]), cols[8], cols[14]
        if not name or not cc or cols[7] in SKIP_FEATURE_CODES:
            continue
        rows.append((lat, f"{name}\t{cc}\t{lat:.4f}\t{lon:.4f}\t{int(pop or 0)}"))

# Sorted by latitude so the app can binary search without re-sorting at launch.
rows.sort(key=lambda r: r[0])
with open(dst, "w", encoding="utf-8") as f:
    f.write("\n".join(r[1] for r in rows) + "\n")
print(f"wrote {len(rows)} cities to {dst}")
