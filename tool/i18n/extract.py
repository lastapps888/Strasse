#!/usr/bin/env python3
"""Extrait de lib/ les textes français à traduire vers tool/i18n/source_fr.json.

Les chaînes avec valeurs insérées sont converties en modèles : « Marche {0} jusqu'à {1} ».
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import dartlex  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SKIP_DIRS = {"i18n"}  # lib/core/i18n : aucun texte d'interface
NOISE = {"Accept", "Authorization", "Cancel", "City", "Content-Type", "User-Agent", "Bearer"}
SQL = re.compile(r"^\s*(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|PRAGMA|WITH|CASE|FROM)\b", re.I)


def is_ui_text(t):
    if re.fullmatch(r"[A-Z0-9_]+", t) or t in NOISE or "|" in t or re.fullmatch(r"[a-zà-ÿ]{2,}", t) and len(set(t)) > 5 and not t.isalpha():
        return False
    if re.fullmatch(r"[a-zà-ÿœæ]+", t) and len(t) > 12:
        return False  # suite de lettres sans espace (alphabet, identifiant)
    if not re.search(r"[A-Za-zÀ-ÿЀ-ӿ؀-ۿ]", t):
        return False
    if len(t.strip()) < 2:
        return False
    if re.search(r"https?://|^package:|^assets/|^dart:|\.(png|jpg|json|svg|dart)$", t):
        return False
    if SQL.match(t) or re.search(r"[<>]\w+[^<>]*>|\bfunction\b|=>|&&|\|\|", t):
        return False
    stripped = re.sub(r"\{\d+\}", "", t).strip()
    if not stripped:
        return False
    if " " not in stripped and "\n" not in stripped:
        # un seul mot : texte d'interface s'il commence par une majuscule ou contient une lettre accentuée
        if re.search(r"[0-9_./:#@\\\\\[\]()=\-]", stripped) and not re.match(r"^[A-ZÀ-Ý][\wÀ-ÿ'’]*[.!?…:]?$", stripped):
            return False
        return bool(re.match(r"^[A-ZÀ-Ý]", stripped) or re.search(r"[À-ÿ]", stripped))
    # plusieurs mots : écarte ce qui ressemble à du code ou à des identifiants
    if re.fullmatch(r"[\w .,:;/#@\-]*", stripped) and re.fullmatch(r"[a-z0-9_.:/\- ]+", stripped):
        return False  # tout en minuscules sans accent ni ponctuation de phrase : probablement technique
    return True


def main():
    found = {}
    for base, dirs, files in os.walk(os.path.join(ROOT, "lib")):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in files:
            if not f.endswith(".dart"):
                continue
            p = os.path.join(base, f)
            s = open(p, encoding="utf-8").read()
            lines = s.split("\n")
            lits = dartlex.scan(s)
            for g in dartlex.group_adjacent(s, lits):
                ln = dartlex.line_of(s, g["start"])
                line = lines[ln - 1].lstrip()
                if line.startswith(("import ", "export ", "part ")):
                    continue
                t = g["template"]
                if is_ui_text(t):
                    found.setdefault(t, []).append(os.path.relpath(p, ROOT) + ":" + str(ln))
    keys = sorted(found)
    out = os.path.join(ROOT, "tool", "i18n", "source_fr.json")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump({k: len(found[k]) for k in keys}, fh, ensure_ascii=False, indent=1)
    print(f"{len(keys)} textes uniques ({sum(1 for k in keys if '{0}' in k)} avec valeurs insérées) → {os.path.relpath(out, ROOT)}")


if __name__ == "__main__":
    main()
