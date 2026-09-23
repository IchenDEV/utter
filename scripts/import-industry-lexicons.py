#!/usr/bin/env python3
"""Rebuild the four common-term packs from pinned, MIT-licensed THUOCL data."""
import argparse
import hashlib
import json
import re
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
REVISION = "a30ce79d895d01ab5132a5c74c29703ff7efb4cc"
BASE = f"https://raw.githubusercontent.com/thunlp/THUOCL/{REVISION}/"
FILES = {
    "technology": ("THUOCL_IT.txt", "e8cd42c9f5559735fa3bfb91515cbe051f991efd4a803038a1d5c0da85af3526"),
    "medical": ("THUOCL_medical.txt", "a01f39f1677af0b6a620bbc68bf293e8e436f06248b74adb625cd61d9ad7bbcd"),
    "legal": ("THUOCL_law.txt", "8ef1a5f41052ac95dedde88b167c5031a43b3e0211bf128b6125736cc76ef7b2"),
    "finance": ("THUOCL_caijing.txt", "68e63d2009e59c6f388eeaa789d19b6a681657de3e8e56cc3479b21cd8548542"),
}
LICENSE_SHA = "db4b8cca414db4cf487b933d07a0514f77caf44f9f3d392f2bc9d7ba0d511c58"
LIMIT = 2000
CATEGORY = "thuocl-common"


def read_verified(path, digest, cache):
    data = (cache / Path(path).name).read_bytes() if cache else urllib.request.urlopen(BASE + path, timeout=60).read()
    if hashlib.sha256(data).hexdigest() != digest:
        raise ValueError(f"Source checksum mismatch: {path}")
    return data


def common_terms(data, reserved):
    ranked = []
    for line in data.decode("utf-8-sig").splitlines():
        term, frequency = line.rsplit("\t", 1)
        if not frequency.strip().isdecimal():
            continue
        term = term.strip()
        if 2 <= len(term) <= 40 and not any(c.isspace() or not c.isprintable() for c in term) and not term.isdecimal():
            ranked.append((int(frequency.strip()), term))
    result = []
    seen = set(reserved)
    for _, term in sorted(ranked, key=lambda item: (-item[0], item[1])):
        if term.casefold() in seen:
            continue
        seen.add(term.casefold())
        result.append(term)
        if len(result) == LIMIT:
            break
    if len(result) != LIMIT:
        raise ValueError("Not enough eligible source terms")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, help="Use already downloaded originals; checksums still required")
    args = parser.parse_args()
    resource = ROOT / "Sources/Resources"
    target = resource / "IndustryLexicons.json"
    document = json.loads(target.read_text())
    license_data = read_verified("LICENSE", LICENSE_SHA, args.source_dir)
    sources = [s for s in document["sources"] if not s["id"].startswith("thuocl-")]
    for pack in document["packs"]:
        industry = pack["id"]
        filename, checksum = FILES[industry]
        seed = [t for t in pack["terms"] if t["category"] != CATEGORY]
        reserved = {value.casefold() for t in seed for value in [t["term"], *t["aliases"], *t["corrections"]]}
        terms = common_terms(read_verified("data/" + filename, checksum, args.source_dir), reserved)
        source_id = "thuocl-" + industry
        sources.append({"id": source_id, "title": "THUOCL " + industry + " (MIT, 2016/2017 corpus)",
                        "url": BASE + "data/" + filename, "usage": "redistributed-terms", "redistribution": "MIT"})
        pack["sourceIDs"] = [s for s in pack["sourceIDs"] if not s.startswith("thuocl-")] + [source_id]
        pack["version"] = "2026.09.24-v2"
        pack["reviewStatus"] = "curated-and-imported-needs-domain-review"
        pack["terms"] = seed + [{"id": source_id + "-" + hashlib.sha256(t.encode()).hexdigest()[:16],
                                 "term": t, "aliases": [], "corrections": [], "category": CATEGORY} for t in terms]
        print(f"{industry}: {len(seed)} curated + {len(terms)} imported = {len(pack['terms'])}")
    document.update(version="2026.09.24-v2", updatedAt="2026-09-24", sources=sources,
                    rights="Utter-curated seed terms plus THUOCL common terms, Copyright (c) 2018 THUNLP, MIT License. See THUOCL-LICENSE.txt. Imported terms have no automatic correction mappings.")
    # One record per line keeps the generated data compact and reviewable.
    output = json.dumps(document, ensure_ascii=False, indent=2)
    output = re.sub(r'\{\n\s+"id": "[^"\n]+",\n\s+"term":.*?\n\s+\}',
                    lambda m: json.dumps(json.loads(m.group()), ensure_ascii=False), output, flags=re.S)
    target.write_text(output + "\n")
    (resource / "THUOCL-LICENSE.txt").write_bytes(license_data)


if __name__ == "__main__":
    main()
