"""Build Avida/landmarks.tsv from Wikidata (CC0). Build time only; the app never calls Wikidata.

Usage: python3 -I tools/build_landmarks.py Avida/landmarks.tsv [raw-cache.json]
Optional: AVIDA_CONTACT env var for the User-Agent contact (Wikimedia asks for one).
If a cache path is given, raw query results are saved there and reused on later runs,
so the filters below can be tuned without hitting the endpoint again.

Queries the Wikidata SPARQL endpoint for items with coordinates (P625) inside each bounding box
below, keeps items with at least MIN_SITELINKS Wikipedia/Wikimedia sitelinks and an English label,
and drops:
- settlements and administrative areas (cities, boroughs, neighborhoods...): the city lookup covers those
- destroyed, demolished or defunct places
- items that aren't places at all (languages, companies, events...) but have a headquarters coordinate

Output columns (tab-separated, no header, sorted by latitude):
QID, English label, English description, instance-of type label, latitude, longitude, sitelinks
"""
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

ENDPOINT = "https://query.wikidata.org/sparql"
CONTACT = os.environ.get("AVIDA_CONTACT", "https://github.com/aishwarya4114")
USER_AGENT = f"AvidaLandmarkBuilder/1.0 ({CONTACT}) python-urllib"
MIN_SITELINKS = 5

# name: (south, west, north, east)
BOXES = {
    "NYC metro (incl. Jersey City, Hoboken)": (40.49, -74.27, 40.92, -73.68),
    "Mumbai and Thane": (18.89, 72.77, 19.35, 73.10),
    "Goa": (14.89, 73.67, 15.80, 74.34),
    "Tokyo (mainland)": (35.50, 138.94, 35.90, 139.92),
    "Kyoto (city)": (34.88, 135.55, 35.20, 135.90),
    "Nagano (prefecture)": (35.20, 137.32, 37.03, 138.74),
    "Miyazaki (prefecture)": (31.35, 130.70, 32.85, 131.90),
}

# If an item has several instance-of types, prefer one that marks a large area, since the app
# uses the type to pick a wider match radius. Keep in sync with ClusterConfig.landmarkLargeAreaTypeWords.
LARGE_AREA_WORDS = {"park", "beach", "island", "garden", "forest", "mountain", "lake", "zoo", "cemetery",
                    "airport", "aerodrome"}

# Too big for a point coordinate to mean anything (Honshu's point would label one random spot).
EXCLUDED_QIDS = {"Q13989"}

# Dropped if ANY type matches: places to live, regions, places that no longer exist, events. Whole words.
DROP_ANY_PATTERN = re.compile(
    r"\b(city|cities|town|village|borough|neighbou?rhood|district|county|municipality|ward|"
    r"human settlement|census-designated place|metropolis|megacity|prefecture|u\.s\. state|"
    r"federated state|sovereign state|island country|province|suburb|locality|hamlet|capital|"
    r"taluka|tehsil|chōchō|chōme|ōaza|state of|region|historical country|"
    r"destroyed|demolished|defunct|dissolved|former|"
    r"protest|riot|earthquake|battle|war|incident|disaster|attack|massacre|bombing|explosion|accident|"
    r"flood|typhoon|eruption|conflagration)\b"
)

# Dropped if EVERY type matches: things that aren't places. Whole words.
NON_PLACE_PATTERN = re.compile(
    r"\b(language|company|companies|organi[sz]ation|event|edition|studio|publisher|broadcaster|"
    r"network|team|club|league|agency|corporation|business|enterprise|label|conglomerate|"
    r"newspaper|magazine|competition|tournament|award|project|website|party|union|foundation|"
    r"association|society|brand|television|radio|genre|of the year|rapid transit|transit system|stock exchange)\b"
)

QUERY = """
SELECT ?item ?label ?description ?typeLabel ?coord ?sitelinks WHERE {
  SERVICE wikibase:box {
    ?item wdt:P625 ?coord .
    bd:serviceParam wikibase:cornerSouthWest "Point(%(west)f %(south)f)"^^geo:wktLiteral .
    bd:serviceParam wikibase:cornerNorthEast "Point(%(east)f %(north)f)"^^geo:wktLiteral .
  }
  ?item wikibase:sitelinks ?sitelinks .
  FILTER(?sitelinks >= %(min)d)
  ?item rdfs:label ?label . FILTER(LANG(?label) = "en")
  OPTIONAL { ?item schema:description ?description . FILTER(LANG(?description) = "en") }
  OPTIONAL { ?item wdt:P31 ?type . ?type rdfs:label ?typeLabel . FILTER(LANG(?typeLabel) = "en") }
}
"""


def run_query(box):
    south, west, north, east = box
    query = QUERY % {"south": south, "west": west, "north": north, "east": east, "min": MIN_SITELINKS}
    url = ENDPOINT + "?" + urllib.parse.urlencode({"query": query, "format": "json"})
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/sparql-results+json"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return json.load(response)["results"]["bindings"]
        except Exception as error:  # retry transient endpoint errors (429/5xx/timeouts)
            print(f"  attempt {attempt + 1} failed: {error}", file=sys.stderr)
            time.sleep(10 * (attempt + 1))
    raise SystemExit("Wikidata query failed")


def clean(text):
    return " ".join(text.split())  # no tabs or newlines in the TSV


def parse_point(wkt):
    # "Point(lon lat)"
    lon, lat = wkt[wkt.index("(") + 1 : wkt.index(")")].split()
    return float(lat), float(lon)


def is_non_place(type_label):
    return bool(NON_PLACE_PATTERN.search(type_label.lower()))


def pick_type(types):
    large = sorted(t for t in types if LARGE_AREA_WORDS & set(t.lower().split()))
    places = sorted(t for t in types if not is_non_place(t))
    return (large or places or sorted(types) or [""])[0]


def fetch_all(cache):
    if cache and os.path.exists(cache):
        with open(cache, encoding="utf-8") as f:
            print(f"using cached results from {cache}")
            return json.load(f)
    results = {}
    for name, box in BOXES.items():
        results[name] = run_query(box)
        print(f"{name}: {len(results[name])} rows")
        time.sleep(5)  # be polite to the public endpoint
    if cache:
        with open(cache, "w", encoding="utf-8") as f:
            json.dump(results, f)
    return results


def main(dst, cache=None):
    items = {}
    for rows in fetch_all(cache).values():
        for row in rows:
            qid = row["item"]["value"].rsplit("/", 1)[-1]
            item = items.setdefault(qid, {
                "label": clean(row["label"]["value"]),
                "description": clean(row.get("description", {}).get("value", "")),
                "types": set(),
                "point": parse_point(row["coord"]["value"]),
                "sitelinks": int(row["sitelinks"]["value"]),
            })
            if "typeLabel" in row:
                item["types"].add(clean(row["typeLabel"]["value"]))

    lines = []
    skipped = 0
    for qid, item in items.items():
        types = item["types"]
        if (qid in EXCLUDED_QIDS
                or any(DROP_ANY_PATTERN.search(t.lower()) for t in types)
                or (types and all(map(is_non_place, types)))):
            skipped += 1
            continue
        lat, lon = item["point"]
        fields = [qid, item["label"], item["description"], pick_type(item["types"]),
                  f"{lat:.5f}", f"{lon:.5f}", str(item["sitelinks"])]
        lines.append((lat, "\t".join(fields)))

    lines.sort(key=lambda line: line[0])
    with open(dst, "w", encoding="utf-8") as f:
        f.write("\n".join(line for _, line in lines) + "\n")
    print(f"wrote {len(lines)} landmarks to {dst} (skipped {skipped})")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
