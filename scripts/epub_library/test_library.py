#!/usr/bin/env python3
"""Dependency, window, and catalog tests. No EPUB generation."""

from __future__ import annotations

import json
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
        niagara_bilingual = [
            job for job in jobs if job["slug"] == "niagara" and job["variant"] == "la"
        ]
        other_bilingual = [
            job for job in jobs if job["slug"] != "niagara" and job["variant"] == "la"
        ]
        self.assertEqual([job["year"] for job in niagara_bilingual], [2028])
        self.assertEqual(other_bilingual, [])

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
        # Bilingual files are no longer published, so they are pruned too.
        self.assertEqual(
            doomed, ["niagara-2026-10-la.epub", "niagara-2026-10.epub", "niagara-2027-la-en.epub"]
        )

    def test_prune_keeps_listed_legacy_names(self):
        window = library.rolling_window(date(2026, 10, 16))
        catalog = _legacy_catalog([self.by_slug["niagara"]], window, "same")
        catalog["window"] = window.as_dict()
        doomed = library.assets_to_prune(
            catalog,
            ["niagara-2026.epub", "niagara-2026-10.epub", "niagara-2026-10-la.epub", "notes.txt"],
        )
        self.assertEqual(doomed, ["niagara-2026-10-la.epub"])

    def test_latin_copies_are_removed_only_after_the_latin_release_has_them(self):
        bilingual = [
            "niagara-2026.epub",
            "niagara-2026-10-la.epub",
            "niagara-2026-10-la-en.epub",
            "niagara-2026-la.epub",
        ]
        self.assertEqual(
            library.latin_copies_on_bilingual_release(bilingual, ["niagara-2026-10-la.epub"]),
            ["niagara-2026-10-la.epub"],
        )
        self.assertEqual(library.latin_copies_on_bilingual_release(bilingual, []), [])

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


def _year_files(slug: str, year: int, variant: str = "la-en", legacy: bool = False) -> list[dict]:
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
