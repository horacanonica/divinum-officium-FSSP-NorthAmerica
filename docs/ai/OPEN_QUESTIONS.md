# Open questions — locations held back until answered

Per instruction: nothing below is guessed. Each location with an unanswered question is **not generated and not listed in the version menu** (`horas.dialog`). A location whose diocese is held back is held back too (its chain would be incomplete).
When an answer arrives: edit `fssp/na_province.yaml` (remove `CONFIRM`/`pending`, fill the value), run `python3 -I scripts/na_province/gen.py`, then `transfers.py`, then the tests.

## Dioceses held back (and the sites that depend on them)
| Diocese | Question | Also hides |
|---|---|---|
| Little Rock | Feb 3 Dedication of Consecrated Churches — only in consecrated churches. Are the Cabot / Springdale churches consecrated? (Spec default was "do not implement".) | Cabot (St. John the Baptist), Springdale (Our Lady of Sorrows) |
| Sacramento | Jun 30 cathedral dedication — when not on a Sunday, transferred to the Sunday before or after at the Bishop's direction. Which? (Spec default: keep Jun 30.) | Sacramento (St. Stephen) — the legacy `Rubrics 1960 - Sacramento` calendar is untouched and still available |
| Miami | Not in the Ordo supplement: principal patron and cathedral-dedication date unknown. | Miami (Our Lady of Belen) |
| Lexington | Aug 22 "Queenship of Mary": 1962 Queenship is May 31, Aug 22 is the Immaculate Heart. Which texts? (Spec default: Queenship texts with comm. of Immaculate Heart.) | Georgetown (St. Francis de Sales / Regina Pacis) |
| Allentown | "Mary, Mother of the Church": Monday after Pentecost is a privileged I-class day. Which date does the diocese use? (Spec default: first free day after the octave.) | Bethlehem (Holy Ghost), Allentown (St. Stephen of Hungary) |
| Edmonton | No principal patron listed; the Ordo gives Abp. Richard Smith (Vancouver) as ordinary — bishop data likely stale; May 1 dedication clashes with St. Joseph the Worker (I class) — which day? | Edmonton (Assumption), Edmonton (St. Edmund's) |
| Québec | Does the province patroness (Sep 12, Holy Name of Mary, listed under Montréal) also apply to Québec? (Spec default: not added.) | Québec (St-Zéphirin) |

## Sites held back (own question)
| Site | Question |
|---|---|
| Phoenix — Mater Misericordiae | Patronal date unknown. Second Mass site St. Edward the Confessor (Oct 13): elevate? |
| Fresno — Holy Cross Chaplaincy | Community patron Exaltation of the Holy Cross (Sep 14): elevate to I class as well as St. Anthony? |
| Littleton — Carmel of the Holy Spirit | Carmelite nuns follow the Carmelite proper office; generate an FSSP-chaplaincy calendar at all? |
| Ocala — Our Lady Queen of Peace | Patronal date: Jan 24 or Jul 9 (pro aliquibus locis)? |
| Miami — Our Lady of Belen | Patronal date unknown (also blocked by Miami diocese). |
| Brookville — Ss. Philomena & Cecilia | Philomena (Aug 11) was removed from the calendar in 1961; elevate her anyway (built from Common of a Virgin Martyr)? |
| Georgetown — Regina Pacis community | Date of Regina Pacis (also blocked by Lexington). |
| Nashua — St. Stanislaus | Stanislaus Bishop & Martyr (May 7) or Stanislaus Kostka (Nov 13)? (A legacy `Rubrics 1960 - Nashua` calendar exists and is untouched.) |
| Harrisburg — St. Lawrence / Mater Dei | Community patron Mater Dei (Oct 11): elevate as well as St. Lawrence? |
| Conshohocken — St. Mary | Which feast of St. Mary (Assumption assumed)? |
| Providence — St. Mary on Broadway | Which feast of St. Mary (Assumption assumed)? |
| Edmonton — St. Edmund's | Edmund of Canterbury (Nov 16) or Edmund, King & Martyr (Nov 20)? |
| Ottawa — St. Clement | Church building is St. Anne (Jul 26): elevate as well as St. Clement (Nov 23)? |
| Saskatoon — Sacred Heart LM Community | Community patron Sacred Heart: elevate as well as St. Joseph (church building)? |
| Post Falls — St. Joan of Arc | **Data error**: Joan of Arc has no proper in the 1962 base (May 30 is St. Felix I), so `propers: base` cannot be honoured. Build from the Common of a Virgin Martyr, or supply a proper? |

## Not blocking, but noted
- Every site: own church dedication anniversary unknown (I class when known).
- Bishop anniversary Mass commemorations ("pro Episcopo") are stored in the YAML only; the fork has no Mass-collect commemoration mechanism for them.
