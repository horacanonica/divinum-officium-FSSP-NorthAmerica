#!/usr/bin/env python3
"""Generate the annual supplement bundle from DO Fork Kalendaria files.

Calls EofficiumXhtml.pl for each feast in the custom parish calendars and
assembles the HTML output into a single JSON bundle, uploaded to GitHub Releases.

Usage:
  python3 generate_supplement.py [YEAR]
  YEAR defaults to next year if run in November, otherwise current year.
"""

import subprocess
import json
import re
import os
import sys
from datetime import date
from urllib.parse import quote

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KALENDARIA_DIR = os.path.join(REPO_ROOT, "web", "www", "Tabulae", "Kalendaria")
EPUBGEN_DIR = os.path.join(REPO_ROOT, "standalone", "tools", "epubgen2")
EOFFICIUM = os.path.join(EPUBGEN_DIR, "EofficiumXhtml.pl")

# In Kalendaria files the rank field is the CLASS number (1=I class, 2=II class, 3=III class/Double)
# not the internal horas rank number (6=I class, 5=II class, 3=Double).
RANK_LABELS = {
    1: "I Class",
    2: "II Class",
    3: "Double (III Class)",
}

HORAS = ["Matutinum", "Laudes", "Prima", "Tertia", "Sexta", "Nona", "Vespera", "Completorium"]

# Calendars with custom Kalendaria files, in order of inheritance depth.
# source_label: how feasts from THIS file are labelled in output.
CALENDARS = {
    "Rubrics 1960 - Nashua": {
        "parent": "Rubrics 1960 - FSSP USA",
        "kalendaria": "Nashua.txt",
        "source_label": "Parish",
    },
    "Rubrics 1960 - Arlington": {
        "parent": "Rubrics 1960 - FSSP USA",
        "kalendaria": "Arlington.txt",
        "source_label": "Parish",
    },
    "Rubrics 1960 - Chesapeake": {
        "parent": "Rubrics 1960 - FSSP USA",
        "kalendaria": "Chesapeake.txt",
        "source_label": "Parish",
    },
    "Rubrics 1960 - Sacramento": {
        "parent": "Rubrics 1960 - FSSP USA",
        "kalendaria": "Sacramento.txt",
        "source_label": "Parish",
    },
    "Rubrics 1960 - Guadalajara": {
        "parent": "Rubrics 1960 - FSSP",
        "kalendaria": "Guadalajara.txt",
        "source_label": "Parish",
    },
}


def parse_kalendaria(filepath):
    """Return list of feast dicts from a Kalendaria .txt file."""
    feasts = []
    with open(filepath, encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("*"):
                continue
            parts = line.split("=")
            if len(parts) < 4:
                continue
            date_str = parts[0]          # MM-DD
            name = parts[2].strip() if len(parts) > 2 else ""
            rank_str = parts[3].strip() if len(parts) > 3 else "0"
            try:
                rank = int(rank_str)
            except ValueError:
                rank = 0
            feasts.append({
                "date": date_str,
                "name": name,
                "rank": rank,
                "rank_label": RANK_LABELS.get(rank, f"Rank {rank}"),
            })
    return feasts


def generate_hora_html(calendar_name, date_str, hora, year):
    """Call EofficiumXhtml.pl and return the HTML string."""
    month, day = date_str.split("-")
    date_param = f"{month}-{day}-{year}"
    version_enc = quote(calendar_name, safe="")
    query = (
        f"date1={date_param}&command=pray{hora}"
        f"&version={version_enc}&testmode=regular"
        f"&lang1=Latin&nofancychars=1"
    )
    try:
        result = subprocess.run(
            ["perl", EOFFICIUM, query],
            capture_output=True,
            text=True,
            cwd=EPUBGEN_DIR,
            timeout=120,
        )
        return result.stdout
    except subprocess.TimeoutExpired:
        return ""


def extract_body(html):
    """Extract content between <body> and </body> tags."""
    m = re.search(r"<body[^>]*>(.*?)</body>", html, re.DOTALL | re.IGNORECASE)
    if m:
        return m.group(1).strip()
    return html.strip()


def main():
    today = date.today()
    if len(sys.argv) > 1:
        year = int(sys.argv[1])
    else:
        year = today.year + 1 if today.month >= 11 else today.year

    print(f"Generating supplement bundle for liturgical year {year}", flush=True)

    bundle = {
        "generated": today.isoformat(),
        "year": year,
        "version": "1.0",
        "calendars": {},
    }

    for calendar_name, cal_info in CALENDARS.items():
        print(f"\n  Calendar: {calendar_name}", flush=True)
        kal_path = os.path.join(KALENDARIA_DIR, cal_info["kalendaria"])
        if not os.path.exists(kal_path):
            print(f"    WARNING: {kal_path} not found, skipping.", flush=True)
            continue

        feasts = parse_kalendaria(kal_path)
        feast_list = []

        for feast in feasts:
            print(f"    {feast['date']} — {feast['name']}", flush=True)
            horas_content = {}
            for hora in HORAS:
                print(f"      {hora}...", end=" ", flush=True)
                html = generate_hora_html(calendar_name, feast["date"], hora, year)
                horas_content[hora] = extract_body(html)
                print("done", flush=True)

            feast_list.append({
                "date": feast["date"],
                "name": feast["name"],
                "rank": feast["rank"],
                "rank_label": feast["rank_label"],
                "source": cal_info["source_label"],
                "horas": horas_content,
            })

        bundle["calendars"][calendar_name] = {
            "parent": cal_info["parent"],
            "feasts": feast_list,
        }

    out_path = os.path.join(REPO_ROOT, f"supplement-{year}.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(bundle, f, ensure_ascii=False)

    size_kb = os.path.getsize(out_path) // 1024
    print(f"\nBundle: {out_path} ({size_kb} KB)", flush=True)


if __name__ == "__main__":
    main()
