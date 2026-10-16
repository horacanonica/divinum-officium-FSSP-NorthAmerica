# Hand-off: finishing the unanswered FSSP NA Province calendars

Audience: an AI agent (Grok bot) picking this up cold. Branch: `fssp-na-province-calendars`. Do not deploy to Fly.io; do not touch `master` without the owner's say-so.

## Ground rules
1. **Never guess.** If an item below has no answer yet, leave it unanswered, keep it out of the menu, and report it. Only act on an answer given by the owner (or a cited source the owner accepts).
2. `fssp/na_province.yaml` is the single source of truth. Everything else is generated. Never hand-edit generated files (listed in `fssp/generated_manifest.json`).
3. A location is "open" while its YAML entry still contains `CONFIRM` or `propers: pending`. Open locations (and sites of open dioceses) are not generated. To release one: edit the YAML (remove `CONFIRM`/`status: CONFIRM`, set the value, add `note: "ANSWERED <date>: <answer>"`).
4. Docs to read first: `fssp/README.md`, `docs/ai/OPEN_QUESTIONS.md`, `docs/ai/LOCAL_PROPERS_REGISTRY.md`, `docs/ai/CANADA_PROPERS.md`.

## Workflow after each batch of answers
```
cd divinum-officium-FSSP-NorthAmerica
python3 -I scripts/na_province/gen.py          # regenerate (needs the web container running)
python3 -I scripts/na_province/transfers.py    # ~6 min; recomputes 2026/2027 transfers
python3 -I scripts/na_province/test_na.py      # ~10 min; all tests must pass
```
Then: move the answered rows in `docs/ai/OPEN_QUESTIONS.md` to its "Answered" section, add any commons-built feast to the Open table in `LOCAL_PROPERS_REGISTRY.md`, commit (small commits), push the branch.
Never run `pkill -f`/`pgrep -f` with a pattern that appears in your own command line.

## YAML conventions
- Titular (site): `titulars: [{title: "...", date: "MM-DD", propers: base|commons, commune: "Common of ..."}]` → elevated to local I class.
- Diocese feast: `{date, title, rank: I|II|III|as_on_feast, kind: patron_principal|patron_secondary|dedication_cathedral|other, propers: base|commons}`.
- `propers: base` means the saint has own texts in the 1962 base; the generator raises rank only. If the saint is NOT in the 1962 base at that date, use `propers: commons` with a `commune` (supported: "Common of Feasts of the BVM", "Common of a Virgin not a Martyr", "Common of a Virgin Martyr", "Common of a Confessor not a Bishop", "... (Abbot)").
- For a `propers: commons` feast you must also add to `scripts/na_province/gen.py`: a `COMMONS_TITLE[(date, owner_id)]` Latin label and, for saints whose commune oration contains `N.`, a `NAMES[title]` genitive (e.g. C5 "beáti N. Confessóris"). Flag both in the registry for Latin review.
- Movable titulars (`date: "movable:..."`) only need work if the feast is not already I class (only Holy Family is special-cased).
- Do not remove `legacy: true` from Sacramento: the owner said the legacy `Rubrics 1960 - Sacramento` calendar stays.

## Unanswered questions (numbering kept from the original list)

### Dioceses (an open diocese also hides all its sites)
**4. Lexington, Aug 22 "Queenship of Mary".** 1962 Queenship is May 31; Aug 22 is the Immaculate Heart. Which texts? Spec default (NOT yet approved): Queenship texts on Aug 22 with commemoration of the Immaculate Heart. Hides: Lexington, Georgetown.
**5. Allentown, "Mary, Mother of the Church" (movable: Monday after Pentecost).** That day is a privileged I-class day and excludes feasts. What date does the diocese use? Spec default (not approved): first free day after the octave. Hides: Allentown, Bethlehem (Holy Ghost), Allentown (St. Stephen of Hungary). Needs `propers: commons` (C11) and a Tempora/transfer mechanism for a movable date — design it, show the owner.
**6. Edmonton.** (a) Does the archdiocese have a principal patron (Ordo lists none)? (b) Bishop data is likely stale (Ordo gives Abp. Richard Smith, who is Vancouver's ordinary) — bishop commemorations are stored only, no Office effect. (c) The May 1 cathedral dedication clashes with St. Joseph the Worker (I class): on what day is it kept? Hides: Edmonton, Assumption (Vital Grandin Chaplaincy), St. Edmund's. Do NOT create any feast for Vital Grandin (Venerable only).
**7. Québec, Sep 12 Holy Name of Mary.** The Ordo lists it as principal patroness of the ecclesiastical province of Québec under Montréal. Does it also apply to the Archdiocese of Québec? Spec default (not approved): no. Hides: Québec, Saint-Zéphirin-de-Stadacona.

### Sites
**8. Phoenix, Mater Misericordiae.** Patronal date? (not in 1962 calendar; commons C11). Should the second Mass site St. Edward the Confessor (Oct 13) be elevated?
**9. Fresno, Holy Cross Chaplaincy.** Also elevate the community patron Exaltation of the Holy Cross (Sep 14) to I class?
**10. Littleton, Carmel of the Holy Spirit.** Carmelite nuns follow the Carmelite proper office. Generate an FSSP-chaplaincy calendar at all? Spec default (not approved): generate it, marked "not the nuns' choir office".
**11. Ocala, Our Lady Queen of Peace.** Patronal date: Jan 24 or Jul 9 (pro aliquibus locis)? (commons C11)
**12. Brookville, Ss. Philomena & Cecilia.** Philomena (Aug 11) was removed from the calendar in 1961. Elevate her anyway (Common of a Virgin Martyr, C6)? Cecilia (Nov 22) is fine.
**13. Georgetown, Regina Pacis community.** Date of the community patron Regina Pacis (also blocked by question 4)?
**14. Nashua, St. Stanislaus.** Stanislaus Bishop & Martyr (May 7) or Stanislaus Kostka (Nov 13)? A legacy `Rubrics 1960 - Nashua` calendar already exists and must not be changed.
**16. Conshohocken, St. Mary.** Which feast of St. Mary? (Assumption Aug 15 was assumed.)
**17. Providence, St. Mary on Broadway.** Which feast of St. Mary? (Assumption assumed.)
**18. Edmonton, St. Edmund's.** Edmund of Canterbury, Bishop (Nov 16, in the 1962 calendar) or Edmund, King & Martyr (Nov 20, pro aliquibus locis)? Also blocked by question 6.
**19. Ottawa, St. Clement.** The church building is St. Anne (Jul 26): also elevate her, as well as St. Clement (Nov 23)?
**20. Saskatoon, Sacred Heart Latin Mass Community.** Also elevate the community patron Most Sacred Heart (movable, already I class) alongside St. Joseph (church building, Mar 19)?
**21. Post Falls, St. Joan of Arc.** Data error: Joan has no proper in the 1962 base (May 30 is St. Felix I), so `propers: base` is wrong. Build from the Common of a Virgin Martyr (C6), or will the owner supply a proper?

## Already answered (do not reopen)
1. Churches are assumed consecrated unless stated otherwise (Little Rock Feb 3 implemented).
2. Sacramento: leave unchanged; legacy calendar is correct.
3. Miami: patron Immaculate Conception; cathedral dedicated Jan 27, 1957 (Wikipedia only — owner should verify with the archdiocese). Our Lady of Belen chapel still needs its own patronal date (open).
15. Harrisburg: Mater Dei community patron NOT elevated.

## Other standing items for the owner (not blocking)
- Colorado Springs cathedral dedication, Dec 19 2027, falls on Advent IV and has no free day before year end; not shown that year (`fssp/transfers_report.json`, "failed").
- The USA1960 layer lacks Seton, Neumann, the Peace votive and the external Corpus Christi solemnity that the 2026 Ordo tags USA.
- Lincoln's cathedral dedication is Aug 18 in the YAML, but the legacy OLG Seminary calendar has Sep 14.
- Latin office titles and `[Name]` genitives for commons-built feasts are generator labels — need Latin review.
- Own-church dedication anniversaries (I class) are unknown for every site.
