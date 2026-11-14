#!/usr/bin/env python3
"""Vérifie les traductions partielles : JSON valide, mêmes clés que la source, marqueurs {n} conservés."""
import json, os, re, sys
R = os.path.join(os.path.dirname(__file__), "..", "..")
langs = "en de ru ar zh es it pt pl nl ja".split()
missing = {}
for l in langs:
    for i in (1, 2, 3):
        src = json.load(open(f"{R}/tool/i18n/chunks/source_{i}.json"))
        p = f"{R}/assets/i18n/_parts/{l}_{i}.json"
        ok = False
        if os.path.exists(p):
            try:
                d = json.load(open(p))
                ph = lambda t: sorted(re.findall(r"\{\d+\}", t))
                bad = [k for k in src if k not in d or not isinstance(d[k], str) or ph(k) != ph(d[k])]
                ok = not bad and set(d) == set(src)
                if bad:
                    print(l, i, "anomalies:", len(bad), bad[:2])
            except Exception as e:
                print(l, i, "illisible", e)
        if not ok:
            missing.setdefault(l, []).append(i)
print("à (re)faire :", missing)
