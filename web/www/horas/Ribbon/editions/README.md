# Adding a printed breviary (page numbers)

The ribbon helper already knows the *structure* of the office (Psalter, Proper of the Season, Proper of Saints, Common, Ordinary, and the parts of each hour). A printed edition does not add a second structure. It only attaches **page numbers** to those same parts, and it does so **per volume**.

Drop one file in this directory, named `something.edition`. The edition dropdown picks it up on the next load. No code change is required. Files whose names start with `_` are ignored, so a draft can sit here as `_notes.edition` without appearing in the dropdown.

`general.edition` is the built-in choice "General structure only". It has no volumes and no page numbers. Leave it in place.

## Every set has more than one volume

Page numbers belong to a volume, and the volume depends on the **temporal cycle**, not on the civil date alone.

- A typical Latin *Breviarium Romanum* is two volumes (often Advent–Pentecost, and after Pentecost — the exact split is the book's, not a rule you should assume).
- Baronius Press prints three volumes.
- Older sets were often four (*Pars Hiemalis, Verna, Aestiva, Autumnalis*).

The same Ordinary or the same saint can sit on a different page in each volume. Record the page in the volume the reader is actually holding.

Do **not** copy another edition's volume boundaries. Open the book and record the seasons that volume really contains.

## Season codes

Each volume lists the engine's season codes it covers. The helper takes the day's season from the same week-name the office engine uses, then chooses the volume whose `seasons` line contains that code.

| Code | Part of the year |
| --- | --- |
| `Adv` | Advent |
| `Nat` | Christmas (Nativity) |
| `Epi` | Epiphany, up to Septuagesima |
| `Quadp` | Septuagesima, Sexagesima, Quinquagesima |
| `Quad` | Lent and Passiontide |
| `Pasc` | Easter through the octave of Pentecost |
| `Pent` | After Pentecost |

One code must belong to only one volume of an edition. Together the volumes should cover every code the book actually prints. If the day falls in a season you have not listed, the page shows the structure and says that this edition has no volume for that season.

The office engine also re-uses the name `Epi` for a few Sundays just before Advent (the unused Sundays after Epiphany). Those days are still **after Pentecost** in a printed breviary, so the helper treats an `Epi` week in September–December as `Pent`. You do not list that case separately.

## File format

UTF-8. Lines starting with `#` are comments. Blank lines are ignored.

```
id: baronius-1962
coming_soon: 0
name.en: Baronius Press, 1962 (three volumes)
name.la: Baronius, 1962 (tres tomi)

volume: I
label.en: Volume I — Advent to Septuagesima
label.la: Tomus I — ab Adventu ad Septuagesimam
seasons: Adv Nat Epi

section:psalterium	12
hour:Matutinum:invitatory	40
hour:Matutinum:lessons	80	Sunday lessons, this volume

volume: II
label.en: Volume II — Septuagesima to Pentecost
label.la: Tomus II — a Septuagesima ad Pentecostem
seasons: Quadp Quad Pasc

section:psalterium	14
hour:Matutinum:lessons	90

volume: III
label.en: Volume III — after Pentecost
label.la: Tomus III — post Pentecosten
seasons: Pent

section:psalterium	10
hour:Laudes:collect:Sancti/03-17	312	only if this edition prints that feast
```

The three-way split above is an **illustration of the file shape** for a three-volume set. It is not a claim about where Baronius (or any other press) actually divides the year. Replace `seasons:` with the division printed in the book you have.

- `id` becomes the value of the dropdown. It must be unique among the files in this directory.
- `name.en`, `name.es`, `name.fr`, `name.de`, `name.la` are the labels. `name.en` is used when a language has no label of its own.
- `coming_soon: 1` marks an edition that is not ready. The placeholder uses this. A finished edition uses `0`.
- `volume:` starts a volume. Everything after it, until the next `volume:` line, belongs to that volume.
- `label.*` is what the page shows ("Volume II — after Pentecost").
- `seasons:` is a space-separated list of the codes above.
- A page row is three columns separated by a tab: `key`, `page`, `note`. The note may be empty. The page is whatever is printed (Arabic numerals; include a volume-specific prefix such as `312` or `xii` if you need to).

## Keys

Keys are the ones the walkthrough already uses. The helper tries them from the most specific to the most general and uses the first page it finds in the chosen volume:

1. `hour:<Hour>:<part>:<file>` — one feast or season file, one part of one hour
2. `hour:<Hour>:<part>` — that part of that hour in this volume
3. `section:<section>:<file>` — the whole file
4. `section:<section>` — the section in this volume (Psalter, Ordinary, and so on)

`<Hour>` is one of `Matutinum`, `Laudes`, `Prima`, `Tertia`, `Sexta`, `Nona`, `Vespera`, `Completorium`.

`<part>` is one of `invitatory`, `hymn`, `antiphons`, `psalms`, `verse`, `lessons`, `te_deum`, `capitulum`, `collect`, `commemoration`, `preces`, `lectio_brevis`, `athanasian`.

`<section>` is one of `psalterium`, `tempora`, `sancti`, `commune`, `ordinarium`.

`<file>` is the engine's file without `.txt`, for example `Sancti/03-17`, `Sancti/03-17nl1`, `Tempora/Quad4-2`, `Commune/C4`, `Psalterium/Psalmi/Psalmi matutinum`.

You can be as specific or as general as the book allows. A single `section:psalterium` page is enough for the Psalter ribbon. A feast that the edition prints with its own lessons can add `hour:Matutinum:lessons:Sancti/03-17` without affecting any other feast.

When "General structure only" is selected, the same ribbons are shown and the page-number column is left empty.
