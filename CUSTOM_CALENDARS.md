# Divinum Officium — FSSP & North American Custom Calendar Supplement

A layered set of proper offices for the **FSSP** (Fraternitas Sacerdotalis Sancti Petri)
and the **United States**, following the 1960 rubrics, designed to drop into any existing
installation of [Divinum Officium](https://github.com/DivinumOfficium/divinum-officium).

Also included: a worked example of a **diocesan/parish calendar** (Diocese of Sacramento /
Church of St. Stephen), demonstrating how any parish can add its own proper feasts on top
of the North American supplement with minimal effort.

---

## How the Calendar Chain Works

The DO engine resolves any date by walking up an inheritance chain. Each level only
declares what it **adds or overrides**; everything else falls through to the parent:

```
Rubrics 1960 - 1960           (stock DO — base for all 1960 rubrics)
    └── Rubrics 1960 - FSSP         adds: Feb 22 (Chair of St. Peter, I cl.)
    |                                      Mar 7  (St. Thomas Aquinas, II cl.)
    |                                      Aug 1  (St. Peter in Chains, III cl.)
    |
    └── Rubrics 1960 - FSSP USA     adds everything in FSSP, plus:
    |       (inherits from FSSP)           Sep 9  (St. Peter Claver, III cl.)
    |                                      Sep 26 (SS. Jogues & de Brébeuf, III cl.)
    |                                      Oct 25 (St. Isidore the Farmer, III cl.)
    |                                      Nov 13 (St. Frances Xavier Cabrini, III cl.)
    |                                      Dec 12 (Our Lady of Guadalupe, III cl.)
    |
    └── Rubrics 1960 - Sacramento   adds everything above, plus:
    |       (inherits from FSSP USA)       Mar 17 (St. Patrick, I cl.)
    |                                      Jun 30 (Cathedral Dedication, I cl.)
    |                                      Aug 2  (St. Stephen — I Vespers, I cl.)
    |                                      Aug 3  (Finding of St. Stephen, I cl.)
    |                                      Dec 12 (Guadalupe promoted to I cl.)
    |
    └── Rubrics 1960 - Guadalajara  adds everything in FSSP (not USA), plus:
            (inherits from FSSP)           Jan 24 (S. Mariæ Pacis, III cl.)
                                           Feb 5  (S. Philippus a Jesu, III cl.)
                                           Feb 25 (B. Sebastianus ab Apparitio, III cl.)
                                           Mar 2  (B. Bartholomæus Gutierrez, III cl.)
                                           May 15 (S. Isidorus Agricola, III cl.)
                                           May 16 (S. Joannes Nepomucen, II cl.)
                                           Jul 4  (B.M.V. Refugium Peccatorum, II cl.)
                                           Aug 17 (B. Bartholomæus Laurel, III cl.)
                                           Aug 30 (S. Rosa de Lima, I cl.)
                                           Oct 12 (S.M.V. de Zapopan, I cl.)
                                           Oct 21 (Ss. Ursula et Sociæ, III cl.)
                                           Oct 22 (Dedicatio Cathedralis, I cl.)
                                           Dec 18 (In Expectatione Partus B.M.V. — Commemoratio ad Laudes)
```

A new diocese or parish = one small `.txt` file + one line in `data.txt`.

---

## Package Contents

### Kalendaria/ (calendar definition files)
| File | Purpose |
|------|---------|
| `FSSP.txt` | FSSP proper offices (3 feasts) |
| `USA1960.txt` | North American supplement (5 feasts) |
| `Sacramento.txt` | Example diocese/parish calendar |
| `Guadalajara.txt` | Archdiocese of Guadalajara, MX (13 feasts, inherits FSSP not USA) |

### Sancti/ (office text files)
| File | Saint | Notes |
|------|-------|-------|
| `09-09u.txt` | S. Petrus Claver (Sep 9) | New USA proper from FSSP Supplementum |
| `09-26n.txt` | SS. Isaac Jogues & John de Brébeuf (Sep 26) | Corrected spelling, added Ant 2 |
| `10-25n.txt` | S. Isidore the Farmer (Oct 25) | Corrected spelling |
| `11-13n.txt` | S. Frances Xavier Cabrini (Nov 13) | Added Invit, Ant 2/3, Capitula |
| `12-12n.txt` | B.M.V. de Guadalupe (Dec 12) — III cl. | USA-only; corrected spelling, removed erroneous 9-lesson rule |
| `12-12s.txt` | B.M.V. de Guadalupe (Dec 12) — I cl. | Sacramento-only override |
| `06-30s.txt` | Dedicatio Ecclesiae Cathedralis Sacramentensis (Jun 30) | Sacramento-specific |
| `08-02s.txt` | Inventio S. Stephani Protomartyris — I Vespers (Aug 2) | Sacramento-specific |
| `08-03s.txt` | Inventio S. Stephani Protomartyris (Aug 3) | Sacramento-specific |

#### Guadalajara proper offices (`g` suffix)
| File | Saint | Rank | Notes |
|------|-------|------|-------|
| `01-24g.txt` | S. Mariæ Pacis (Jan 24) | III cl. | Common BVM (C11) |
| `02-05g.txt` | S. Philippi a Jesu Martyris (Feb 5) | III cl. | Proper hymns + Lectio94 |
| `02-25g.txt` | B. Sebastiani ab Apparitio (Feb 25) | III cl. | Proper Lectio94 + Oratio |
| `03-02g.txt` | B. Bartholomæi Gutierrez (Mar 2) | III cl. | Proper Lectio94 + Oratio |
| `05-15g.txt` | S. Isidori Agricolæ (May 15) | III cl. | Proper Oratio; Common C5 |
| `05-16g.txt` | S. Joannis Nepomuceni (May 16) | II cl. | Proper Lectio4–6, Lectio94, hymn + Oratio |
| `07-04g.txt` | B.M.V. Refugium Peccatorum (Jul 4) | II cl. | Proper Oratio; Common BVM |
| `08-17g.txt` | B. Bartholomæi Laurel (Aug 17) | III cl. | Proper Lectio94 + Oratio |
| `08-30g.txt` | S. Rosæ de Lima (Aug 30) | I cl. | Proper Lectio4–6, Lectio94 + Oratio |
| `10-12g.txt` | S.M.V. de Zapopan (Oct 12) | I cl. | Common BVM at I classis |
| `10-21g.txt` | Ss. Ursulæ et Sociarum (Oct 21) | III cl. | Proper Lectio94 + Oratio |
| `10-22g.txt` | Dedicatio Cathedralis Guadalajarensis (Oct 22) | I cl. | Common Dedication (C8) |
| `12-18g.txt` | In Expectatione Partus B.M.V. (Dec 18) | Semiduplex | Commemoratio ad Laudes; proper Ant, V/R, Oratio |

---

## Installation

### Prerequisites
- A working installation of [Divinum Officium](https://github.com/DivinumOfficium/divinum-officium)
- The root of that installation is referred to below as `DO_ROOT/`

---

### Step 1 — Copy Sancti files

```bash
cp Sancti/*.txt DO_ROOT/web/www/horas/Latin/Sancti/
```

---

### Step 2 — Copy Kalendaria files

```bash
cp Kalendaria/*.txt DO_ROOT/web/www/Tabulae/Kalendaria/
```

---

### Step 3 — Add entries to data.txt

Open `DO_ROOT/web/www/Tabulae/data.txt` and find this line:

```
Rubrics 1960 - 1960,1960,1960,1960,Reduced - 1955
```

Insert the following four lines **immediately after it**:

```
Rubrics 1960 - FSSP,FSSP,FSSP,FSSP,Rubrics 1960 - 1960
Rubrics 1960 - USA 1960,USA1960,FSSP,FSSP,Rubrics 1960 - 1960
Rubrics 1960 - FSSP USA,USA1960,FSSP,FSSP,Rubrics 1960 - FSSP
Rubrics 1960 - Sacramento,Sacramento,FSSP,FSSP,Rubrics 1960 - FSSP USA
```

**Column reference:** `version, kalendar, transfer, stransfer, base`

- `version` — the full name used in the UI and EPUB generator
- `kalendar` — which `.txt` file in `Kalendaria/` to use
- `transfer` / `stransfer` — which Transfer/Stransfer rule set applies
- `base` — the parent version (inheritance chain)

---

### Step 4 — Update Transfer and Stransfer files

The FSSP transfer rules use the code `FSSP` to identify which calendar versions they apply to.
Run the following from `DO_ROOT/` to apply the rename:

**macOS:**
```bash
find web/www/Tabulae/Transfer web/www/Tabulae/Stransfer -name "*.txt" \
  -exec sed -i '' 's/;;Newcal/;;FSSP/g; s/ Newcal/ FSSP/g' {} +
```

**Linux:**
```bash
find web/www/Tabulae/Transfer web/www/Tabulae/Stransfer -name "*.txt" \
  -exec sed -i 's/;;Newcal/;;FSSP/g; s/ Newcal/ FSSP/g' {} +
```

---

### Step 5 — Patch epubgen2.sh (for EPUB generation)

If you plan to generate EPUBs, two edits are needed in
`DO_ROOT/standalone/tools/epubgen2/epubgen2.sh`:

#### 5a — Add custom rubrics to the lookup arrays

Find the three array lines (around line 84) and append the new entries:

```bash
# Before:
ALL_RUBRICS_CODES=(1570 1888 1906 DA 1955 1960 Newcal 1617 1930 1963 1951 Altovado Dominican)
ALL_RUBRICS=("Tridentine - 1570" ... "Ordo Praedicatorum - 1962")
ALL_RUBRICS_NAME=(_1570 _1888 _1906 _DA _1955 "" _NC _M1617 _M1930 Monastic _Cist _Altovado _OP)

# After (append the four new entries to each array):
ALL_RUBRICS_CODES=(1570 1888 1906 DA 1955 1960 Newcal 1617 1930 1963 1951 Altovado Dominican FSSP USA1960 FSSPUSA Sacramento)
ALL_RUBRICS=("Tridentine - 1570" ... "Ordo Praedicatorum - 1962" "Rubrics 1960 - FSSP" "Rubrics 1960 - USA 1960" "Rubrics 1960 - FSSP USA" "Rubrics 1960 - Sacramento")
ALL_RUBRICS_NAME=(_1570 _1888 _1906 _DA _1955 "" _NC _M1617 _M1930 Monastic _Cist _Altovado _OP _FSSP _USA1960 _FSSPUSA _Sac)
```

#### 5b — Fix bash 3.2 compatibility (macOS only)

macOS ships with bash 3.2, which does not support the `&>>` operator.
Find the two occurrences of:

```bash
$OPTIONAL_KINDLEGEN_PATH $EPUB_FILENAME &>> "${EPUBDIR}/kindlegen.log"
```

Replace each with:

```bash
$OPTIONAL_KINDLEGEN_PATH $EPUB_FILENAME >> "${EPUBDIR}/kindlegen.log" 2>&1
```

---

## Generating EPUBs

Run from `DO_ROOT/standalone/tools/epubgen2/`:

```bash
# FSSP proper offices (Feb 22, Mar 7, Aug 1)
bash epubgen2.sh -y 2026 -r FSSP -o /path/to/output/FSSP

# USA 1960 — FSSP + North American saints
bash epubgen2.sh -y 2026 -r USA1960 -o /path/to/output/USA1960

# FSSP USA — full FSSP + USA chain combined
bash epubgen2.sh -y 2026 -r FSSPUSA -o /path/to/output/FSSPUSA

# Sacramento — full chain including diocesan/parish feasts
bash epubgen2.sh -y 2026 -r Sacramento -o /path/to/output/Sacramento

# Guadalajara — Archdiocese of Guadalajara (FSSP base, no North American feasts)
bash epubgen2.sh -y 2026 -r Guadalajara -o /path/to/output/Guadalajara
```

Each run produces 12 monthly EPUBs and one full-year EPUB.

---

## Creating a Custom Calendar for a New Diocese or Parish

### 1. Create the calendar file

Create `DO_ROOT/web/www/Tabulae/Kalendaria/MyDiocese.txt`:

```
#My Diocese Proper Offices
*January*
*February*
*March*
*April*
*May*
06-29=06-29n~06-29=Dedicatio Ecclesiae Cathedralis=1=
*June*
*July*
*Augustus*
*September*
*October*
*November*
*December*
```

**Entry format:** `MM-DD=SanctiFile~FallbackFile=Feast Name=Class=`

| Part | Meaning |
|------|---------|
| `MM-DD` | Date |
| `SanctiFile` | Filename (without `.txt`) in `Sancti/` |
| `~FallbackFile` | Optional: used as automatic commemoration when feast is superseded |
| `Feast Name` | Display name |
| `Class` | `1` = I classis, `2` = II classis, `3` = III classis |

### 2. Add to data.txt

```
Rubrics 1960 - MyDiocese,MyDiocese,FSSP,FSSP,Rubrics 1960 - FSSP USA
```

### 3. For a parish beneath the diocese

Create `Kalendaria/MyParish.txt` and add to `data.txt`:

```
Rubrics 1960 - MyParish,MyParish,FSSP,FSSP,Rubrics 1960 - MyDiocese
```

The parish inherits all feasts from the diocese, which inherits from FSSP USA, and so on.

---

## Creating a New Sancti File

If a feast has no existing office in the DO database, create
`DO_ROOT/web/www/horas/Latin/Sancti/MM-DDx.txt` (choose a suffix letter unused on that date).

Minimum required sections for a **III classis** feast under 1960 rubrics:

```
[Officium]
Name of the Saint

[Rank]
;;Duplex;;3;;vide C5

[Rule]
vide C5;

[Oratio]
Prayer text.
$Per Dominum

[Lectio94]
Single-paragraph lesson (bio + canonization). End with:
&teDeum

[Ant 2]
Benedictus antiphon * text here.

[Ant 3]
Magnificat antiphon * text here.
```

**Rule codes by class:**
- I classis: `vide C10` (or appropriate C-code for feast type)
- II classis: `vide C7` (double of II class)
- III classis: `vide C5` (double of III class)

**`[Lectio94]`** is the single summary lesson generated when 1960 rubrics reduce Matins
to one nocturne. The `&teDeum` at the end replaces the second and third nocturnes.

---

## Source of North American Proper Offices

All offices for the five North American feasts are drawn from the official FSSP supplementum:

> *Breviarium Romanum — Supplementum: North America* (2-column edition)
> Pontificia Commissio Ecclesia Dei, Prot. N. 153/2009

The text of the Sacramento diocesan offices follows the same format and rubrical tradition.

---

## License & Attribution

These files are intended as a contribution to the
[Divinum Officium](https://github.com/DivinumOfficium/divinum-officium) project
and follow its existing license and file structure. Sancti texts are taken from
approved liturgical sources. The Sacramento proper offices are specific to that
diocese and parish and are provided as a worked example only.
