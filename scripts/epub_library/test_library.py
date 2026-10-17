#!/usr/bin/env python3
"""Dependency, window, and catalog tests. No EPUB generation."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import unittest
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import library


class CalendarDiscoveryTest(unittest.TestCase):
    def setUp(self):
        self.calendars, self.order = library.load_calendars()
        self.by_slug = {cal.slug: cal for cal in self.calendars}

    def test_publishes_fssp_family_only(self):
        slugs = set(self.by_slug)
        for expected in (
            "fssp",
            "fssp-usa",
            "sacramento",
            "guadalajara",
            "chesapeake",
            "richmond",
            "nashua",
            "arlington",
            "scranton",
            "maple-hill",
            "olg-seminary",
            "quincy",
            "baltimore",
            "niagara",
        ):
            self.assertIn(expected, slugs)
        versions = {cal.version for cal in self.calendars}
        self.assertNotIn("Tridentine - 1570", versions)
        self.assertNotIn("Rubrics 1960 - 1960", versions)
        self.assertNotIn("Rubrics 1960 - USA 1960", versions)
        self.assertNotIn("Monastic - 1963", versions)

    def test_regions_are_data_driven(self):
        self.assertEqual(self.by_slug["sacramento"].region, "West")
        self.assertEqual(self.by_slug["guadalajara"].region, "Mexico")
        self.assertEqual(self.by_slug["niagara"].region, "Canada")
        self.assertEqual(self.by_slug["quincy"].region, "Midwest")
        self.assertEqual(self.by_slug["baltimore"].region, "Northeast & Mid-Atlantic")
        self.assertEqual(self.by_slug["fssp"].region, "General")
        self.assertIn("South Central", self.order)
        self.assertIn("Southeast", self.order)

    def test_every_generated_calendar_is_listed_year_only(self):
        self.assertGreaterEqual(len(self.calendars), 99)
        self.assertNotIn("Other", {cal.region for cal in self.calendars})
        self.assertFalse(any(cal.monthly for cal in self.calendars))
        self.assertEqual(library.VARIANTS, ("la",))
        self.assertIn("diocese-of-phoenix", self.by_slug)
        self.assertEqual(self.by_slug["fssp-canada"].region, "Canada")
        # A generated calendar that repeats a hand-written one is not listed twice.
        self.assertNotIn("st-lucys-church-scranton-pa", self.by_slug)
        self.assertEqual(
            self.by_slug["scranton"].name, "St. Lucy's Church, Scranton (Diocese of Scranton)"
        )
        # Parish headings carry the city.
        for cal in self.calendars:
            if cal.version.split(" - ", 1)[1].startswith("St. "):
                self.assertIn(",", cal.name)

    def test_calendars_list_their_local_feasts_by_layer(self):
        def sequence(slug):
            layers = []
            for feast in self.by_slug[slug].feasts:
                if not layers or layers[-1] != feast["layer"]:
                    layers.append(feast["layer"])
            return layers

        # Parish, then diocese, then FSSP, then the country.
        self.assertEqual(sequence("diocese-of-phoenix"), ["Diocese", "FSSP", "United States"])
        self.assertEqual(sequence("archdiocese-of-denver"), ["Diocese", "FSSP", "United States"])
        self.assertEqual(
            sequence("our-lady-of-mount-carmel-littleton-co"),
            ["Parish", "Diocese", "FSSP", "United States"],
        )
        self.assertEqual(sequence("diocese-of-calgary"), ["Diocese", "FSSP", "Canada"])
        self.assertEqual(
            sequence("st-anthony-church-calgary-ab"),
            ["Parish", "Diocese", "FSSP", "Canada"],
        )
        self.assertEqual(sequence("sacramento"), ["This calendar", "FSSP", "United States"])
        self.assertEqual(sequence("guadalajara"), ["This calendar", "FSSP"])

        denver = self.by_slug["archdiocese-of-denver"].feasts
        self.assertEqual((denver[0]["date"], denver[0]["layer"]), ("10-27", "Diocese"))
        littleton = self.by_slug["our-lady-of-mount-carmel-littleton-co"].feasts
        self.assertEqual((littleton[0]["date"], littleton[0]["layer"]), ("07-16", "Parish"))

        phoenix = self.by_slug["diocese-of-phoenix"]
        dec12 = [f for f in phoenix.feasts if f["date"] == "12-12"]
        self.assertEqual(len(dec12), 1)  # the diocese replaces the US layer on the same date
        self.assertEqual((dec12[0]["layer"], dec12[0]["class"]), ("Diocese", "I"))
        canada = self.by_slug["diocese-of-calgary"]
        self.assertNotIn("United States", {f["layer"] for f in canada.feasts})

        for cal in self.calendars:
            ranks = [library.layer_display_rank(feast["layer"]) for feast in cal.feasts]
            self.assertEqual(ranks, sorted(ranks), cal.slug)
            by_layer: dict[str, list[str]] = {}
            for feast in cal.feasts:
                by_layer.setdefault(feast["layer"], []).append(feast["date"])
            for layer, dates in by_layer.items():
                self.assertEqual(dates, sorted(dates), f"{cal.slug} {layer}")

    def test_download_page_sorts_feast_groups_the_same_way(self):
        node = shutil.which("node")
        if node is None:
            self.skipTest("node is not installed")
        script = Path(__file__).resolve().parents[1].parent / "docs" / "downloads.js"
        source = script.read_text(encoding="utf-8")
        prelude = source.split("function monthsInWindow", 1)[0]
        calendars = []
        for cal in self.calendars:
            feasts = [dict(feast) for feast in cal.feasts]
            calendars.append(
                {
                    "slug": cal.slug,
                    "feasts": list(reversed(feasts)),
                    "expected": feasts,
                }
            )
        calendars.append(
            {
                "slug": "unknown-layer",
                "feasts": [
                    {"layer": "United States", "date": "01-02", "name": "country"},
                    {"layer": "Mission", "date": "06-01", "name": "local"},
                    {"layer": "FSSP", "date": "03-01", "name": "institute"},
                    {"layer": "Parish", "date": "01-01", "name": "parish"},
                ],
                "expected": [
                    {"layer": "Mission", "date": "06-01", "name": "local"},
                    {"layer": "Parish", "date": "01-01", "name": "parish"},
                    {"layer": "FSSP", "date": "03-01", "name": "institute"},
                    {"layer": "United States", "date": "01-02", "name": "country"},
                ],
            }
        )
        program = prelude + """
const calendars = require("fs").readFileSync(0, "utf8");
for (const calendar of JSON.parse(calendars)) {
  const ordered = feastsInDisplayOrder(calendar.feasts);
  if (JSON.stringify(ordered) !== JSON.stringify(calendar.expected)) {
    console.error(calendar.slug);
    console.error(JSON.stringify(ordered));
    process.exit(1);
  }
}
"""
        result = subprocess.run(
            [node, "-e", program],
            input=json.dumps(calendars),
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)

    def test_missing_region_falls_through_to_other(self):
        versions = library.load_versions()
        versions["Rubrics 1960 - Testville"] = library.Version(
            "Rubrics 1960 - Testville",
            "Testville",
            "Rubrics 1960 - FSSP",
            "Rubrics 1960 - Testville,Testville,1960,1960,Rubrics 1960 - FSSP",
        )
        calendars, _order = library.load_calendars(versions)
        testville = next(cal for cal in calendars if cal.slug == "testville")
        self.assertEqual(testville.region, "Other")
        self.assertIn("sacramento", {cal.slug for cal in calendars})


class DependencyTest(unittest.TestCase):
    def setUp(self):
        self.calendars, _order = library.load_calendars()
        self.by_slug = {cal.slug: cal for cal in self.calendars}
        self.versions = library.load_versions()

    def test_chain_files_follow_inheritance(self):
        sacramento = set(library.chain_files(self.by_slug["sacramento"], self.versions))
        guadalajara = set(library.chain_files(self.by_slug["guadalajara"], self.versions))
        niagara = set(library.chain_files(self.by_slug["niagara"], self.versions))
        self.assertIn("web/www/Tabulae/Kalendaria/Sacramento.txt", sacramento)
        self.assertNotIn("web/www/Tabulae/Kalendaria/Sacramento.txt", guadalajara)
        self.assertIn("web/www/Tabulae/Kalendaria/FSSP.txt", sacramento)
        self.assertIn("web/www/Tabulae/Kalendaria/FSSP.txt", guadalajara)
        self.assertIn("web/www/Tabulae/Kalendaria/USA1960.txt", sacramento)
        self.assertNotIn("web/www/Tabulae/Kalendaria/USA1960.txt", guadalajara)
        self.assertNotIn("web/www/Tabulae/Kalendaria/USA1960.txt", niagara)
        self.assertTrue(any(path.startswith("web/www/horas/Latin/Tempora/") for path in library.iter_shared_files()))

    def test_affected_paths(self):
        all_slugs = {cal.slug for cal in self.calendars}
        self.assertEqual(
            library.affected_slugs(["web/www/Tabulae/Kalendaria/Sacramento.txt"], self.calendars),
            {"sacramento"},
        )
        self.assertEqual(
            library.affected_slugs(["web/www/Tabulae/Kalendaria/FSSP.txt"], self.calendars),
            all_slugs,
        )
        usa = library.affected_slugs(["web/www/Tabulae/Kalendaria/USA1960.txt"], self.calendars)
        self.assertIn("sacramento", usa)
        self.assertIn("fssp-usa", usa)
        self.assertIn("baltimore", usa)
        self.assertNotIn("guadalajara", usa)
        self.assertNotIn("niagara", usa)
        self.assertNotIn("fssp", usa)
        self.assertEqual(
            library.affected_slugs(["web/www/horas/Latin/Tempora/Adv1-0.txt"], self.calendars),
            all_slugs,
        )
        self.assertEqual(
            library.affected_slugs(["web/cgi-bin/horas/horas.pl"], self.calendars),
            all_slugs,
        )
        self.assertEqual(
            library.affected_slugs(["web/www/horas/Latin/Sancti/01-24g.txt"], self.calendars),
            {"guadalajara"},
        )
        self.assertEqual(library.affected_slugs(["README.md", "docs/index.html"], self.calendars), set())

    def test_fingerprint_ignores_unrelated_parish(self):
        sacramento = self.by_slug["sacramento"]
        guadalajara = self.by_slug["guadalajara"]
        sac_hash = library.content_hash(sacramento, self.versions)
        gld_hash = library.content_hash(guadalajara, self.versions)
        self.assertNotEqual(sac_hash, gld_hash)
        sac_file = "web/www/Tabulae/Kalendaria/Sacramento.txt"
        changed = library.content_hash(
            sacramento,
            self.versions,
            file_overrides={sac_file: b"03-17=03-17n=Changed=\n"},
        )
        unchanged = library.content_hash(
            guadalajara,
            self.versions,
            file_overrides={sac_file: b"03-17=03-17n=Changed=\n"},
        )
        self.assertNotEqual(changed, sac_hash)
        self.assertEqual(unchanged, gld_hash)

    def test_fingerprint_ignores_unrelated_data_row(self):
        sacramento = self.by_slug["sacramento"]
        guadalajara = self.by_slug["guadalajara"]
        override = {"Rubrics 1960 - Guadalajara": "Rubrics 1960 - Guadalajara,CHANGED"}
        self.assertEqual(
            library.content_hash(sacramento, self.versions),
            library.content_hash(sacramento, self.versions, row_overrides=override),
        )
        self.assertNotEqual(
            library.content_hash(guadalajara, self.versions),
            library.content_hash(guadalajara, self.versions, row_overrides=override),
        )

    def test_shared_edit_changes_every_fingerprint(self):
        before = {
            cal.slug: library.content_hash(cal, self.versions)
            for cal in (self.by_slug["sacramento"], self.by_slug["niagara"])
        }
        after = {
            cal.slug: library.content_hash(
                cal,
                self.versions,
                file_overrides={"web/cgi-bin/horas/horas.pl": b"changed"},
            )
            for cal in (self.by_slug["sacramento"], self.by_slug["niagara"])
        }
        self.assertNotEqual(before["sacramento"], after["sacramento"])
        self.assertNotEqual(before["niagara"], after["niagara"])


class WindowAndPlanTest(unittest.TestCase):
    def setUp(self):
        self.calendars, self.order = library.load_calendars()
        self.by_slug = {cal.slug: cal for cal in self.calendars}

    def test_window_from_october_2026(self):
        window = library.rolling_window(date(2026, 10, 16))
        self.assertEqual(window.start, "2026-10")
        self.assertEqual(window.end, "2028-10")
        self.assertEqual(window.years, (2026, 2027, 2028))

    def test_window_rolls_into_a_new_year(self):
        window = library.rolling_window(date(2027, 1, 1))
        self.assertEqual(window.start, "2027-01")
        self.assertEqual(window.end, "2029-01")
        self.assertEqual(window.years, (2027, 2028, 2029))

    def test_empty_catalog_plans_every_year_up_to_the_cap(self):
        window = library.rolling_window(date(2026, 10, 16))
        hashes = {cal.slug: "abc" for cal in self.calendars}
        jobs = library.plan_jobs(self.calendars, {}, window, hashes, affected=None, max_jobs=400)
        self.assertEqual(len(jobs), len(self.calendars) * len(window.years) * len(library.VARIANTS))
        self.assertEqual(jobs[0]["variant"], "la")
        capped = library.plan_jobs(self.calendars, {}, window, hashes, affected=None, max_jobs=5)
        self.assertEqual(len(capped), 5)
        self.assertTrue(all(job["variant"] == "la" for job in capped))

    def test_push_rebuilds_only_the_affected_calendar(self):
        window = library.rolling_window(date(2026, 10, 16))
        hashes = {cal.slug: "same" for cal in self.calendars}
        catalog = _complete_catalog(self.calendars, window, "same")
        hashes["sacramento"] = "new"
        jobs = library.plan_jobs(
            self.calendars,
            catalog,
            window,
            hashes,
            affected={"sacramento"},
        )
        self.assertEqual({job["slug"] for job in jobs}, {"sacramento"})
        self.assertEqual(sorted(job["year"] for job in jobs if job["variant"] == "la"), [2026, 2027, 2028])
        self.assertEqual([job["variant"] for job in jobs], ["la", "la", "la"])

    def test_complete_catalog_plans_nothing(self):
        window = library.rolling_window(date(2026, 10, 16))
        hashes = {cal.slug: "same" for cal in self.calendars}
        catalog = _complete_catalog(self.calendars, window, "same")
        jobs = library.plan_jobs(self.calendars, catalog, window, hashes, affected=None)
        self.assertEqual(jobs, [])

    def test_first_v2_catalog_keeps_complete_years(self):
        window = library.rolling_window(date(2026, 10, 16))
        hashes = {cal.slug: "office-hash" for cal in self.calendars}
        catalog = _complete_catalog(self.calendars, window, "previous-hash")
        del catalog["fingerprint"]
        jobs = library.plan_jobs(self.calendars, catalog, window, hashes, affected=set(hashes))
        self.assertEqual(jobs, [])

    def test_missing_years_are_filled_even_when_the_push_is_unrelated(self):
        window = library.rolling_window(date(2026, 10, 16))
        hashes = {cal.slug: "same" for cal in self.calendars}
        catalog = _complete_catalog(self.calendars, window, "same")
        niagara = next(item for item in catalog["calendars"] if item["slug"] == "niagara")
        niagara["files"] = [item for item in niagara["files"] if item["year"] != 2028]
        niagara["built"].pop("2028", None)
        jobs = library.plan_jobs(self.calendars, catalog, window, hashes, affected=set())
        niagara_jobs = [job for job in jobs if job["slug"] == "niagara"]
        other_jobs = [job for job in jobs if job["slug"] != "niagara"]
        self.assertEqual([job["year"] for job in niagara_jobs], [2028])
        self.assertEqual([job["variant"] for job in niagara_jobs], ["la"])
        self.assertEqual(other_jobs, [])

    def test_partial_year_does_not_stamp_the_other_years(self):
        window = library.rolling_window(date(2026, 10, 16))
        sacramento = self.by_slug["sacramento"]
        old = {"calendars": []}
        fragment = {
            "version": sacramento.version,
            "slug": "sacramento",
            "year": 2026,
            "variant": "la",
            "content_hash": "new",
            "files": _year_files("sacramento", 2026, "la"),
        }
        merged = library.merge_catalog(
            old,
            self.calendars,
            self.order,
            window,
            [fragment],
            repo="horacanonica/divinum-officium-FSSP-NorthAmerica",
            updated="2026-10-16T00:00:00Z",
        )
        entry = next(item for item in merged["calendars"] if item["slug"] == "sacramento")
        self.assertEqual(entry["built"], {"2026": {"la": "new"}})
        hashes = {cal.slug: "new" for cal in self.calendars}
        jobs = library.plan_jobs(self.calendars, merged, window, hashes, affected={"sacramento"})
        sacramento_jobs = [job for job in jobs if job["slug"] == "sacramento"]
        self.assertEqual(
            sorted(job["year"] for job in sacramento_jobs),
            [2027, 2028],
        )
        # Calendars that have never been built are still queued, so one push
        # cannot leave a new apostolate waiting for the nightly run.
        self.assertIn("fssp", {job["slug"] for job in jobs})

    def test_merge_refreshes_metadata_and_drops_old_years(self):
        window = library.rolling_window(date(2027, 1, 1))
        old = _complete_catalog(self.calendars, library.rolling_window(date(2026, 10, 16)), "same")
        merged = library.merge_catalog(
            old,
            self.calendars,
            self.order,
            window,
            [],
            repo="horacanonica/divinum-officium-FSSP-NorthAmerica",
            updated="2027-01-01T00:00:00Z",
        )
        entry = next(item for item in merged["calendars"] if item["slug"] == "niagara")
        years = {item["year"] for item in entry["files"]}
        self.assertEqual(years, {2027, 2028})
        self.assertEqual(merged["window"]["start"], "2027-01")
        doomed = library.assets_to_prune(
            merged,
            [
                "niagara-2026-10.epub",
                "niagara-2026-10-la.epub",
                "niagara-2027-la.epub",
                "niagara-2027-la-en.epub",
                "catalog.json",
                "notes.txt",
            ],
        )
        self.assertEqual(
            doomed, ["niagara-2026-10-la.epub", "niagara-2026-10.epub", "niagara-2027-la-en.epub"]
        )
        self.assertEqual(merged["release"], "epub-library-la")
        self.assertEqual(merged["variants"], [{"id": "la", "label": "Latin"}])

    def test_merge_drops_bilingual_files_and_stamps(self):
        window = library.rolling_window(date(2026, 10, 16))
        catalog = _legacy_catalog([self.by_slug["niagara"]], window, "bilingual-hash")
        entry = catalog["calendars"][0]
        entry["files"].extend(_year_files("niagara", 2026, "la"))
        entry["files"].append(
            {
                "type": "year",
                "year": 2026,
                "name": "niagara-2026-la-en.epub",
                "bytes": 10,
                "variant": "la-en",
            }
        )
        entry["built"]["2026"] = {"la": "latin-hash", "la-en": "bilingual-hash"}
        merged = library.merge_catalog(
            catalog,
            self.calendars,
            self.order,
            window,
            [
                {
                    "version": self.by_slug["niagara"].version,
                    "slug": "niagara",
                    "year": 2027,
                    "variant": "la-en",
                    "content_hash": "should-be-ignored",
                    "files": [
                        {
                            "type": "year",
                            "year": 2027,
                            "name": "niagara-2027-la-en.epub",
                            "bytes": 10,
                            "variant": "la-en",
                        }
                    ],
                }
            ],
            repo="horacanonica/divinum-officium-FSSP-NorthAmerica",
            updated="2026-10-17T00:00:00Z",
        )
        niagara = next(item for item in merged["calendars"] if item["slug"] == "niagara")
        names = [item["name"] for item in niagara["files"]]
        self.assertEqual(names, ["niagara-2026-la.epub"])
        self.assertEqual(niagara["built"], {"2026": {"la": "latin-hash"}})
        self.assertEqual(merged["releases"], {"la": "epub-library-la"})
        self.assertNotIn("la-en", json.dumps(merged["variants"]))
        doomed = library.assets_to_prune(
            merged,
            ["niagara-2026.epub", "niagara-2026-la-en.epub", "niagara-2026-la.epub", "niagara-2027-la-en.epub"],
        )
        self.assertEqual(
            doomed, ["niagara-2026-la-en.epub", "niagara-2026.epub", "niagara-2027-la-en.epub"]
        )

    def test_asset_names_keep_hyphenated_slugs(self):
        self.assertEqual(
            library.parse_asset_name("fssp-usa-2026-01-la-en.epub"),
            ("fssp-usa", 2026, "la-en"),
        )
        self.assertEqual(library.parse_asset_name("maple-hill-2028-la.epub"), ("maple-hill", 2028, "la"))
        self.assertEqual(library.parse_asset_name("sacramento-2026-10.epub"), ("sacramento", 2026, None))
        self.assertIsNone(library.parse_asset_name("catalog.json"))

    def test_classify_generated_names(self):
        self.assertEqual(library.classify_generated("breviarium2026-10_Sac.epub", 2026), ("month", 10))
        self.assertEqual(library.classify_generated("breviarium2026_Sac.epub", 2026), ("year", None))
        self.assertEqual(library.classify_generated("breviarium2026_MapleHill.epub", 2026), ("year", None))
        self.assertIsNone(library.classify_generated("breviarium2025-10_Sac.epub", 2026))


def _year_files(slug: str, year: int, variant: str = "la", legacy: bool = False) -> list[dict]:
    def name(month: int | None) -> str:
        if legacy:
            if month is None:
                return f"{slug}-{year}.epub"
            return f"{slug}-{year}-{month:02d}.epub"
        return library.asset_name(slug, year, month, variant)

    files = [{"type": "year", "year": year, "name": name(None), "bytes": 10, "variant": variant}]
    if legacy:
        files[0].pop("variant")
    for month in range(1, 13):
        record = {
            "type": "month",
            "year": year,
            "month": month,
            "name": name(month),
            "bytes": 10,
            "variant": variant,
        }
        if legacy:
            record.pop("variant")
        files.append(record)
    return files


def _catalog_with(calendars, window, digest: str, *, legacy: bool) -> dict:
    entries = []
    for cal in calendars:
        files = []
        built = {}
        for year in window.years:
            if legacy:
                files.extend(_year_files(cal.slug, year, legacy=True))
                built[str(year)] = digest
            else:
                year_files = []
                for variant in library.VARIANTS:
                    year_files.extend(_year_files(cal.slug, year, variant))
                files.extend(year_files)
                built[str(year)] = {variant: digest for variant in library.VARIANTS}
        entries.append(
            {
                "version": cal.version,
                "slug": cal.slug,
                "name": cal.name,
                "region": cal.region,
                "place": cal.place,
                "built": built,
                "files": files,
            }
        )
    return {
        "fingerprint": library.FINGERPRINT_VERSION,
        "calendars": entries,
        "window": window.as_dict(),
    }


def _complete_catalog(calendars, window, digest: str) -> dict:
    return _catalog_with(calendars, window, digest, legacy=False)


def _legacy_catalog(calendars, window, digest: str) -> dict:
    return _catalog_with(calendars, window, digest, legacy=True)


if __name__ == "__main__":
    unittest.main()
