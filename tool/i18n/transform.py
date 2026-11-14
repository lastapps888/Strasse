#!/usr/bin/env python3
"""Branche la traduction dans le code existant (idempotent).

1. Les fichiers qui construisent un `Text(...)` importent le `Text` de Strasse (traduit à l'affichage) au lieu de celui de Flutter.
2. Les textes passés en paramètres de type String (infobulles, libellés de champs...) sont enveloppés par tr().
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import dartlex  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PARAMS = ["tooltip", "labelText", "hintText", "helperText", "errorText", "prefixText", "suffixText", "counterText", "semanticsLabel"]
MATERIAL = re.compile(r"import 'package:flutter/material\.dart'(?P<rest>[^;]*);")
report = []


def fix_imports(path, s):
    masked = dartlex.mask_strings_and_comments(s)
    if not re.search(r"(?<![\w.])Text(\.rich)?\(", masked) and not re.search(r"(?<![\w.])Text\b(?!Style|Field|Span|Align|Editing|Input|Overflow|Direction|Baseline|Painter|Theme|Button|Selection|Scaler|Height|Width|Capitalization|Decoration|Heading)", masked):
        return s
    if path.endswith(os.path.join("i18n", "tr_text.dart")):
        return s
    m = MATERIAL.search(s)
    if not m:
        report.append(f"{path}: utilise Text sans importer material.dart")
        return s
    rest = m.group("rest").strip()
    if "tr_text.dart" not in s:
        if not rest:
            new = "import 'package:flutter/material.dart' hide Text;"
        elif rest.startswith("hide"):
            new = "import 'package:flutter/material.dart' " + rest + (", Text;" if "Text" not in re.split(r"[ ,]+", rest) else ";")
        else:
            report.append(f"{path}: import material avec « {rest} » : à vérifier à la main")
            return s
        s = s[:m.start()] + new + "\nimport 'package:strasse/core/i18n/tr_text.dart';" + s[m.end():]
    return s


def expr_end(masked, i):
    """Fin (exclue) de l'expression commençant en i : première virgule ou parenthèse fermante de profondeur 0."""
    depth = 0
    while i < len(masked):
        c = masked[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                return i
            depth -= 1
        elif c == "," and depth == 0:
            return i
        i += 1
    return -1


def enclosing_consts(masked, pos):
    """Positions des `const` qui rendent constante l'expression contenant pos (jusqu'au début de l'instruction)."""
    found = []
    depth = 0
    i = pos - 1
    while i >= 0:
        c = masked[i]
        if c in ")]}":
            depth += 1
        elif c in "([{":
            if depth == 0:
                j = i - 1
                while j >= 0 and masked[j].isspace():
                    j -= 1
                # saute <Types> et Nom.nom
                if j >= 0 and masked[j] == ">":
                    d = 1
                    j -= 1
                    while j >= 0 and d:
                        d += (masked[j] == ">") - (masked[j] == "<")
                        j -= 1
                    while j >= 0 and masked[j].isspace():
                        j -= 1
                k = j
                while k >= 0 and (masked[k].isalnum() or masked[k] in "_."):
                    k -= 1
                head = k + 1
                if masked[head:j + 1] == "const":
                    found.append(head)
                k2 = k
                while k2 >= 0 and masked[k2].isspace():
                    k2 -= 1
                if k2 >= 4 and masked[k2 - 4:k2 + 1] == "const" and (k2 == 4 or not (masked[k2 - 5].isalnum() or masked[k2 - 5] == "_")):
                    found.append(k2 - 4)
                if c == "{" and j >= 0 and masked[j] == ")":
                    break  # corps de fonction : début d'instruction
            else:
                depth -= 1
        elif c == ";" and depth == 0:
            break
        i -= 1
    return found


def wrap_params(path, s):
    changed = True
    guard = 0
    while changed and guard < 500:
        guard += 1
        changed = False
        masked = dartlex.mask_strings_and_comments(s)
        for m in re.finditer(r"\b(%s)\s*:" % "|".join(PARAMS), masked):
            start = m.end()
            while start < len(s) and s[start].isspace():
                start += 1
            end = expr_end(masked, start)
            if end < 0:
                continue
            expr = s[start:end].rstrip()
            if not expr or expr.startswith(("tr(", "trn(")):
                continue
            end = start + len(expr)
            lit = re.fullmatch(r"('(?:[^'\\\n]|\\.)*'|\"(?:[^\"\\\n]|\\.)*\")", expr)
            wrapped = ("tr(" if lit else "trn(") + expr + ")"
            consts = enclosing_consts(masked, m.start())
            # déclaration constante englobante : impossible à corriger automatiquement
            head = masked[max(0, masked.rfind(";", 0, m.start()) + 1):m.start()]
            if re.search(r"\bconst\b", head) and not consts:
                report.append(f"{path}:{dartlex.line_of(s, m.start())}: {m.group(1)} dans une déclaration const")
            edits = [(start, end, wrapped)] + [(c, c + 6, "") for c in consts]
            for a, b, rep in sorted(edits, reverse=True):
                s = s[:a] + rep + s[b:]
            changed = True
            break
    return s


def ensure_tr_import(path, s):
    if not re.search(r"\btrn?\(", dartlex.mask_strings_and_comments(s)):
        return s
    if "core/core.dart" in s or "i18n/translator.dart" in s:
        return s
    imp = "import 'package:strasse/core/i18n/translator.dart';\n"
    m = list(re.finditer(r"^import [^\n]*\n", s, re.M))
    if not m:
        return imp + s
    # ordre alphabétique approximatif : avant le premier import 'package:strasse/...' supérieur
    for mm in m:
        if mm.group(0).startswith("import 'package:strasse/") and mm.group(0) > imp:
            return s[:mm.start()] + imp + s[mm.start():]
    return s[:m[-1].end()] + imp + s[m[-1].end():]


def refix_consts():
    """Retire les `const` encore présents autour d'un tr()/trn() déjà posé."""
    n = 0
    for base, _d, files in os.walk(os.path.join(ROOT, "lib")):
        for f in files:
            if not f.endswith(".dart") or "/core/i18n" in base:
                continue
            p = os.path.join(base, f)
            s = open(p, encoding="utf-8").read()
            for _ in range(200):
                masked = dartlex.mask_strings_and_comments(s)
                hit = None
                for mm in re.finditer(r"(?<![\w.])trn?\(", masked):
                    c = enclosing_consts(masked, mm.start())
                    if c:
                        hit = c
                        break
                if not hit:
                    break
                for c in sorted(set(hit), reverse=True):
                    s = s[:c] + s[c + 6:]
                n += 1
            open(p, "w", encoding="utf-8").write(s)
    return n


def main():
    n = 0
    for base, _d, files in os.walk(os.path.join(ROOT, "lib")):
        for f in files:
            if not f.endswith(".dart"):
                continue
            p = os.path.join(base, f)
            rel = os.path.relpath(p, ROOT)
            if "/core/i18n/" in p:
                continue
            s0 = open(p, encoding="utf-8").read()
            s = fix_imports(rel, s0)
            s = wrap_params(rel, s)
            s = ensure_tr_import(rel, s)
            if s != s0:
                open(p, "w", encoding="utf-8").write(s)
                n += 1
    print(f"{n} fichiers modifiés, {refix_consts()} const retirés")
    for r in report:
        print("À VÉRIFIER :", r)


if __name__ == "__main__":
    main()
