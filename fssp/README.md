# FSSP North American Province calendars

`na_province.yaml` is the single source of truth (FSSP 2026 Ordo, NA Province). Everything below is generated from it.

```
python3 -I scripts/na_province/gen.py         # Kalendaria, Sancti overrides, data.txt, Tempora, horas.dialog
python3 -I scripts/na_province/transfers.py   # impeded local I-class feasts, 2026 & 2027 (needs the web container)
python3 -I scripts/na_province/test_na.py     # regression / Canada / spot-check tests (needs the web container)
```

Chains (this fork resolves a calendar by walking `base` in `Tabulae/data.txt`, per date):

```
USA:     1960 → FSSP → FSSP USA (kalendar USA1960) → Diocese of X → <site>
Canada:  1960 → FSSP → FSSP Canada (kalendar CAN1960, PENDING) → Diocese of X → <site>
```

Generated files are listed in `generated_manifest.json` and removed/rewritten on each run; do not hand-edit them.
Naming: `Kalendaria/Dio<Id>.txt`, `Kalendaria/Site<Id>.txt`; Sancti `MM-DDndc` (cathedral dedication), `MM-DDnl1`/`nl2` (base feast raised to I/II class), `MM-DDnc<diocese>` (commons-built); `Tempora/Epi1-0nhf` (Holy Family as local I class).
Local transfer lines in `Tabulae/Transfer/<easter>.txt` carry a `NAP-…` token so they only affect that layer and its children.

Open questions (CONFIRM / pending) are never generated: see `docs/ai/OPEN_QUESTIONS.md`.
`generation_report.json`, `transfers_report.json` – what was elevated, tagged only, collided, transferred.
`golden_usa_chain.json` – snapshot of the pre-existing USA chain for the no-regression test.
