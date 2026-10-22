#!/usr/bin/env python3
"""Verify emitted BibTeX entries against bibliographic ground truth.

    python eval/litsearch/verify.py [--systems baseline,elba] [--logdir logs/litsearch]

For every entry in every refs.bib: find the cited paper by title in
Crossref, DBLP, OpenAlex, or arXiv. An entry is a hallucination when the
paper cannot be found (fabricated) or when its authors, year, or DOI
disagree with the located record (wrong fields).

Results: per-entry rows in <logdir>/verify/entries.csv and per-system
aggregates in <logdir>/verify/summary.json. Lookups are cached on disk, so
reruns are cheap.
"""

from __future__ import annotations

import argparse
import csv
import difflib
import html
import json
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MAILTO = "ttzhou@ucsd.edu"
TITLE_MATCH = 0.85

_last_call: dict[str, float] = {}


def polite_get(url: str, source: str, delay: float, cache: dict) -> str | None:
    """A response body, or None when the request keeps failing.

    Failures are retried and never cached, so a rate limited source does
    not turn into a permanent verdict.
    """
    if cache.get(url) is not None:
        return cache[url]
    req = urllib.request.Request(url, headers={
        "User-Agent": f"litsearch-eval (mailto:{MAILTO})"})
    for attempt in range(3):
        wait = _last_call.get(source, 0) + delay - time.time()
        if wait > 0:
            time.sleep(wait)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                body = resp.read().decode("utf-8", "replace")
            _last_call[source] = time.time()
            cache[url] = body
            return body
        except urllib.error.HTTPError as e:
            _last_call[source] = time.time()
            if e.code == 404:
                cache[url] = ""
                return ""
            _last_call[source] += 5 * (attempt + 1)
        except Exception:
            _last_call[source] = time.time() + 5 * (attempt + 1)
    return None


# ---------------------------------------------------------------- bib parsing

def parse_bib(text: str) -> list[dict]:
    entries = []
    for m in re.finditer(r"@(\w+)\s*\{", text):
        kind = m.group(1).lower()
        if kind in ("comment", "preamble", "string"):
            continue
        body, end = balanced(text, m.end() - 1)
        if body is None:
            continue
        key, _, fields_src = body.partition(",")
        fields = parse_fields(fields_src)
        entries.append({"kind": kind, "key": key.strip(), **fields})
    return entries


def balanced(text: str, start: int) -> tuple[str | None, int]:
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:i], i
    return None, len(text)


def parse_fields(src: str) -> dict:
    fields = {}
    i = 0
    while i < len(src):
        m = re.compile(r"\s*(\w[\w-]*)\s*=\s*").match(src, i)
        if not m:
            i += 1
            continue
        name = m.group(1).lower()
        i = m.end()
        if i < len(src) and src[i] == "{":
            value, i = balanced(src, i)
            i += 1
        elif i < len(src) and src[i] == '"':
            end = src.find('"', i + 1)
            value, i = src[i + 1:end], end + 1
        else:
            m2 = re.compile(r"[^,]*").match(src, i)
            value, i = m2.group(0), m2.end()
        if value is not None:
            fields[name] = re.sub(r"\s+", " ", value).strip()
    return fields


LATEX_LETTERS = [("\\ss", "ss"), ("\\ae", "ae"), ("\\oe", "oe"), ("\\AE", "ae"),
                 ("\\OE", "oe"), ("\\o", "o"), ("\\O", "o"), ("\\l", "l"),
                 ("\\L", "l"), ("\\i", "i"), ("\\j", "j")]

PLAIN_LETTERS = str.maketrans({"ø": "o", "Ø": "o", "ł": "l", "Ł": "l", "æ": "ae",
                               "Æ": "ae", "œ": "oe", "Œ": "oe", "ß": "ss",
                               "đ": "d", "Đ": "d", "þ": "th", "Þ": "th", "ı": "i"})


def norm_title(title: str) -> str:
    title = re.sub(r"<[^>]+>", "", title)
    for cmd, repl in LATEX_LETTERS:
        title = title.replace(cmd, repl)
    # single letter LaTeX commands are accents and vanish, longer ones separate
    title = re.sub(r"\\([a-zA-Z])(?![a-zA-Z])", "", title)
    title = re.sub(r"\\[a-zA-Z]+", " ", title)
    title = re.sub(r"\\.", "", title)
    title = title.replace("{", "").replace("}", "")
    title = unicodedata.normalize("NFKD", title.translate(PLAIN_LETTERS))
    title = "".join(c for c in title if not unicodedata.combining(c))
    title = re.sub(r"[^a-z0-9 ]", " ", title.lower())
    return re.sub(r"\s+", " ", title).strip()


def titles_match(a: str, b: str) -> bool:
    na, nb = norm_title(a), norm_title(b)
    if not na or not nb:
        return False
    if na in nb or nb in na:
        return True
    # registry titles sometimes carry markup whitespace inside words
    ca, cb = na.replace(" ", ""), nb.replace(" ", "")
    if min(len(ca), len(cb)) >= 8 and (ca in cb or cb in ca):
        return True
    seq = difflib.SequenceMatcher(None, na, nb).ratio()
    ta, tb = set(na.split()), set(nb.split())
    jac = len(ta & tb) / max(1, len(ta | tb))
    return max(seq, jac) >= TITLE_MATCH


def name_tokens(person: str) -> list[str]:
    """Plausible family name tokens for one person.

    BibTeX renders names as "Family, Given", "Given Family", and sometimes
    "Family Given", so without a comma both edge tokens are candidates.
    """
    person = html.unescape(person).strip().replace("{", "").replace("}", "")
    if not person:
        return []
    if "," in person:
        return [t for t in norm_title(person.split(",")[0]).split() if t]
    words = person.split()
    tokens = set(norm_title(words[-1]).split()) | set(norm_title(words[0]).split())
    return [t for t in tokens if t]


def family_names(author_field: str) -> list[list[str]]:
    people = re.split(r"\s+and\s+", author_field)
    return [tokens for person in people if (tokens := name_tokens(person))]


# ------------------------------------------------------------------- sources

def crossref_candidates(title: str, cache: dict) -> list[dict] | None:
    url = ("https://api.crossref.org/works?rows=5&mailto=" + MAILTO
           + "&select=DOI,title,author,issued"
           + "&query.bibliographic=" + urllib.parse.quote(title))
    body = polite_get(url, "crossref", 0.5, cache)
    if not body:
        return None
    out = []
    for item in json.loads(body).get("message", {}).get("items", []):
        if not item.get("title"):
            continue
        out.append({
            "source": "crossref",
            "title": item["title"][0],
            "authors": [a.get("family", "") for a in item.get("author", [])],
            "year": (item.get("issued", {}).get("date-parts") or [[None]])[0][0],
            "doi": item.get("DOI", "")})
    return out


def dblp_candidates(title: str, cache: dict) -> list[dict] | None:
    url = ("https://dblp.uni-trier.de/search/publ/api?format=json&h=10&q="
           + urllib.parse.quote(norm_title(title)))
    body = polite_get(url, "dblp", 1.5, cache)
    if not body:
        return None
    try:
        hits = json.loads(body)["result"]["hits"].get("hit", [])
    except (json.JSONDecodeError, KeyError):
        return None
    out = []
    for hit in hits:
        info = hit.get("info", {})
        authors = info.get("authors", {}).get("author", [])
        if isinstance(authors, dict):
            authors = [authors]
        # dblp appends numeric disambiguators to author names
        out.append({
            "source": "dblp",
            "title": info.get("title", ""),
            "authors": [next((w for w in reversed(a.get("text", "").split())
                              if not w.isdigit()), "")
                        for a in authors],
            "year": int(info["year"]) if info.get("year") else None,
            "doi": (info.get("doi") or "")})
    return out


def openalex_candidates(title: str, cache: dict) -> list[dict] | None:
    url = ("https://api.openalex.org/works?per_page=5&mailto=" + MAILTO
           + "&search=" + urllib.parse.quote(norm_title(title)))
    body = polite_get(url, "openalex", 0.4, cache)
    if not body:
        return None
    try:
        results = json.loads(body).get("results", [])
    except json.JSONDecodeError:
        return None
    out = []
    for work in results:
        out.append({
            "source": "openalex",
            "title": work.get("title") or "",
            "authors": [(a.get("author", {}).get("display_name") or "").split()[-1]
                        for a in work.get("authorships", [])
                        if a.get("author", {}).get("display_name")],
            "year": work.get("publication_year"),
            "doi": (work.get("doi") or "").removeprefix("https://doi.org/")})
    return out


def arxiv_candidates(title: str, cache: dict) -> list[dict] | None:
    query = urllib.parse.quote(f'ti:"{norm_title(title)}"')
    url = f"http://export.arxiv.org/api/query?search_query={query}&max_results=5"
    body = polite_get(url, "arxiv", 3.0, cache)
    if not body:
        return None
    out = []
    for entry in re.findall(r"<entry>(.*?)</entry>", body, re.S):
        t = re.search(r"<title>(.*?)</title>", entry, re.S)
        published = re.search(r"<published>(\d{4})", entry)
        names = re.findall(r"<name>(.*?)</name>", entry)
        if not t:
            continue
        out.append({
            "source": "arxiv",
            "title": re.sub(r"\s+", " ", t.group(1)).strip(),
            "authors": [n.split()[-1] for n in names],
            "year": int(published.group(1)) if published else None,
            "doi": ""})
    return out


def doi_lookup(doi: str, cache: dict):
    """The registered record for a DOI, None when definitively absent,
    and "failed" when the registries could not be reached."""
    doi = doi.strip().removeprefix("https://doi.org/").removeprefix("doi:")
    url = ("https://api.crossref.org/works/" + urllib.parse.quote(doi)
           + "?mailto=" + MAILTO)
    body = polite_get(url, "crossref", 0.5, cache)
    if body:
        item = json.loads(body).get("message", {})
        return {
            "source": "doi",
            "title": (item.get("title") or [""])[0],
            "authors": [a.get("family", "") for a in item.get("author", [])],
            "year": (item.get("issued", {}).get("date-parts") or [[None]])[0][0],
            "doi": doi}
    crossref_absent = body == ""
    url = "https://api.datacite.org/dois/" + urllib.parse.quote(doi)
    body = polite_get(url, "datacite", 0.5, cache)
    if body:
        try:
            attrs = json.loads(body)["data"]["attributes"]
            titles = attrs.get("titles") or [{}]
            creators = attrs.get("creators") or []
            year = attrs.get("publicationYear")
            return {
                "source": "doi",
                "title": titles[0].get("title", ""),
                "authors": [c.get("familyName") or (c.get("name") or "").split(",")[0]
                            for c in creators],
                "year": int(year) if year else None,
                "doi": doi}
        except (json.JSONDecodeError, KeyError):
            return "failed"
    if crossref_absent and body == "":
        return None
    return "failed"


# ----------------------------------------------------------------- verdicts

def field_errors(entry: dict, match: dict) -> list[str]:
    """Disagreements between the entry and one located record."""
    errors = []
    claimed = family_names(entry.get("author", ""))
    # registries sometimes put the whole name in the family field
    true_families = {word for f in match["authors"] if f
                     for word in norm_title(html.unescape(f)).split()}
    if claimed and true_families:
        matched = [person for person in claimed if set(person) & true_families]
        first_ok = bool(set(claimed[0]) & true_families)
        if not first_ok and len(matched) < max(1, len(claimed) // 2):
            errors.append("authors")
    year = re.search(r"\d{4}", entry.get("year", "") or "")
    if year and match["year"] and abs(int(year.group(0)) - match["year"]) > 1:
        errors.append("year")
    return errors


def check_entry(entry: dict, cache: dict) -> dict:
    """An entry is clean when some real record agrees with what it claims.

    Papers appear in several registries (preprint and published versions
    with different years or author lists), so a field only counts as wrong
    when no matching record is consistent with it.
    """
    title = entry.get("title", "")
    row = {"title": title, "verdict": "ok", "errors": [], "matched_source": ""}
    if not title:
        row["verdict"] = "unparseable"
        return row

    doi_errors = []
    doi_record = None
    doi = entry.get("doi", "")
    if doi:
        registered = doi_lookup(doi, cache)
        if registered is None:
            doi_errors.append("doi_unregistered")
        elif registered == "failed":
            pass
        elif registered["title"] and not titles_match(title, registered["title"]):
            doi_errors.append("doi_wrong_paper")
        else:
            doi_record = registered

    best: list[str] | None = None
    any_failed = False
    # the claimed DOI resolving to a consistent record is the strongest match
    if doi_record is not None:
        best = field_errors(entry, doi_record)
        row["matched_source"] = "doi"
        if best == []:
            row["errors"] = doi_errors
            if doi_errors:
                row["verdict"] = "wrong_fields"
            return row
    for lookup in (crossref_candidates, dblp_candidates,
                   openalex_candidates, arxiv_candidates):
        candidates = lookup(title, cache)
        if candidates is None:
            any_failed = True
            continue
        for cand in candidates:
            if not titles_match(title, cand["title"]):
                continue
            errors = field_errors(entry, cand)
            if best is None or len(errors) < len(best):
                best = errors
                row["matched_source"] = cand["source"]
            if not errors:
                break
        if best == []:
            break

    if best is None:
        # a paper is only fabricated when every registry answered and none matched
        row["verdict"] = "unverified" if any_failed else "fabricated"
        row["errors"] = doi_errors
        return row
    row["errors"] = best + doi_errors
    if row["errors"]:
        row["verdict"] = "wrong_fields"
    return row


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--logdir", default=str(REPO_ROOT / "logs" / "litsearch"))
    ap.add_argument("--systems", default="baseline,elba")
    args = ap.parse_args()

    logdir = Path(args.logdir)
    verify_dir = logdir / "verify"
    verify_dir.mkdir(parents=True, exist_ok=True)
    cache_path = verify_dir / "cache.json"
    cache = json.loads(cache_path.read_text()) if cache_path.exists() else {}

    rows = []
    try:
        for system in args.systems.split(","):
            bib_files = sorted((logdir / system).glob("*/refs.bib"))
            for bib in bib_files:
                slug = bib.parent.name
                entries = parse_bib(bib.read_text())
                print(f"[{system}/{slug}] {len(entries)} entries", flush=True)
                for entry in entries:
                    row = check_entry(entry, cache)
                    row |= {"system": system, "task": slug, "key": entry.get("key", "")}
                    rows.append(row)
    finally:
        cache_path.write_text(json.dumps(cache))

    with (verify_dir / "entries.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "system", "task", "key", "title", "verdict", "errors", "matched_source"],
            extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(row | {"errors": "+".join(row["errors"])})

    summary = {}
    for system in args.systems.split(","):
        mine = [r for r in rows if r["system"] == system]
        summary[system] = {
            "entries": len(mine),
            "tasks_with_bib": len({r["task"] for r in mine}),
            "ok": sum(r["verdict"] == "ok" for r in mine),
            "fabricated": sum(r["verdict"] == "fabricated" for r in mine),
            "wrong_fields": sum(r["verdict"] == "wrong_fields" for r in mine),
            "unverified": sum(r["verdict"] == "unverified" for r in mine),
            "unparseable": sum(r["verdict"] == "unparseable" for r in mine),
        }
    (verify_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
