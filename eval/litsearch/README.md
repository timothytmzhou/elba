# Literature search evaluation

Measures citation hallucination on an open ended, multi step agentic task:
compile the bibliography for a survey. This is the benchmark behind the
rebuttal response on realistic agentic tasks.

## Task set

100 topics across systems, security, PL, and ML (`tasks.py`). Each task asks
the agent to find 10 published papers covering three named aspects of the
topic, write one complete BibTeX entry per paper to `refs.bib`, and print a
summary mapping papers to aspects. Covering the aspects requires several
distinct searches, so every task is multi step by construction: the baseline
averaged 5.5 LLM turns and 11.7 web searches per task.

## Systems

Both run Claude Sonnet 5 on Bedrock with the same task text.

- **Baseline (`run_pai.py`)** — a stock `pydantic_ai.Agent` with the
  framework's packaged web search tool
  (`pydantic_ai.common_tools.duckduckgo`) plus a `write_bib_file` function
  tool the task requires. All model settings are framework defaults. The
  model composes the BibTeX text itself from what it read and remembers.
  (Anthropic's server side web search tool is not served on Bedrock, which
  Bedrock confirms with `tool type 'web_search_20260209' is not supported`;
  the framework tool is the standard substitute.)
- **Elba (`run_elba.py`, `examples/bibtex`)** — the agent emits one typed
  Haskell program against the `LitSearch` API: `searchWorks` queries
  Crossref, `fetchBib` downloads a record's BibTeX, and
  `writeBibFile :: FilePath -> [Trusted Bibtex] -> TIO ()` writes it. The
  `Trusted` constructor is private and `fetchBib` is its only producer, so
  the program can select and order entries but no LLM produced byte can
  reach the bibliography. The required type `TIO ()` confines all effects
  to this API.

## Verification (`verify.py`)

Every emitted entry is checked against Crossref, DBLP, OpenAlex, and arXiv:
an entry is **fabricated** when no registry contains a matching title, and
**wrong fields** when no consistent record supports its authors, year, or
DOI (a claimed DOI is resolved and must belong to the cited work). Checks
are conservative: any record agreeing with the entry clears it, registry
outages are retried and excluded rather than miscounted, and the residue of
flags was audited by hand — real works absent from registries (tech
reports, workshop papers without DOIs, web publications) are recorded in
`adjudications.json` and count as correct.

## Results

| system | tasks | entries | fabricated | wrong fields | hallucinated |
|---|---|---|---|---|---|
| baseline (stock pydantic-ai) | 100/100 | 1002 | 0/1002 | 19/1002 | 19/1002 |
| Elba | 100/100 | 925 | 0/925 | 0/925 | **0/925** |

The baseline's 19 hallucinated entries are all invented bibliographic
identifiers for real papers: DOIs that resolve to unrelated works (a
microkernel paper cited with the DOI of a carbon monoxide study, an ICS
security paper with the DOI of an explosives detection paper, a smart
contract paper with the DOI of a different NDSS talk) or DOIs that are not
registered at all. Elba's 925 entries are byte identical registry records
by construction, and the verifier confirms 0 hallucinations empirically.

Utility is comparable: both systems completed all 100 tasks; the baseline
produced 1002 entries, Elba 925 (it may return fewer than 10 when Crossref
has no BibTeX for a hit). Elba used 4x fewer LLM calls (134 vs 549) and
2.6x fewer output tokens (270k vs 692k).

## Running

On the eval box (`source ~/eval-env.sh`):

    ~/pai-venv/bin/python eval/litsearch/run_pai.py --limit 2   # pilot first
    python eval/litsearch/run_elba.py --limit 2 --workers 2

Then locally (DBLP blocks AWS addresses, so verification runs off the box):

    python eval/litsearch/verify.py --systems pai,elba
    python eval/litsearch/tables.py --systems pai,elba
