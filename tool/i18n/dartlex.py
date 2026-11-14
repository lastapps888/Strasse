"""Analyse minimale de sources Dart : repère les littéraux de chaîne en ignorant les commentaires.

Sert à l'extraction des textes à traduire et aux transformations (tr(), imports). Ce n'est pas un parseur complet :
il suffit à retrouver précisément chaque chaîne, ses valeurs interpolées et ses positions.
"""
import re

IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


class Lit:
    def __init__(self, start, end, template, n_interp, raw):
        self.start, self.end, self.template, self.n_interp, self.raw = start, end, template, n_interp, raw


def _skip_block_comment(s, i):
    j = s.find("*/", i + 2)
    return len(s) if j < 0 else j + 2


def _parse_string(s, i):
    """s[i] est le début d'un littéral (r, quote). Retourne (Lit, index après)."""
    start = i
    raw = False
    if s[i] == "r" and i + 1 < len(s) and s[i + 1] in "'\"":
        raw = True
        i += 1
    q = s[i]
    triple = s.startswith(q * 3, i)
    qlen = 3 if triple else 1
    i += qlen
    out = []
    n = 0
    while i < len(s):
        c = s[i]
        if s.startswith(q * qlen, i):
            i += qlen
            return Lit(start, i, "".join(out), n, raw), i
        if not raw and c == "\\":
            nxt = s[i + 1] if i + 1 < len(s) else ""
            mapping = {"n": "\n", "t": "\t", "r": "\r", "'": "'", '"': '"', "\\": "\\", "$": "$"}
            if nxt in mapping:
                out.append(mapping[nxt])
                i += 2
            elif nxt == "u":
                if s[i + 2] == "{":
                    j = s.index("}", i)
                    out.append(chr(int(s[i + 3:j], 16)))
                    i = j + 1
                else:
                    out.append(chr(int(s[i + 2:i + 6], 16)))
                    i += 6
            elif nxt == "x":
                out.append(chr(int(s[i + 2:i + 4], 16)))
                i += 4
            else:
                out.append(nxt)
                i += 2
            continue
        if not raw and c == "$":
            if i + 1 < len(s) and s[i + 1] == "{":
                depth = 1
                j = i + 2
                while j < len(s) and depth:
                    cj = s[j]
                    if cj in "'\"" or (cj == "r" and j + 1 < len(s) and s[j + 1] in "'\""):
                        _, j = _parse_string(s, j)
                        continue
                    if cj == "{":
                        depth += 1
                    elif cj == "}":
                        depth -= 1
                    j += 1
                out.append("{%d}" % n)
                n += 1
                i = j
                continue
            m = IDENT.match(s, i + 1)
            if m:
                out.append("{%d}" % n)
                n += 1
                i = m.end()
                continue
        out.append(c)
        i += 1
    return Lit(start, len(s), "".join(out), n, raw), len(s)


def scan(s):
    """Liste des littéraux de chaîne du source, dans l'ordre."""
    lits = []
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c == "/" and i + 1 < n and s[i + 1] == "/":
            j = s.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "/" and i + 1 < n and s[i + 1] == "*":
            i = _skip_block_comment(s, i)
            continue
        if c in "'\"" or (c == "r" and i + 1 < n and s[i + 1] in "'\"" and (i == 0 or not (s[i - 1].isalnum() or s[i - 1] == "_"))):
            lit, i = _parse_string(s, i)
            lits.append(lit)
            continue
        i += 1
    return lits


def line_of(s, idx):
    return s.count("\n", 0, idx) + 1


def group_adjacent(s, lits):
    """Regroupe les littéraux adjacents (« 'a' 'b' » = « ab » en Dart) : retourne [(start, end, template, n_interp)]."""
    groups = []
    cur = None
    for lit in lits:
        if cur and not s[cur["end"]:lit.start].strip():
            cur["end"] = lit.end
            # renumérote les valeurs du morceau ajouté
            t = re.sub(r"\{(\d+)\}", lambda m: "{%d}" % (int(m.group(1)) + cur["n"]), lit.template)
            cur["template"] += t
            cur["n"] += lit.n_interp
        else:
            if cur:
                groups.append(cur)
            cur = {"start": lit.start, "end": lit.end, "template": lit.template, "n": lit.n_interp}
    if cur:
        groups.append(cur)
    return groups


def mask_strings_and_comments(s):
    """Copie du source où chaque chaîne et commentaire est remplacé par des espaces (mêmes positions)."""
    out = list(s)
    for lit in scan(s):
        for k in range(lit.start, lit.end):
            if out[k] != "\n":
                out[k] = " "
    i = 0
    n = len(s)
    while i < n:
        if s.startswith("//", i) and out[i] == "/":
            j = s.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = " "
            i = j
        elif s.startswith("/*", i) and out[i] == "/":
            j = _skip_block_comment(s, i)
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
        else:
            i += 1
    return "".join(out)
