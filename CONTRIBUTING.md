# Contributing to divinum-officium-FSSP-NorthAmerica

This is a fork of [DivinumOfficium](https://github.com/DivinumOfficium/divinum-officium), the open-source
Latin Divine Office project. This fork adds custom calendars and particular feasts for FSSP parishes
in North America, following the 1962 Roman Rite (Extraordinary Form).

---

## Table of Contents

1. [Getting Started — Setting Up Your Local Copy](#1-getting-started)
2. [Understanding the Calendar System](#2-understanding-the-calendar-system)
3. [Creating a New Parish Calendar](#3-creating-a-new-parish-calendar)
4. [Adding a Particular Feast](#4-adding-a-particular-feast)
5. [Testing Your Changes](#5-testing-your-changes)
6. [Submitting Your Work](#6-submitting-your-work)
7. [File Reference](#7-file-reference)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Getting Started

### What You Need

- A Mac, Windows, or Linux computer
- [Git](https://git-scm.com/downloads) installed
- [Perl](https://www.perl.org/get.html) installed (comes pre-installed on Mac and most Linux)
- A text editor — [VSCode](https://code.visualstudio.com) is recommended

### Clone the Fork

Open your terminal and run:

```bash
git clone https://github.com/horacanonica/divinum-officium-FSSP-NorthAmerica.git
cd divinum-officium-FSSP-NorthAmerica
```

This downloads the entire project to your computer.

### Run It Locally

Start the local web server:

```bash
perl web/cgi-bin/webdia.pl
```

Then open your browser and go to:

```
http://localhost:8080
```

You should see the DivinumOfficium interface. If it doesn't work, see [Troubleshooting](#8-troubleshooting).

---

## 2. Understanding the Calendar System

DivinumOfficium uses a **layered calendar chain**. Think of it like a stack of transparencies:

```
Universal Roman Calendar (1960 rubrics)          ← bottom layer, always present
    ↓
USA General Calendar                              ← national layer
    ↓
FSSP Proper Calendar                             ← order-specific layer
    ↓
Diocese/Region Calendar (e.g. Sacramento)        ← diocesan layer
    ↓
Parish Calendar (e.g. Guadalajara)               ← most specific, top layer
```

Each layer can **add, replace, or defer** feasts from the layer below it. The topmost applicable
layer wins for any given day. This means a parish feast overrides a diocesan feast, which overrides
the national calendar, and so on.

### Key Concepts

**Sancti files** contain feasts of saints assigned to specific dates.
Each date has its own file named by the date, e.g. `01-25` for January 25th.

**Tempora files** contain the moveable feasts of the liturgical year (Advent, Lent, Easter, etc.).
These are calculated relative to Easter and do not need date-specific files.

**Rank** determines which feast wins when two fall on the same day. Ranks in the 1960 rubrics:
- I classis (First Class) — highest
- II classis (Second Class)
- III classis (Third Class)
- IV classis (Commemoration) — lowest

**Suffixes** identify which calendar layer a file belongs to:
- No suffix — universal Roman calendar
- `USA` — United States national calendar
- `FSSP` — FSSP proper calendar
- `g` — used in this fork for Guadalajara parish (you will define your own)

---

## 3. Creating a New Parish Calendar

This section walks you through adding a completely new parish, step by step.

### Step 1 — Choose Your Parish Identifier

Pick a short, unique code for your parish. Use only letters, no spaces or special characters.
Examples: `Sacramento`, `Denver`, `Toronto`, `Guadalajara`

This identifier will be used in filenames and configuration. We will call it `[Parish]` throughout
this guide. Replace `[Parish]` with your actual identifier everywhere you see it.

### Step 2 — Create the Calendar Configuration File

Navigate to:

```
web/www/horas/Latin/Tabulae/
```

Create a new file named `[Parish].txt`

Copy the contents of an existing parish file as your starting point — for example `Guadalajara.txt`:

```
[Guadalajara]
Calendarë=Guadalajara
Prefix=g
```

Edit your new file to match your parish:

```
[[Parish]]
Calendarë=[Parish]
Prefix=[your chosen suffix letter]
```

The **Prefix** is the suffix letter that will be added to all feast files specific to this parish.
Choose a letter not already used by another calendar in the project. Check the `Tabulae` folder
for existing prefixes before choosing yours.

### Step 3 — Register the Calendar Chain

Open:

```
web/www/horas/Latin/Tabulae/Calendars.txt
```

Add your parish to the chain. Find the section that shows how other parishes are structured
and add a line for yours following the same pattern. This tells DivinumOfficium which layers
to load and in what order when your parish is selected.

### Step 4 — Create Your Parish Sancti Directory

Navigate to:

```
web/www/horas/Latin/Sancti/
```

You will see folders for each calendar layer. Create a new folder named with your prefix letter.
For example, if your prefix is `x`, create a folder named `x`.

This folder will hold all feast files specific to your parish.

### Step 5 — Verify the Setup

Start the local server and select your parish from the interface. If the calendar loads without
errors and shows the correct base calendar, your setup is correct. You are ready to add feasts.

---

## 4. Adding a Particular Feast

This section explains how to add a feast specific to your parish — a patron saint, a local
dedication feast, or any other particular observance.

### Understanding the Feast File Structure

Each feast is a plain text file. The filename is the date in `MM-DD` format, plus your parish
prefix suffix. For example, a feast on July 4th for a parish with prefix `x` would be:

```
07-04x.txt
```

A feast file looks like this:

```
[Rank]
Festum Sancti Nominis;;III classis

[Rule]
Commemoratio=

[Prayers]
...
```

The easiest approach is to copy an existing feast file of the same rank from another calendar
and modify the name and prayers. The Guadalajara files in the `g` folder are good examples
to copy from.

### Step-by-Step: Adding a Feast

**1. Identify the date and rank**

What date is the feast? What rank should it be?
- Patron saints of a parish are typically II classis
- Dedication of a church is typically II classis
- Most other particular feasts are III classis

**2. Check for conflicts**

Look at what is already assigned to that date in the layers above. If a I classis or II classis
feast is already there universally, your feast may need to be moved to the nearest free day or
assigned as a commemoration. The 1960 rubrics govern this — when in doubt, consult a rubricist.

**3. Create the feast file**

Navigate to your parish Sancti folder:

```
web/www/horas/Latin/Sancti/[your-prefix]/
```

Create a file named `MM-DDx.txt` (where `x` is your prefix letter).

The minimum structure for a simple feast:

```
[Rank]
Festum Sancti [Name];;[Rank in classis format]

[Rule]
Commemoratio=

[Lectio1]
(your first lesson text here, or a reference to a common)

[Lectio2]
(your second lesson text)

[Lectio3]
(your third lesson text)

[Oratio]
(the collect for this feast)
```

**4. Use Commons for standard text**

Most particular feasts do not have unique Office texts — they borrow from the Commons
(Common of One Martyr, Common of a Doctor, Common of a Virgin, etc.). Reference the
appropriate Common rather than duplicating text:

```
[Rule]
Lectio1=Commune/C2
```

This pulls the lesson from the Common of One Martyr. Browse the `Commune` folder to see
what commons are available.

**5. Test the feast**

Load the date in your local DivinumOfficium instance with your parish selected. Verify:
- The correct feast name appears
- The rank is correct
- The texts display properly
- Commemorations appear correctly if applicable

---

## 5. Testing Your Changes

Before submitting anything, test thoroughly locally.

### Basic Testing Checklist

- [ ] Local server starts without errors
- [ ] Your parish appears in the calendar selector
- [ ] A normal weekday shows correct texts
- [ ] Your new feast appears on its assigned date
- [ ] The feast rank is correct
- [ ] Surrounding days are not disrupted
- [ ] Commemorations display correctly where expected
- [ ] The anticipation of Matins works correctly (if testing evening)

### Testing Edge Cases

Check days near your feast:
- The day before (does Vespers correctly anticipate the feast?)
- The feast day itself
- The day after (does the octave appear if applicable?)
- Any day where your feast might conflict with a moveable feast

### Check the Console for Errors

In your browser, open Developer Tools (Cmd+Option+I on Mac) and check the Console tab
for any errors while navigating to your feast days.

---

## 6. Submitting Your Work

### If You Are Contributing to This Fork

1. Create a new branch for your work:
```bash
git checkout -b add-[parish-name]-calendar
```

2. Make your changes, then commit:
```bash
git add .
git commit -m "Add [Parish] calendar with [description of feasts]"
```

3. Push to GitHub:
```bash
git push origin add-[parish-name]-calendar
```

4. Open a Pull Request on GitHub describing what you added.

### If You Want to Contribute Upstream to DivinumOfficium

General calendar additions (USA national feasts, widely applicable FSSP proper feasts) may be
appropriate to submit to the main DivinumOfficium project at:

```
https://github.com/DivinumOfficium/divinum-officium
```

Highly particular parish-specific feasts should remain in this fork only.

When submitting upstream:
- Read their CONTRIBUTING guidelines first
- Write a clear description of what the addition covers and its liturgical basis
- Be patient — maintainers are volunteers

---

## 7. File Reference

### Directory Structure

```
web/www/horas/Latin/
├── Sancti/                    ← Saint feast files by date
│   ├── [no prefix]/           ← Universal Roman calendar
│   ├── USA/                   ← USA national calendar
│   ├── FSSP/                  ← FSSP proper calendar
│   └── [your-prefix]/         ← Your parish calendar
├── Tempora/                   ← Moveable feasts (Advent, Lent, Easter, etc.)
├── Tabulae/                   ← Calendar configuration files
│   ├── Calendars.txt          ← Calendar chain definitions
│   ├── Guadalajara.txt        ← Example parish config
│   └── [Parish].txt           ← Your parish config (you create this)
└── Commune/                   ← Common texts (Commons of saints)
```

### Feast File Naming Convention

```
MM-DD[prefix].txt
```

Examples:
- `07-04.txt` — July 4th, universal calendar
- `07-04g.txt` — July 4th, Guadalajara parish
- `07-04x.txt` — July 4th, your parish (if prefix is x)

### Rank Strings

Use these exact strings in the `[Rank]` section:

| Rank | String to use |
|------|--------------|
| First Class | `;;I classis` |
| Second Class | `;;II classis` |
| Third Class | `;;III classis` |
| Commemoration | `;;Commemoratio` |

---

## 8. Troubleshooting

**Local server won't start**
Make sure Perl is installed: `perl --version`
Make sure you are in the project root directory when running the command.

**My parish doesn't appear in the selector**
Check that your `[Parish].txt` file is in `web/www/horas/Latin/Tabulae/` and that
it is registered in `Calendars.txt`.

**My feast isn't showing up**
Check the filename — it must match `MM-DD[prefix].txt` exactly with the correct prefix.
Check that your Sancti folder name matches your prefix letter exactly.

**The wrong feast is showing**
A higher-ranked feast in a lower layer is taking precedence. Check what feast is assigned
to that date in the universal, USA, and FSSP layers. Adjust your feast rank or date accordingly.

**Texts are displaying incorrectly or garbled**
DivinumOfficium files must be saved in UTF-8 encoding. Check your text editor's encoding
settings and re-save if necessary.

**Something else is broken**
Open an issue on this repository with the date, the parish, and a description of what
you expected versus what you saw.

---

## Notes on the 1962 Rubrics

This fork follows the 1962 Roman Rite rubrics as used by the FSSP. When making decisions
about feast ranks, precedence, and commemoration rules, the authoritative source is the
*Rubricae Generales Breviarii* as found in the 1961 edition of the Roman Breviary.

When in doubt about a rubrical question, consult a priest familiar with the traditional rite
before implementing a change. Getting the rubrics right matters more than getting the
code right quickly.

---

*This fork is maintained under the same open source license as DivinumOfficium.
See LICENSE for details.*
