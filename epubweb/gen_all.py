#!/usr/bin/env python3
"""
Auto-generate or purge EPUBs for all discovered calendars.

Usage:
  gen_all.py                      # generate current year in Latin
  gen_all.py --year 2027          # generate a specific year
  gen_all.py --purge-year 2025    # delete all output dirs for that year
"""
import argparse
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

OUTPUT_BASE    = Path("/epub-output")
EPUBGEN_SH     = "/var/www/standalone/tools/epubgen2/epubgen2.sh"
EPUBGEN_DIR    = "/var/www/standalone/tools/epubgen2"
DATA_TXT       = Path("/var/www/web/www/Tabulae/data.txt")
KALENDARIA_DIR = Path("/var/www/web/www/Tabulae/Kalendaria")

_EXCLUDE_CODES  = {"USA1960", "1960"}
_PARISH_PARENTS = {"Rubrics 1960 - FSSP USA", "Rubrics 1960 - FSSP"}


def load_calendars():
    """Return list of (code, label) for all active calendars."""
    seen, result = set(), []
    if DATA_TXT.exists() and KALENDARIA_DIR.exists():
        with open(DATA_TXT) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#') or line.startswith('version'):
                    continue
                parts = line.split(',')
                if len(parts) < 5:
                    continue
                version_name, code, parent = parts[0], parts[1], parts[4]
                if (version_name.startswith('Rubrics 1960 - ')
                        and code not in seen
                        and code not in _EXCLUDE_CODES
                        and parent in _PARISH_PARENTS
                        and (KALENDARIA_DIR / f"{code}.txt").exists()):
                    result.append((code, version_name[len('Rubrics 1960 - '):]))
                    seen.add(code)
    for code, label in [("FSSPUSA", "FSSP USA"), ("FSSP", "FSSP")]:
        if code not in seen:
            result.append((code, label))
    return result


def generate_year(year: int):
    calendars = load_calendars()
    print(f"Generating EPUBs for {year} — "
          f"{len(calendars)} calendar(s): {', '.join(c for c, _ in calendars)}", flush=True)
    OUTPUT_BASE.mkdir(parents=True, exist_ok=True)
    errors = []
    for code, label in calendars:
        output_key = f"{year}_{code}_Latin"
        out_dir = OUTPUT_BASE / output_key
        if out_dir.exists():
            shutil.rmtree(out_dir)
        out_dir.mkdir(parents=True)
        print(f"  [{label}] generating {year}…", flush=True)
        cmd = ["bash", EPUBGEN_SH, "-y", str(year), "-r", code, "-l", "Latin",
               "-o", str(out_dir)]
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=EPUBGEN_DIR)
        if result.returncode == 0:
            epubs = list(out_dir.glob("*.epub"))
            print(f"  [{label}] done — {len(epubs)} file(s)", flush=True)
        else:
            err = (result.stderr or result.stdout or "")[-400:]
            print(f"  [{label}] FAILED: {err}", flush=True)
            errors.append(label)
    if errors:
        print(f"\nFailed calendars: {', '.join(errors)}", flush=True)
        sys.exit(1)
    print(f"\nAll done for {year}.", flush=True)


def purge_year(year: int):
    if not OUTPUT_BASE.exists():
        print("Output dir does not exist, nothing to purge.", flush=True)
        return
    purged = 0
    for d in sorted(OUTPUT_BASE.iterdir()):
        if not d.is_dir():
            continue
        if d.name.startswith(f"{year}_") or re.match(rf"^{year}-\d{{2}}_", d.name):
            shutil.rmtree(d)
            print(f"  Removed: {d.name}", flush=True)
            purged += 1
    print(f"Purged {purged} director{'y' if purged == 1 else 'ies'} for {year}.", flush=True)


def main():
    parser = argparse.ArgumentParser(description="Generate or purge Divinum Officium EPUBs.")
    parser.add_argument("--year", type=int, default=None,
                        help="Year to generate (default: current year)")
    parser.add_argument("--purge-year", type=int, dest="purge_year", default=None,
                        help="Delete all output directories for this year")
    args = parser.parse_args()

    if args.purge_year is not None:
        purge_year(args.purge_year)
    else:
        generate_year(args.year if args.year is not None else datetime.now().year)


if __name__ == "__main__":
    main()
