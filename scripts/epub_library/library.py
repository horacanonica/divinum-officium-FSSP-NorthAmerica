#!/usr/bin/env python3
"""Plan and build the public Divine Office EPUB library.

Calendars are discovered from web/www/Tabulae/data.txt. A version is published
when it is ``Rubrics 1960 - FSSP`` or its base chain reaches that version.
Region headings come from regions.tsv; a calendar with no row is listed under
Other, so a new data.txt row appears on the page without a code change.

Dependency rule
---------------
Each published calendar has a fingerprint of the files that can change its
Office text:

* shared files (the engine, the temporal cycle, commons, psalter, martyrology,
  transfer tables, and this generator) are in every fingerprint, so a change
  there rebuilds every calendar;
* the calendar's own Kalendaria file, plus the Kalendaria of each ancestor in
  data.txt, plus the Sancti files those calendars name, are in that calendar
  only. A Sacramento edit therefore does not rebuild Guadalajara, while an
  FSSP.txt edit rebuilds every calendar that inherits FSSP, and a USA1960.txt
  edit rebuilds FSSP USA and the apostolates that inherit it, not Guadalajara
  or Niagara (those inherit FSSP directly).

The rolling window is the current month through the same month two years
ahead. Each calendar-year job produces all twelve monthly EPUBs and the
full-year EPUB. Months outside the window are kept on the release so the
nightly job can advance the page without regenerating a year that is already
built. A year that leaves the window is deleted.

Fingerprints are stored per year. A run that finishes only some years of a
calendar does not mark the unfinished years as current.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import zipfile
from dataclasses import dataclass
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA_TXT = ROOT / "web" / "www" / "Tabulae" / "data.txt"
KALENDARIA_DIR = ROOT / "web" / "www" / "Tabulae" / "Kalendaria"
REGIONS_TSV = Path(__file__).resolve().parent / "regions.tsv"
EPUBGEN_DIR = ROOT / "standalone" / "tools" / "epubgen2"
EPUBGEN = EPUBGEN_DIR / "epubgen2.sh"

FSSP_VERSION = "Rubrics 1960 - FSSP"
RELEASE_TAG = "epub-library"
WINDOW_MONTHS = 24
MAX_JOBS = 48
OTHER_REGION = "Other"

# Office data that every calendar reads. Kalendaria and data.txt are not
# here: those are hashed per inheritance chain.
SHARED_DIRS = (
    "web/cgi-bin",
    "standalone/tools/epubgen2",
    "web/www/horas/Latin/Tempora",
    "web/www/horas/Latin/Commune",
    "web/www/horas/Latin/Psalterium",
    "web/www/horas/Latin/Martyrologium",
    "web/www/horas/Latin/Martyrologium1960",
    "web/www/horas/English/Tempora",
    "web/www/horas/English/Commune",
    "web/www/horas/English/Psalterium",
    "web/www/horas/English/Martyrologium",
    "web/www/horas/Ordinarium",
    "web/www/Tabulae/Tempora",
    "web/www/Tabulae/Transfer",
    "web/www/Tabulae/Stransfer",
)
SHARED_FILES = (
    "scripts/epub_library/library.py",
    "scripts/epub_library/cli.py",
)
SKIP_DIR_NAMES = {"output", "screenshots", "__pycache__", ".git"}

LANGS = ("Latin", "English")
SANCTI_DIRS = ("Sancti", "SanctiM")

_file_digest_cache: dict[str, str] = {}
_shared_digest: str | None = None


@dataclass(frozen=True)
class Version:
    name: str
    kalendar: str
    base: str
    row: str


@dataclass(frozen=True)
class Calendar:
    version: str
    slug: str
    name: str
    kalendar: str
    region: str
    place: str
    chain: tuple[str, ...]


@dataclass(frozen=True)
class Window:
    start: str  # YYYY-MM
    end: str
    years: tuple[int, ...]

    def as_dict(self) -> dict:
        return {"start": self.start, "end": self.end, "years": list(self.years)}


def _rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def load_versions(path: Path | None = None) -> dict[str, Version]:
    """First row for each version name wins (later missa aliases are ignored)."""
    versions: dict[str, Version] = {}
    text = (path or DATA_TXT).read_text(encoding="utf-8", errors="replace")
    for line in text.splitlines():
        raw = line.strip()
        if not raw or raw.startswith("#") or raw.startswith("version,"):
            continue
        parts = [p.strip() for p in raw.split(",")]
        name = parts[0]
        if not name or name in versions:
            continue
        kalendar = parts[1] if len(parts) > 1 else ""
        base = parts[4] if len(parts) > 4 else ""
        versions[name] = Version(name, kalendar, base, raw)
    return versions


def chain_of(name: str, versions: dict[str, Version]) -> tuple[str, ...]:
    out: list[str] = []
    seen: set[str] = set()
    cur = name
    while cur and cur not in seen and cur in versions:
        seen.add(cur)
        out.append(cur)
        cur = versions[cur].base
    return tuple(out)


def inherits_fssp(name: str, versions: dict[str, Version]) -> bool:
    return FSSP_VERSION in chain_of(name, versions)


def slugify(name: str) -> str:
    slug = name.lower().replace("&", " and ")
    slug = re.sub(r"[^a-z0-9]+", "-", slug).strip("-")
    return slug


def load_regions(path: Path | None = None) -> tuple[list[str], dict[str, tuple[str, str]]]:
    order = [
        "General",
        "West",
        "South Central",
        "Southeast",
        "Northeast & Mid-Atlantic",
        "Midwest",
        "Canada",
        "Mexico",
        OTHER_REGION,
    ]
    places: dict[str, tuple[str, str]] = {}
    text = (path or REGIONS_TSV).read_text(encoding="utf-8")
    for line in text.splitlines():
        if line.startswith("# region_order:"):
            order = [part.strip() for part in line.split(":", 1)[1].split("|") if part.strip()]
            if OTHER_REGION not in order:
                order.append(OTHER_REGION)
            continue
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2 or parts[0].strip() == "version":
            continue
        version = parts[0].strip()
        region = parts[1].strip() or OTHER_REGION
        place = parts[2].strip() if len(parts) > 2 else ""
        places[version] = (region, place)
    return order, places


def load_calendars(
    versions: dict[str, Version] | None = None,
    regions_path: Path | None = None,
) -> tuple[list[Calendar], list[str]]:
    versions = versions if versions is not None else load_versions()
    order, places = load_regions(regions_path)
    calendars: list[Calendar] = []
    used_slugs: set[str] = set()
    for name, version in versions.items():
        if not inherits_fssp(name, versions):
            continue
        display = name.split(" - ", 1)[1] if " - " in name else name
        slug = slugify(display)
        if slug in used_slugs:
            slug = slugify(display + "-" + version.kalendar)
        used_slugs.add(slug)
        region, place = places.get(name, (OTHER_REGION, ""))
        calendars.append(
            Calendar(
                version=name,
                slug=slug,
                name=display,
                kalendar=version.kalendar,
                region=region,
                place=place,
                chain=chain_of(name, versions),
            )
        )

    def sort_key(cal: Calendar) -> tuple:
        try:
            region_index = order.index(cal.region)
        except ValueError:
            region_index = len(order)
        return (region_index, cal.name.lower())

    calendars.sort(key=sort_key)
    return calendars, order


def rolling_window(today: date | None = None, months_ahead: int = WINDOW_MONTHS) -> Window:
    today = today or date.today()
    start_index = today.year * 12 + (today.month - 1)
    end_index = start_index + months_ahead
    start = date(start_index // 12, start_index % 12 + 1, 1)
    end = date(end_index // 12, end_index % 12 + 1, 1)
    years = tuple(range(start.year, end.year + 1))
    return Window(f"{start.year:04d}-{start.month:02d}", f"{end.year:04d}-{end.month:02d}", years)


def _skip_path(path: Path) -> bool:
    return any(part in SKIP_DIR_NAMES or part.startswith("output_") for part in path.parts)


def iter_shared_files() -> list[str]:
    found: list[str] = []
    for rel in SHARED_DIRS:
        root = ROOT / rel
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if not path.is_file() or _skip_path(path):
                continue
            found.append(_rel(path))
    for rel in SHARED_FILES:
        path = ROOT / rel
        if path.is_file():
            found.append(rel)
    return sorted(set(found))


def shared_path(rel: str) -> bool:
    rel = rel.replace("\\", "/").lstrip("./")
    if rel in SHARED_FILES:
        return True
    for prefix in SHARED_DIRS:
        if rel == prefix or rel.startswith(prefix + "/"):
            return True
    return False


def kalendaria_refs(text: str) -> set[str]:
    refs: set[str] = set()
    for line in text.splitlines():
        raw = line.strip()
        if not raw or raw.startswith("#") or raw.startswith("*"):
            continue
        parts = raw.split("=")
        if len(parts) < 2:
            continue
        for token in parts[1].split("~"):
            token = token.strip()
            if token and token != "XXXXX":
                refs.add(token)
    return refs


def sancti_files(ref: str) -> list[str]:
    found = []
    for lang in LANGS:
        for folder in SANCTI_DIRS:
            rel = f"web/www/horas/{lang}/{folder}/{ref}.txt"
            if (ROOT / rel).is_file():
                found.append(rel)
    return found


def chain_files(cal: Calendar, versions: dict[str, Version] | None = None) -> list[str]:
    versions = versions if versions is not None else load_versions()
    found: set[str] = set()
    for name in cal.chain:
        version = versions.get(name)
        if version is None or not version.kalendar:
            continue
        rel = f"web/www/Tabulae/Kalendaria/{version.kalendar}.txt"
        path = ROOT / rel
        if not path.is_file():
            continue
        found.add(rel)
        for ref in kalendaria_refs(path.read_text(encoding="utf-8", errors="replace")):
            found.update(sancti_files(ref))
    return sorted(found)


def chain_rows(
    cal: Calendar,
    versions: dict[str, Version] | None = None,
    row_overrides: dict[str, str] | None = None,
) -> list[str]:
    versions = versions if versions is not None else load_versions()
    row_overrides = row_overrides or {}
    rows = []
    for name in cal.chain:
        if name in row_overrides:
            rows.append(row_overrides[name])
        elif name in versions:
            rows.append(versions[name].row)
    return rows


def _digest_bytes(key: str, data: bytes) -> str:
    cached = _file_digest_cache.get(key)
    if cached is not None and not key.startswith("override:"):
        return cached
    digest = hashlib.sha256()
    digest.update(key.encode())
    digest.update(b"\0")
    digest.update(data)
    value = digest.hexdigest()
    if not key.startswith("override:"):
        _file_digest_cache[key] = value
    return value


def _digest_file(rel: str, overrides: dict[str, bytes] | None = None) -> str:
    if overrides and rel in overrides:
        return _digest_bytes("override:" + rel, overrides[rel])
    cached = _file_digest_cache.get(rel)
    if cached is not None:
        return cached
    data = (ROOT / rel).read_bytes()
    return _digest_bytes(rel, data)


def shared_digest(overrides: dict[str, bytes] | None = None) -> str:
    global _shared_digest
    if overrides:
        digest = hashlib.sha256()
        for rel in iter_shared_files():
            digest.update(_digest_file(rel, overrides).encode())
        return digest.hexdigest()
    if _shared_digest is None:
        digest = hashlib.sha256()
        for rel in iter_shared_files():
            digest.update(_digest_file(rel).encode())
        _shared_digest = digest.hexdigest()
    return _shared_digest


def content_hash(
    cal: Calendar,
    versions: dict[str, Version] | None = None,
    file_overrides: dict[str, bytes] | None = None,
    row_overrides: dict[str, str] | None = None,
) -> str:
    versions = versions if versions is not None else load_versions()
    digest = hashlib.sha256()
    digest.update(shared_digest(file_overrides).encode())
    for rel in chain_files(cal, versions):
        digest.update(_digest_file(rel, file_overrides).encode())
    for row in chain_rows(cal, versions, row_overrides):
        digest.update(row.encode())
        digest.update(b"\0")
    return digest.hexdigest()


def affected_slugs(paths: list[str], calendars: list[Calendar] | None = None) -> set[str]:
    """Slugs whose Office text can change because one of ``paths`` changed.

    An empty result means none of the published calendars. Callers that do
    not have a path list should not call this; the nightly job uses fingerprints
    instead.
    """
    calendars = calendars if calendars is not None else load_calendars()[0]
    versions = load_versions()
    all_slugs = {cal.slug for cal in calendars}
    owners_of_kalendar: dict[str, set[str]] = {}
    owners_of_ref: dict[str, set[str]] = {}
    for cal in calendars:
        for name in cal.chain:
            version = versions.get(name)
            if version is None:
                continue
            owners_of_kalendar.setdefault(version.kalendar, set()).add(cal.slug)
            rel = f"web/www/Tabulae/Kalendaria/{version.kalendar}.txt"
            path = ROOT / rel
            if path.is_file():
                for ref in kalendaria_refs(path.read_text(encoding="utf-8", errors="replace")):
                    owners_of_ref.setdefault(ref, set()).add(cal.slug)

    selected: set[str] = set()
    for raw in paths:
        rel = raw.replace("\\", "/").lstrip("./")
        if not rel or rel.startswith("docs/") or rel.startswith(".github/"):
            continue
        if shared_path(rel):
            return set(all_slugs)
        if rel == "web/www/Tabulae/data.txt":
            # Which rows changed is decided by the per-chain fingerprint.
            # Marking every calendar affected is safe: unchanged fingerprints
            # still skip the build.
            return set(all_slugs)
        if rel.startswith("web/www/Tabulae/Kalendaria/") and rel.endswith(".txt"):
            code = Path(rel).stem
            selected |= owners_of_kalendar.get(code, set())
            continue
        if "/Sancti" in rel and rel.endswith(".txt"):
            selected |= owners_of_ref.get(Path(rel).stem, set())
            continue
    return selected


def load_catalog(path: Path) -> dict:
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def _files_for_year(files: list[dict], year: int) -> list[dict]:
    return [item for item in files if int(item.get("year", 0)) == year]


def year_complete(files: list[dict], year: int) -> bool:
    have = {(item.get("type"), int(item.get("month") or 0)) for item in _files_for_year(files, year)}
    if ("year", 0) not in have:
        return False
    return all(("month", month) in have for month in range(1, 13))


def plan_jobs(
    calendars: list[Calendar],
    catalog: dict,
    window: Window,
    hashes: dict[str, str],
    *,
    affected: set[str] | None = None,
    force_slugs: set[str] | None = None,
    max_jobs: int = MAX_JOBS,
) -> list[dict]:
    """Return calendar-year jobs that are missing or fingerprint-stale.

    ``affected`` limits a push to calendars the diff can change. A calendar
    that has never been built is still queued, so the first push fills the
    library and a later push still finishes anything the nightly job missed.
    ``affected is None`` (the nightly run) considers every calendar.
    """
    force_slugs = force_slugs or set()
    by_slug = {item.get("slug"): item for item in catalog.get("calendars", [])}
    jobs: list[dict] = []
    for cal in calendars:
        entry = by_slug.get(cal.slug) or {}
        files = entry.get("files") or []
        built = {str(key): value for key, value in (entry.get("built") or {}).items()}
        never = not files
        if affected is not None and cal.slug not in affected and not never and cal.slug not in force_slugs:
            continue
        current = hashes[cal.slug]
        for year in window.years:
            stale = (
                cal.slug in force_slugs
                or built.get(str(year)) != current
                or not year_complete(files, year)
            )
            if not stale:
                continue
            jobs.append(
                {
                    "slug": cal.slug,
                    "year": year,
                    "version": cal.version,
                }
            )
            if len(jobs) >= max_jobs:
                return jobs
    return jobs


def classify_generated(name: str, year: int) -> tuple[str, int | None] | None:
    month_match = re.search(r"breviarium(\d{4})-(\d{2})", name)
    if month_match and int(month_match.group(1)) == year:
        return ("month", int(month_match.group(2)))
    year_match = re.search(r"breviarium(\d{4})(?!\d)", name)
    if year_match and int(year_match.group(1)) == year:
        return ("year", None)
    return None


def _validate_epub(path: Path, kind: str) -> None:
    if path.stat().st_size < (2_000_000 if kind == "year" else 200_000):
        raise RuntimeError(f"{path.name} is unexpectedly small ({path.stat().st_size} bytes)")
    with zipfile.ZipFile(path) as archive:
        bad = archive.testzip()
        if bad:
            raise RuntimeError(f"{path.name} has a corrupt entry: {bad}")
        names = archive.namelist()
        if "mimetype" not in names or "content.opf" not in names:
            raise RuntimeError(f"{path.name} is missing epub structure")
        html_count = sum(1 for name in names if name.endswith(".html") or name.endswith(".xhtml"))
        minimum = 2500 if kind == "year" else 200
        if html_count < minimum:
            raise RuntimeError(f"{path.name} has {html_count} html files, expected at least {minimum}")


def build_year(cal: Calendar, year: int, output: Path, versions: dict[str, Version] | None = None) -> dict:
    """Run epubgen2 for one calendar-year and write stable filenames."""
    output.mkdir(parents=True, exist_ok=True)
    raw = output / "_raw"
    if raw.exists():
        for child in raw.iterdir():
            if child.is_file():
                child.unlink()
    raw.mkdir(parents=True, exist_ok=True)
    code = cal.version.split(" - ", 1)[1] if " - " in cal.version else cal.version
    env = os.environ.copy()
    env["LC_ALL"] = "C.UTF-8"
    env["LANG"] = "C.UTF-8"
    cmd = [
        str(EPUBGEN),
        "-y",
        str(year),
        "-t",
        str(year),
        "-r",
        code,
        "-b",
        "Latin",
        "-l",
        "English",
        "-o",
        str(raw),
    ]
    log_path = output / "epubgen.log"
    print(f"Building {cal.version} {year}", flush=True)
    with log_path.open("w", encoding="utf-8", errors="replace") as log:
        try:
            proc = subprocess.run(
                cmd,
                cwd=str(EPUBGEN_DIR),
                env=env,
                stdout=log,
                stderr=subprocess.STDOUT,
                timeout=40 * 60,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError(f"epubgen2 timed out for {cal.slug} {year}") from exc
    if proc.returncode != 0:
        tail = log_path.read_text(encoding="utf-8", errors="replace")[-4000:]
        raise RuntimeError(f"epubgen2 failed for {cal.slug} {year} (exit {proc.returncode})\n{tail}")

    produced = sorted(path for path in raw.glob("*.epub"))
    files: list[dict] = []
    seen_months: set[int] = set()
    saw_year = False
    for source in produced:
        kind = classify_generated(source.name, year)
        if kind is None:
            continue
        file_kind, month = kind
        if file_kind == "month":
            dest_name = f"{cal.slug}-{year}-{month:02d}.epub"
            seen_months.add(month)
        else:
            dest_name = f"{cal.slug}-{year}.epub"
            saw_year = True
        dest = output / dest_name
        dest.write_bytes(source.read_bytes())
        _validate_epub(dest, file_kind)
        record = {"type": file_kind, "year": year, "name": dest_name, "bytes": dest.stat().st_size}
        if month is not None:
            record["month"] = month
        files.append(record)
    missing = [month for month in range(1, 13) if month not in seen_months]
    if missing or not saw_year:
        raise RuntimeError(f"{cal.slug} {year} did not produce every EPUB (missing months {missing}, year={saw_year})")
    files.sort(key=lambda item: (item["type"] != "year", item.get("month") or 0))
    fragment = {
        "version": cal.version,
        "slug": cal.slug,
        "year": year,
        "content_hash": content_hash(cal, versions),
        "files": files,
    }
    (output / "fragment.json").write_text(json.dumps(fragment, indent=2) + "\n", encoding="utf-8")
    log_path.unlink(missing_ok=True)
    return fragment


def _blank_entry(cal: Calendar) -> dict:
    return {
        "version": cal.version,
        "slug": cal.slug,
        "name": cal.name,
        "region": cal.region,
        "place": cal.place,
        "built": {},
        "files": [],
    }


def merge_catalog(
    old: dict,
    calendars: list[Calendar],
    region_order: list[str],
    window: Window,
    fragments: list[dict],
    *,
    repo: str,
    updated: str,
) -> dict:
    by_slug: dict[str, dict] = {}
    for item in old.get("calendars", []):
        slug = item.get("slug")
        if slug:
            by_slug[slug] = {
                "built": {str(key): value for key, value in (item.get("built") or {}).items()},
                "files": list(item.get("files") or []),
            }
    for fragment in fragments:
        slug = fragment["slug"]
        year = str(fragment["year"])
        entry = by_slug.setdefault(slug, {"built": {}, "files": []})
        entry["built"][year] = fragment["content_hash"]
        entry["files"] = [item for item in entry["files"] if int(item.get("year", 0)) != int(year)]
        entry["files"].extend(fragment["files"])

    window_years = set(window.years)
    published: list[dict] = []
    for cal in calendars:
        previous = by_slug.get(cal.slug, {"built": {}, "files": []})
        files = [item for item in previous["files"] if int(item.get("year", 0)) in window_years]
        files.sort(key=lambda item: (int(item["year"]), 0 if item["type"] == "year" else int(item.get("month") or 0)))
        built = {
            year: digest
            for year, digest in previous["built"].items()
            if year.isdigit() and int(year) in window_years
        }
        entry = _blank_entry(cal)
        entry["built"] = built
        entry["files"] = files
        published.append(entry)

    catalog = {
        "repo": repo,
        "release": RELEASE_TAG,
        "updated": updated,
        "languages": "Latin and English",
        "rubrics": "1960",
        "window": window.as_dict(),
        "region_order": region_order,
        "calendars": published,
    }
    return catalog


def catalog_signature(catalog: dict) -> str:
    """Compare catalogs without the timestamp, so a no-op night does not commit."""
    body = {key: value for key, value in catalog.items() if key != "updated"}
    return json.dumps(body, sort_keys=True, ensure_ascii=False)


def write_catalog(path: Path, catalog: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def assets_to_prune(catalog: dict, remote_names: list[str]) -> list[str]:
    """Release assets for calendars or years the page no longer publishes."""
    calendars = catalog.get("calendars") or []
    if not calendars:
        return []
    slugs = {item["slug"] for item in calendars}
    years = set(catalog.get("window", {}).get("years") or [])
    doomed = []
    for name in remote_names:
        if not name.endswith(".epub"):
            continue
        match = re.match(r"^(.+)-(\d{4})(?:-\d{2})?\.epub$", name)
        if not match:
            continue
        slug, year = match.group(1), int(match.group(2))
        if slug not in slugs or year not in years:
            doomed.append(name)
    return sorted(doomed)


def rubrics_code(cal: Calendar) -> str:
    return cal.version.split(" - ", 1)[1] if " - " in cal.version else cal.version
