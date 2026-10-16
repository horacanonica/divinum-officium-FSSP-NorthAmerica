# Canadian propers — instructions for future AI sessions

STATUS: PENDING. The Officia Propria Canadensis (1962) / Canadian supplement texts have NOT been supplied yet.

## Which apostolates are Canadian
Every site in fssp/na_province.yaml with `country: CA`. As of the 2026 Ordo:
- Diocese of Calgary, AB — St. Anthony Church (+ FSSP Calgary House)
- Archdiocese of Edmonton, AB — Vital Grandin Chaplaincy: Assumption Catholic Church; St. Edmund's Parish
- Archdiocese of Vancouver, BC — Holy Family Parish
- Archdiocese of Québec, QC — Église Saint-Zéphirin-de-Stadacona
- Archdiocese of Montréal, QC — Église St-Irénée
- Archdiocese of Ottawa, ON — St. Clement Parish (at St. Anne Church)
- Diocese of St. Catharines, ON — St. Aloysius Parish, Thorold
- Diocese of Saskatoon, SK — Sacred Heart of Jesus Latin Mass Community, St. Joseph's Church
If a new Canadian apostolate is added, it MUST use the CAN1960 chain, never USA1960.

## Repo specifics (how the chain is actually built here)
- Canadian chain: `Rubrics 1960 - 1960` → `Rubrics 1960 - FSSP` → `Rubrics 1960 - FSSP Canada` (kalendar `CAN1960`) → diocese → site.
  The USA chain is `… → FSSP → FSSP USA` (kalendar `USA1960`) → diocese → site. FSSP is delta-only, so it stacks on either.
- The legacy `Rubrics 1960 - Niagara` calendar was re-based onto `FSSP Canada`.
- Version names must also be listed in `web/www/horas/horas.dialog` `[versions]`.

## Hard rule
Canadian calendars never inherit from USA1960. The test suite (scripts/na_province/test_na.py) enforces this — do not weaken that test. The only North-American item shared today is Dec 12 Our Lady of Guadalupe (III class), which lives independently in CAN1960.

## How to incorporate the Canadian propers when they arrive
1. Read the supplied source (scan/PDF/text). Extract every calendar entry: date, Latin title, 1960 rank, and full Office texts (or Commune references).
2. Put them ONLY in the CAN1960 layer, using the same Sancti file conventions as USA1960 (separate files/namespace — never edit USA files to serve Canada).
3. Known items to expect/verify (from the FSSP 2026 Ordo):
   - Sep 26 Canadian Martyrs — II class, St. Jean de Brébeuf named first (vs USA: III class, Isaac Jogues first).
   - Dec 12 Our Lady of Guadalupe — listed "ubi conceditur" in Officia Propria Canadensis; already in CAN1960 as III class per CDW 1999 decree.
   - Expect also: St. Joseph principal patron of Canada (Mar 19, already I class), St. Anne (Jul 26, patroness of Québec), and Canadian saints/blesseds of the 1962 supplement. Implement only what the source actually contains.
4. Where a Canadian entry and a diocesan or site entry collide, the site/diocese layers sit above CAN1960 and win per 1960 precedence — re-run the 2026/2027 render and check transfers.
5. Re-run: the "no USA inheritance" test, full-year renders for every Canadian site, and compare 2026 against the FSSP Ordo calendar pages (any line tagged CAN or CAN & USA).
6. Remove the PENDING header from CAN1960 and update this file's STATUS line with the source used and date.
