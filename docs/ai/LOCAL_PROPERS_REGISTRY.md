# Local feasts using commons — replace when propers are found

Purpose: every local I/II-class feast below was built from the Commune because no proper Office exists in the 1962 base or in this repo. When a proper is found, replace the commons with it.

## How to replace commons with propers (instructions for future AI sessions)
1. Identify the source. Acceptable: Proprium Sanctorum pro Aliquibus Locis (1962 Missal/Breviary appendix), approved diocesan or religious-order propria (e.g. Redemptorist, Carmelite, Franciscan, Society of the Sacred Heart), pre-1962 approved local propers. Record title, edition, year, page.
2. Create/replace the Sancti file for that feast IN THE LAYER WHERE IT IS USED (site or diocese) — do not put local propers in the FSSP or national layers unless they genuinely apply there.
3. Replace only the parts the proper supplies (e.g. proper Oratio + Nocturn II legend); keep commons for the rest, and say so in the file header.
4. Keep rank and date exactly as in fssp/na_province.yaml. Update that YAML entry: `propers: proper`, `source: "<citation>"`.
5. Render the affected calendars for current and next year; verify Matins has 3 nocturns/9 lessons, Lauds/Vespers antiphons and Oratio are the new ones, commemorations still correct.
6. Move the row below from "Open" to "Done" with date and source.

NOTE: `fssp/na_province.yaml` is the source for `scripts/na_province/gen.py`, which regenerates every `*nc*`, `*ndc`, `*nl1/nl2` Sancti file. Hand-written propers must be given a different filename suffix and referenced via `use_file` in gen.py, or they will be deleted on the next generation.

## Open
| Feast | Date | Where (layer) | Rank | Commons used | Likely proper source |
|---|---|---|---|---|---|
| Our Lady of the Angels (Reginæ Angelorum), principal patroness | 09-04 | DIOCESE Archdiocese of Los Angeles | I | C11 (Feasts of the BVM) | Proprium pro aliquibus locis / Archdiocese of Los Angeles propria |
| St. Theodora Guérin, Virgin, principal patroness | 10-03 | DIOCESE Archdiocese of Indianapolis (St. Thérèse commemorated) | I | C6a (Virgins) via C7a oratio; [Name] "Theodóræ" | Diocesan proprium (canonized 2006); Sisters of Providence |
| St. Philippine Duchesne, Virgin | 11-17 | DIOCESE Archdiocese of Kansas City in Kansas | III | Repo file `11-17mh` (Oratio + Lectio94 from Maple Hill), C6a for the rest | Society of the Sacred Heart propria |
| St. Philippine Duchesne, Virgin (titular) | 11-17 | SITE Westwood KS | I | `11-17mh` raised to I class (+ 9 lectiones from C6a) | Society of the Sacred Heart propria |
| St. Columba, Abbot, principal patron | 06-09 | DIOCESE Diocese of Youngstown (Ss. Primus & Felician commemorated) | I | C5b (Abbot); [Name] "Columbæ" | Irish/Benedictine propria; pro aliquibus locis |
| Our Lady of Perpetual Help, principal patroness | 06-27 | DIOCESE Diocese of Rapid City | I | C11 | Redemptorist propria / pro aliquibus locis |
| St. Gerard Majella, secondary patron | 10-16 | DIOCESE Diocese of Calgary | II | C5; [Name] "Gerárdi" | Redemptorist propria |
| Our Lady of Fatima (Rosary of Fatima) | 05-13 | SITE Pequannock NJ (St. Robert Bellarmine commemorated) | I | C11 | Pro aliquibus locis (Fatima) |
| St. Damien of Molokai, Confessor | 05-10 | SITE Edmond OK (St. Antoninus commemorated) | I | C5; [Name] "Damiáni" | Sacred Hearts Fathers propria; 2009 canonization |
| St. Vitus (Ss. Vitus, Modestus & Crescentia) | 06-15 | SITE Northridge CA | I | Base file is Simplex (Lectio93 only, Oratio proper); Matins lessons from C3 | — (base has own Oratio + one legend lesson) |

Latin office titles and the `[Name]` genitives used above are labels chosen by the generator, not liturgical texts — have a Latinist check them.

## Also pending (not commons, but missing data)
- Own-church dedication anniversaries (I class) for every site — dates unknown.
- Titulars marked CONFIRM in the YAML (see OPEN_QUESTIONS.md).
- Dioceses missing from the Ordo supplement (Miami; Edmonton has no principal patron listed).

## Done
| Feast | Date | Layer | Source | Date replaced |
|---|---|---|---|---|
