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
  transfer tables, and epubgen2) are in every fingerprint, so a change
  there rebuilds every calendar;
* the calendar's own Kalendaria file, plus the Kalendaria of each ancestor in
  data.txt, plus the Sancti files those calendars name, are in that calendar
  only. A Sacramento edit therefore does not rebuild Guadalajara, while an
  FSSP.txt edit rebuilds every calendar that inherits FSSP, and a USA1960.txt
  edit rebuilds FSSP USA and the apostolates that inherit it, not Guadalajara
  or Niagara (those inherit FSSP directly).

The rolling window is the current month through the same month two years
ahead. Each job produces one full-year EPUB for one calendar-year. Monthly
files are not published, for Latin or for any later edition. A calendar edit
rebuilds that calendar; a shared Office edit rebuilds every calendar.

Published names are ``{calendar}-{year}-la.epub`` on the ``epub-library-la``
release. Latin is the only edition.

Before any of those files are compiled, ``missing_vernacular`` checks the
calendars this pipeline publishes. A location that has a proper of its own
needs that proper in each planned vernacular language (English, Spanish,
French). A location that only points at the commons is skipped. The workflow
prints every gap and still builds the Latin years that are available.

Fingerprints are stored per year. A run that finishes only some years does
not mark the unfinished years as current.
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
RELEASE_TAG = "epub-library-la"
RELEASES = {"la": RELEASE_TAG}
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
# The planner and the download page are not part of the fingerprint. A change
# there must not rebuild every EPUB. epubgen2.sh and the Office texts are.
SHARED_FILES = ()
FINGERPRINT_VERSION = "v2"
SKIP_DIR_NAMES = {"output", "screenshots", "__pycache__", ".git"}

LANGS = ("Latin", "English")
SANCTI_DIRS = ("Sancti", "SanctiM")

# Latin is the only published edition.
VARIANTS = ("la",)
# Planned vernacular editions. Latin is the source text and is not listed:
# a missing Latin file is not a vernacular gap. Folder names are
# web/www/horas/<folder>. The second field is the name printed when a file
# is missing. A new language is a new row. Every published calendar is
# checked against this table, so a new location needs no extra code.
VERNACULAR_LANGS = (
    ("English", "English"),
    ("Espanol", "Spanish"),
    ("Francais", "French"),
)
VARIANT_SUFFIX = {"la": "-la"}
# The optional suffix also matches retired unsuffixed and -la-en names so a
# stray bilingual file on the release can be pruned. Nothing generates them.
_ASSET_RE = re.compile(
    r"^(?P<slug>.+)-(?P<year>\d{4})(?:-(?P<month>\d{2}))?(?:-(?P<variant>la-en|la))?\.epub$"
)

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
    feasts: tuple = ()


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


def _flags(cell: str) -> set[str]:
    return {part.strip().lower() for part in cell.split(",") if part.strip()}


def load_hidden(path: Path | None = None) -> set[str]:
    """Versions marked ``hidden`` in regions.tsv: not listed or built.

    Used where a generated calendar duplicates an older hand-written one for
    the same place. The generated version still works on the website.
    """
    found: set[str] = set()
    for line in (path or REGIONS_TSV).read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) > 3 and "hidden" in _flags(parts[3]):
            found.add(parts[0].strip())
    return found


def load_titles(path: Path | None = None) -> dict[str, str]:
    """Display names from the fifth regions.tsv column (parish and city)."""
    found: dict[str, str] = {}
    for line in (path or REGIONS_TSV).read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) > 4 and parts[4].strip():
            found[parts[0].strip()] = parts[4].strip()
    return found


SANCTI_DIR = ROOT / "web" / "www" / "horas" / "Latin" / "Sancti"
_CLASS_NAMES = {"1": "I", "2": "II", "3": "III", "4": "IV"}


def _feast_kind(date_key: str, ref: str) -> str:
    """proper | elevated | class changed, from the first line of the Sancti file."""
    path = SANCTI_DIR / f"{ref}.txt"
    text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
    if text.startswith("@Sancti/"):
        return "elevated"
    if ref == date_key:
        return "class changed"
    return "proper"


def _layer_name(kalendar: str) -> str:
    if kalendar == "FSSP":
        return "FSSP"
    if kalendar.startswith("USA"):
        return "United States"
    if kalendar.startswith("CAN"):
        return "Canada"
    if kalendar.startswith("Dio"):
        return "Diocese"
    if kalendar.startswith("Site"):
        return "Parish"
    return "This calendar"


# Download-page order, most local first. A new Site* or Dio* calendar picks
# up its place from the kalendar prefix; a hand-written kalendar is "This
# calendar" and stays with the parish. Keep docs/downloads.js in step.
_LAYER_RANK = {
    "Parish": 0,
    "This calendar": 0,
    "Diocese": 1,
    "FSSP": 2,
    "Canada": 3,
    "United States": 3,
}


def layer_display_rank(layer: str) -> int:
    """Parish and diocese, then FSSP, then the country. Unknown layers stay local."""
    return _LAYER_RANK.get(layer, 0)


def calendar_feasts(chain: tuple[str, ...], versions: dict[str, Version]) -> tuple:
    """Local feasts grouped parish, diocese, FSSP, then country.

    A nearer layer still replaces a farther one on the same date. The winning
    layer is the liturgical one; the list order is only how the download page
    groups them.
    """
    layers = []
    for name in chain:
        layers.append(name)
        if name == FSSP_VERSION:
            break
    layers.reverse()
    taken: dict[str, int] = {}
    found: list[dict] = []
    for index, name in enumerate(layers):
        kal = versions[name].kalendar
        path = KALENDARIA_DIR / f"{kal}.txt"
        if not path.exists():
            continue
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith(("#", "*")) or "=" not in line:
                continue
            parts = line.split("=")
            if len(parts) < 4 or not re.fullmatch(r"\d\d-\d\d", parts[0]):
                continue
            ref = parts[1].split("~")[0]
            found.append(
                {
                    "layer": _layer_name(kal),
                    "date": parts[0],
                    "name": parts[2],
                    "class": _CLASS_NAMES.get(parts[3], parts[3]),
                    "kind": _feast_kind(parts[0], ref),
                    "_order": index,
                }
            )
            taken[parts[0]] = index
    kept = [f for f in found if taken[f["date"]] == f["_order"]]
    kept.sort(key=lambda f: (layer_display_rank(f["layer"]), f["layer"], f["date"]))
    for f in kept:
        del f["_order"]
    return tuple(kept)


def load_calendars(
    versions: dict[str, Version] | None = None,
    regions_path: Path | None = None,
) -> tuple[list[Calendar], list[str]]:
    versions = versions if versions is not None else load_versions()
    order, places = load_regions(regions_path)
    titles = load_titles(regions_path)
    hidden = load_hidden(regions_path)
    calendars: list[Calendar] = []
    used_slugs: set[str] = set()
    for name, version in versions.items():
        if not inherits_fssp(name, versions) or name in hidden:
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
                name=titles.get(name, display),
                kalendar=version.kalendar,
                region=region,
                place=place,
                chain=chain_of(name, versions),
                feasts=calendar_feasts(chain_of(name, versions), versions),
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


def file_variant(item: dict) -> str | None:
    """``la`` for a Latin catalog file. Anything else is not published."""
    if item.get("variant") == "la":
        return "la"
    name = item.get("name") or ""
    if isinstance(name, str) and name.endswith("-la.epub"):
        return "la"
    return None


def asset_name(slug: str, year: int, month: int | None, variant: str = "la") -> str:
    suffix = VARIANT_SUFFIX[variant]
    if month is None:
        return f"{slug}-{year}{suffix}.epub"
    return f"{slug}-{year}-{month:02d}{suffix}.epub"


def year_complete(files: list[dict], year: int, variant: str = "la") -> bool:
    """True when the full-year EPUB for this year is present.

    Monthly files do not count. A year is one file, for every edition.
    """
    for item in files:
        if int(item.get("year") or 0) != int(year):
            continue
        if file_variant(item) != variant:
            continue
        if item.get("type") == "year":
            return True
    return False


def _stamp_map(value) -> dict[str, str]:
    """Latin fingerprint for one year. A bilingual stamp is ignored."""
    if isinstance(value, dict):
        item = value.get("la")
        if isinstance(item, str) and item:
            return {"la": item}
    return {}


def variant_fresh(
    files: list[dict],
    year: int,
    stamp_value,
    variant: str,
    current: str,
    *,
    adopt_complete: bool = False,
) -> bool:
    """True when this year's full-year file is present and matches the fingerprint.

    The first catalog written by this version also keeps complete years, then
    records the current fingerprint so a later Office edit still rebuilds them.
    """
    if not year_complete(files, year, variant):
        return False
    if adopt_complete:
        return True
    return _stamp_map(stamp_value).get(variant) == current


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
    """Return Latin jobs that are missing or fingerprint-stale.

    ``affected`` limits a content rebuild to calendars the diff can change.
    A year that has never been built is still queued, so a later push finishes
    what an earlier run left behind. ``affected is None`` (the nightly run)
    considers every calendar. Calendars keep their region order.
    """
    force_slugs = force_slugs or set()
    adopt_complete = catalog.get("fingerprint") != FINGERPRINT_VERSION
    by_slug = {item.get("slug"): item for item in catalog.get("calendars", [])}
    priority: list[tuple[int, int, int, dict]] = []
    gaps: list[tuple[int, int, int, dict]] = []
    for order, cal in enumerate(calendars):
        entry = by_slug.get(cal.slug) or {}
        files = entry.get("files") or []
        built = entry.get("built") or {}
        current = hashes[cal.slug]
        in_scope = affected is None or cal.slug in affected or cal.slug in force_slugs
        for year in window.years:
            stamp_value = built.get(str(year))
            for variant_index, variant in enumerate(VARIANTS):
                forced = cal.slug in force_slugs
                if not forced and variant_fresh(
                    files, year, stamp_value, variant, current, adopt_complete=adopt_complete
                ):
                    continue
                incomplete = not year_complete(files, year, variant)
                if not in_scope and not incomplete:
                    continue
                job = {
                    "slug": cal.slug,
                    "year": year,
                    "version": cal.version,
                    "variant": variant,
                }
                bucket = priority if in_scope or forced else gaps
                bucket.append((variant_index, order, year, job))
    priority.sort(key=lambda item: (item[0], item[1], item[2]))
    gaps.sort(key=lambda item: (item[0], item[1], item[2]))
    return [item[3] for item in priority + gaps][:max_jobs]


def classify_generated(name: str, year: int) -> tuple[str, int | None] | None:
    month_match = re.search(r"breviarium(\d{4})-(\d{2})", name)
    if month_match and int(month_match.group(1)) == year:
        return ("month", int(month_match.group(2)))
    year_match = re.search(r"breviarium(\d{4})(?!\d)", name)
    if year_match and int(year_match.group(1)) == year:
        return ("year", None)
    return None


def _validate_epub(path: Path) -> None:
    minimum_bytes = 1_000_000
    if path.stat().st_size < minimum_bytes:
        raise RuntimeError(f"{path.name} is unexpectedly small ({path.stat().st_size} bytes)")
    with zipfile.ZipFile(path) as archive:
        bad = archive.testzip()
        if bad:
            raise RuntimeError(f"{path.name} has a corrupt entry: {bad}")
        names = archive.namelist()
        if "mimetype" not in names or "content.opf" not in names:
            raise RuntimeError(f"{path.name} is missing epub structure")
        html_count = sum(1 for name in names if name.endswith(".html") or name.endswith(".xhtml"))
        minimum = 2500
        if html_count < minimum:
            raise RuntimeError(f"{path.name} has {html_count} html files, expected at least {minimum}")
        opf = archive.read("content.opf").decode("utf-8", errors="replace")
        if "<dc:language>la</dc:language>" not in opf:
            raise RuntimeError(f"{path.name} is missing the Latin language")
        if "<dc:language>en</dc:language>" in opf:
            raise RuntimeError(f"{path.name} includes English; expected Latin only")


def build_year(
    cal: Calendar,
    year: int,
    output: Path,
    versions: dict[str, Version] | None = None,
    variant: str = "la",
) -> dict:
    """Run epubgen2 for one Latin calendar-year and write stable filenames."""
    if variant != "la":
        raise RuntimeError(f"Unknown EPUB variant {variant}")
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
        "Latin",
        "-o",
        str(raw),
    ]
    log_path = output / "epubgen.log"
    print(f"Building {cal.version} {year} ({variant})", flush=True)
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
    saw_year = False
    for source in produced:
        kind = classify_generated(source.name, year)
        if kind is None or kind[0] != "year":
            continue
        dest_name = asset_name(cal.slug, year, None, variant)
        saw_year = True
        dest = output / dest_name
        dest.write_bytes(source.read_bytes())
        _validate_epub(dest)
        files.append(
            {
                "type": "year",
                "year": year,
                "name": dest_name,
                "bytes": dest.stat().st_size,
                "variant": variant,
            }
        )
    if not saw_year:
        raise RuntimeError(f"{cal.slug} {year} did not produce a full-year EPUB")
    fragment = {
        "version": cal.version,
        "slug": cal.slug,
        "year": year,
        "variant": variant,
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
        "feasts": list(cal.feasts),
    }


def _current_hash(cal: Calendar, versions: dict[str, Version], cache: dict[str, str]) -> str:
    cached = cache.get(cal.slug)
    if cached is None:
        cached = content_hash(cal, versions)
        cache[cal.slug] = cached
    return cached


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
    versions = load_versions()
    hash_cache: dict[str, str] = {}
    adopting = old.get("fingerprint") != FINGERPRINT_VERSION
    refreshed: set[tuple[str, str, str]] = set()
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
        variant = fragment.get("variant") or "la"
        if variant not in VARIANTS:
            continue
        entry = by_slug.setdefault(slug, {"built": {}, "files": []})
        stamps = _stamp_map(entry["built"].get(year))
        stamps[variant] = fragment["content_hash"]
        refreshed.add((slug, year, variant))
        entry["built"][year] = stamps
        entry["files"] = [
            item
            for item in entry["files"]
            if not (int(item.get("year") or 0) == int(year) and file_variant(item) == variant)
        ]
        for item in fragment["files"]:
            tagged = dict(item)
            tagged["variant"] = variant
            entry["files"].append(tagged)

    window_years = set(window.years)
    published: list[dict] = []
    for cal in calendars:
        previous = by_slug.get(cal.slug, {"built": {}, "files": []})
        files = [
            item
            for item in previous["files"]
            if int(item.get("year") or 0) in window_years
            and file_variant(item) in VARIANTS
            and item.get("type") == "year"
        ]
        files.sort(
            key=lambda item: (
                int(item["year"]),
                0 if item["type"] == "year" else int(item.get("month") or 0),
            )
        )
        built: dict[str, dict[str, str]] = {}
        for year in window.years:
            stamps = _stamp_map(previous["built"].get(str(year)))
            if adopting:
                for variant in VARIANTS:
                    if (cal.slug, str(year), variant) in refreshed:
                        continue
                    if year_complete(files, year, variant):
                        stamps[variant] = _current_hash(cal, versions, hash_cache)
            if stamps:
                built[str(year)] = stamps
        entry = _blank_entry(cal)
        entry["built"] = built
        entry["files"] = files
        published.append(entry)

    catalog = {
        "repo": repo,
        "release": RELEASE_TAG,
        "releases": dict(RELEASES),
        "updated": updated,
        "languages": "Latin",
        "variants": [{"id": "la", "label": "Latin"}],
        "fingerprint": FINGERPRINT_VERSION,
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


def parse_asset_name(name: str) -> tuple[str, int, str | None] | None:
    """Split a release filename into slug, year, and variant (None if unsuffixed)."""
    match = _ASSET_RE.match(name)
    if not match:
        return None
    return match.group("slug"), int(match.group("year")), match.group("variant")


def assets_to_prune(catalog: dict, remote_names: list[str]) -> list[str]:
    """Release assets the catalog no longer links to.

    A file leaves once its year is outside the window or its name is no longer
    listed. Monthly files, and retired unsuffixed and ``-la-en`` names, are
    removed the same way.
    """
    calendars = catalog.get("calendars") or []
    if not calendars:
        return []
    published: set[str] = set()
    for item in calendars:
        for file in item.get("files") or []:
            name = file.get("name")
            if name:
                published.add(name)
    doomed = []
    for name in remote_names:
        if not name.endswith(".epub") or name in published:
            continue
        if parse_asset_name(name) is None:
            continue
        doomed.append(name)
    return sorted(doomed)


def rubrics_code(cal: Calendar) -> str:
    return cal.version.split(" - ", 1)[1] if " - " in cal.version else cal.version


# Sections that name or rank an office. They are not a proper of its own:
# a commons file is only these, plus a rule that points at a commune.
_STRUCTURAL_SECTIONS = {"Officium", "Rank", "Rule", "Name", "Comment"}
_SECTION_SPLIT = re.compile(r"(?m)^\[([^\]]+)\][^\n]*\n?")
# @Sancti/02-22, and "ex Sancti/01-25" / "vide Sancti/01-25" (a pseudo-commune).
# Commune files (ex C8, vide C5) are not included.
_SANCTI_TARGET = re.compile(
    r"(?:@|(?:ex|vide)\s+)(SanctiM?)/([0-9A-Za-z][0-9A-Za-z-]*)",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class VernacularGap:
    """One location missing one planned language for one or more propers."""

    version: str
    slug: str
    name: str
    folder: str
    language: str
    refs: tuple[str, ...]

    def warning(self) -> str:
        return f"Missing {self.language} for {self.name}: {', '.join(self.refs)}"


@dataclass(frozen=True)
class PreflightResult:
    gaps: tuple[VernacularGap, ...]
    checked: int
    commons_only: int

    @property
    def locations_with_gaps(self) -> int:
        return len({gap.slug for gap in self.gaps})


def office_has_own_text(text: str) -> bool:
    """True when the office contains proper text, not only a commons shell.

    A commons file is a title, a rank, a rule such as ``vide C5`` or ``ex C8``,
    and sometimes a [Name]. An elevation that only redirects with ``@Sancti``
    has no text of its own either. A prayer, lesson, hymn, or antiphon does.
    """
    parts = _SECTION_SPLIT.split(text)
    for index in range(1, len(parts), 2):
        name = parts[index].strip()
        if name in _STRUCTURAL_SECTIONS:
            continue
        body = parts[index + 1] if index + 1 < len(parts) else ""
        if _body_has_prose(body):
            return True
    return False


def _body_has_prose(body: str) -> bool:
    for line in body.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith(("#", "@", "$", "&", "!")):
            continue
        return True
    return False


def sancti_targets(text: str) -> tuple[str, ...]:
    """Sancti refs this file redirects to. Commune ids are left out."""
    found: list[str] = []
    seen: set[str] = set()
    for match in _SANCTI_TARGET.finditer(text):
        ref = match.group(2)
        if ref not in seen:
            seen.add(ref)
            found.append(ref)
    return tuple(found)


def latin_office_text(ref: str, horas: Path | None = None) -> str | None:
    """Latin Sancti text for a kalendar ref. SanctiM is the fallback."""
    horas = horas if horas is not None else ROOT / "web" / "www" / "horas"
    for folder in ("Sancti", "SanctiM"):
        path = horas / "Latin" / folder / f"{ref}.txt"
        if path.is_file():
            return path.read_text(encoding="utf-8", errors="replace")
    return None


def vernacular_office_exists(folder: str, ref: str, horas: Path | None = None) -> bool:
    """True when this language has the proper in Sancti or SanctiM."""
    horas = horas if horas is not None else ROOT / "web" / "www" / "horas"
    for sancti in SANCTI_DIRS:
        if (horas / folder / sancti / f"{ref}.txt").is_file():
            return True
    return False


def own_kalendar_refs(cal: Calendar, kalendaria_dir: Path | None = None) -> set[str]:
    """Refs named by this calendar's own Kalendaria file, not its ancestors.

    A parish that only keeps a dedication does not inherit the duty to
    translate an FSSP proper. That proper is checked on the FSSP calendar.
    """
    kalendaria_dir = kalendaria_dir if kalendaria_dir is not None else KALENDARIA_DIR
    path = kalendaria_dir / f"{cal.kalendar}.txt"
    if not path.is_file():
        return set()
    return kalendaria_refs(path.read_text(encoding="utf-8", errors="replace"))


def proper_refs(
    ref: str,
    horas: Path | None = None,
    *,
    _memo: dict[str, set[str]] | None = None,
    _seen: set[str] | None = None,
) -> set[str]:
    """Files that hold this ref's proper text and therefore need a translation.

    A commons shell contributes nothing. A wrapper (``@Sancti/...`` or a rank
    file whose sections only point at another Sancti file) contributes the
    file it points at. A file with its own prayer or lesson contributes
    itself and is not walked further: hymns it includes belong to the
    general sanctoral, not to this location.
    """
    horas = horas if horas is not None else ROOT / "web" / "www" / "horas"
    memo = _memo if _memo is not None else {}
    if ref in memo:
        return memo[ref]
    seen = _seen if _seen is not None else set()
    if ref in seen:
        return set()
    seen.add(ref)
    text = latin_office_text(ref, horas)
    if text is None:
        memo[ref] = set()
        return memo[ref]
    if office_has_own_text(text):
        memo[ref] = {ref}
        return memo[ref]
    found: set[str] = set()
    for target in sancti_targets(text):
        found |= proper_refs(target, horas, _memo=memo, _seen=seen)
    memo[ref] = found
    return found


def missing_vernacular(
    calendars: list[Calendar],
    *,
    root: Path | None = None,
    langs: tuple[tuple[str, str], ...] | None = None,
) -> PreflightResult:
    """Vernacular propers missing for the calendars the EPUB build publishes.

    Commons-only locations are omitted. The result is a warning list: callers
    still build every Latin year that is available. ``langs`` defaults to
    ``VERNACULAR_LANGS``, so a new edition is picked up by adding a row there.
    """
    root = root or ROOT
    langs = langs if langs is not None else VERNACULAR_LANGS
    horas = root / "web" / "www" / "horas"
    kalendaria_dir = root / "web" / "www" / "Tabulae" / "Kalendaria"
    memo: dict[str, set[str]] = {}
    gaps: list[VernacularGap] = []
    commons_only = 0
    order = {folder: index for index, (folder, _name) in enumerate(langs)}
    for cal in calendars:
        needed: set[str] = set()
        for ref in own_kalendar_refs(cal, kalendaria_dir):
            needed |= proper_refs(ref, horas, _memo=memo)
        if not needed:
            commons_only += 1
            continue
        for folder, language in langs:
            missing = tuple(sorted(ref for ref in needed if not vernacular_office_exists(folder, ref, horas)))
            if missing:
                gaps.append(
                    VernacularGap(
                        version=cal.version,
                        slug=cal.slug,
                        name=cal.name,
                        folder=folder,
                        language=language,
                        refs=missing,
                    )
                )
    gaps.sort(key=lambda gap: (gap.name.lower(), order.get(gap.folder, len(order)), gap.language))
    return PreflightResult(tuple(gaps), len(calendars), commons_only)


def format_preflight(result: PreflightResult, langs: tuple[tuple[str, str], ...] | None = None) -> str:
    """Plain-text report for the job log. Missing files do not fail the build."""
    langs = langs if langs is not None else VERNACULAR_LANGS
    language_names = ", ".join(name for _folder, name in langs)
    lines = [
        "Vernacular preflight (warning only; Latin EPUBs are still built).",
        f"Languages: {language_names}.",
        (
            f"Checked {result.checked} calendar(s); "
            f"skipped {result.commons_only} with no proper of their own."
        ),
    ]
    if not result.gaps:
        lines.append("No vernacular proper files are missing.")
        return "\n".join(lines) + "\n"
    lines.append(
        f"{len(result.gaps)} gap(s) across {result.locations_with_gaps} location(s):"
    )
    for gap in result.gaps:
        lines.append(f"  {gap.name} — {gap.language}: {', '.join(gap.refs)}")
    return "\n".join(lines) + "\n"


def format_preflight_summary(result: PreflightResult) -> str:
    """Markdown for the GitHub Actions step summary."""
    if not result.gaps:
        return (
            "### Vernacular preflight\n\n"
            "No missing vernacular propers. "
            f"Skipped {result.commons_only} commons-only calendar(s). "
            "This check warns and does not stop the Latin build.\n"
        )
    rows = [
        "### Vernacular preflight",
        "",
        "Missing vernacular propers are listed below. "
        "The Latin build continues. Commons-only locations are not listed.",
        "",
        "| Location | Language | Missing files |",
        "| --- | --- | --- |",
    ]
    for gap in result.gaps:
        rows.append(f"| {gap.name} | {gap.language} | {', '.join(gap.refs)} |")
    rows.append("")
    return "\n".join(rows)
