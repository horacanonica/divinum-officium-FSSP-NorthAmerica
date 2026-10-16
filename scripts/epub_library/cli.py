#!/usr/bin/env python3
"""Command line for the EPUB download library.

    python3 scripts/epub_library/cli.py calendars
    python3 scripts/epub_library/cli.py plan --event schedule --github-output "$GITHUB_OUTPUT"
    python3 scripts/epub_library/cli.py build --slug sacramento --year 2026 --output /tmp/epub
    python3 scripts/epub_library/cli.py merge-catalog --fragments-dir fragments --catalog docs/catalog.json
    python3 scripts/epub_library/cli.py prune-list --catalog docs/catalog.json --assets assets.json
"""

from __future__ import annotations

import argparse
import json
import sys
import uuid
from datetime import date, datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import library


def _calendars():
    calendars, order = library.load_calendars()
    return calendars, order


def _parse_today(value: str | None) -> date | None:
    if not value:
        return None
    return date.fromisoformat(value)


def _hashes(calendars, slugs: set[str] | None = None) -> dict[str, str]:
    versions = library.load_versions()
    selected = calendars if slugs is None else [cal for cal in calendars if cal.slug in slugs]
    return {cal.slug: library.content_hash(cal, versions) for cal in selected}


def cmd_calendars(_args: argparse.Namespace) -> int:
    calendars, order = _calendars()
    payload = {
        "region_order": order,
        "calendars": [
            {
                "version": cal.version,
                "slug": cal.slug,
                "name": cal.name,
                "region": cal.region,
                "place": cal.place,
                "chain": list(cal.chain),
            }
            for cal in calendars
        ],
    }
    json.dump(payload, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


def _changed_paths(path: str | None) -> list[str] | None:
    if not path:
        return None
    file = Path(path)
    if not file.is_file():
        return None
    return [line.strip() for line in file.read_text(encoding="utf-8").splitlines() if line.strip()]


def cmd_plan(args: argparse.Namespace) -> int:
    calendars, _order = _calendars()
    window = library.rolling_window(_parse_today(args.today))
    catalog = library.load_catalog(Path(args.catalog)) if args.catalog else {}
    event = args.event or "schedule"
    force_slugs: set[str] = set()
    if args.force_slug:
        force_slugs.add(args.force_slug)
    if args.force:
        force_slugs.update(cal.slug for cal in calendars)

    affected: set[str] | None = None
    if event == "push" and not args.force and not args.force_slug:
        changed = _changed_paths(args.changed)
        if changed is None:
            affected = None
        else:
            affected = library.affected_slugs(changed, calendars)

    # Fingerprint only the calendars that can possibly be queued.
    if affected is None:
        hash_slugs = {cal.slug for cal in calendars}
    else:
        never = set()
        by_slug = {item.get("slug"): item for item in catalog.get("calendars", [])}
        for cal in calendars:
            entry = by_slug.get(cal.slug) or {}
            if not entry.get("files"):
                never.add(cal.slug)
        hash_slugs = set(affected) | never | force_slugs
    hashes = _hashes(calendars, hash_slugs)
    # plan_jobs indexes hashes for every considered calendar. Fill untouched
    # ones with a sentinel that will not be read because affected excludes them.
    for cal in calendars:
        hashes.setdefault(cal.slug, "")

    jobs = library.plan_jobs(
        calendars,
        catalog,
        window,
        hashes,
        affected=affected,
        force_slugs=force_slugs,
        max_jobs=args.max_jobs,
    )
    # An empty include list makes GitHub Actions reject the matrix. The build
    # job is skipped when count is 0, so this placeholder is never built.
    matrix = {"include": jobs or [{"slug": "skip", "year": 0, "version": ""}]}
    payload = {"count": len(jobs), "matrix": matrix, "window": window.as_dict()}
    if args.output:
        Path(args.output).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    else:
        json.dump(payload, sys.stdout, indent=2)
        sys.stdout.write("\n")
    if args.github_output:
        _write_github_output(
            Path(args.github_output),
            {
                "count": str(len(jobs)),
                "matrix": json.dumps(matrix),
            },
        )
    print(f"Planned {len(jobs)} calendar-year job(s) for {window.start} through {window.end}", flush=True)
    return 0


def _write_github_output(path: Path, values: dict[str, str]) -> None:
    with path.open("a", encoding="utf-8") as handle:
        for key, value in values.items():
            if "\n" in value:
                fence = "EOF_" + uuid.uuid4().hex
                handle.write(f"{key}<<{fence}\n{value}\n{fence}\n")
            else:
                handle.write(f"{key}={value}\n")


def cmd_build(args: argparse.Namespace) -> int:
    calendars, _order = _calendars()
    by_slug = {cal.slug: cal for cal in calendars}
    if args.slug not in by_slug:
        known = ", ".join(sorted(by_slug))
        print(f"Unknown calendar slug {args.slug}. Known: {known}", file=sys.stderr)
        return 1
    library.build_year(by_slug[args.slug], args.year, Path(args.output))
    return 0


def _load_fragments(directory: Path) -> list[dict]:
    fragments = []
    if not directory.is_dir():
        return fragments
    for path in sorted(directory.rglob("fragment.json")):
        fragments.append(json.loads(path.read_text(encoding="utf-8")))
    return fragments


def cmd_merge_catalog(args: argparse.Namespace) -> int:
    calendars, order = _calendars()
    window = library.rolling_window(_parse_today(args.today))
    catalog_path = Path(args.catalog)
    old = library.load_catalog(catalog_path)
    fragments = _load_fragments(Path(args.fragments_dir)) if args.fragments_dir else []
    updated = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    repo = args.repo or old.get("repo") or "horacanonica/divinum-officium-FSSP-NorthAmerica"
    merged = library.merge_catalog(
        old,
        calendars,
        order,
        window,
        fragments,
        repo=repo,
        updated=updated,
    )
    if old and library.catalog_signature(old) == library.catalog_signature(merged):
        print("Catalog unchanged", flush=True)
        if args.github_output:
            _write_github_output(Path(args.github_output), {"changed": "false"})
        return 0
    # Keep the previous timestamp when nothing that readers see changed except
    # we already returned. A real change gets a new timestamp.
    library.write_catalog(catalog_path, merged)
    print(f"Wrote {catalog_path} ({len(fragments)} fragment(s))", flush=True)
    if args.github_output:
        _write_github_output(Path(args.github_output), {"changed": "true"})
    return 0


def cmd_prune_list(args: argparse.Namespace) -> int:
    catalog = library.load_catalog(Path(args.catalog))
    assets = json.loads(Path(args.assets).read_text(encoding="utf-8"))
    if isinstance(assets, dict):
        names = [item["name"] if isinstance(item, dict) else item for item in assets.get("assets", assets)]
    else:
        names = [item["name"] if isinstance(item, dict) else item for item in assets]
    doomed = library.assets_to_prune(catalog, names)
    for name in doomed:
        print(name)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build and catalog Divine Office EPUBs")
    sub = parser.add_subparsers(dest="command", required=True)

    calendars = sub.add_parser("calendars")
    calendars.set_defaults(func=cmd_calendars)

    plan = sub.add_parser("plan")
    plan.add_argument("--event", default="schedule")
    plan.add_argument("--changed", help="File of changed paths, one per line")
    plan.add_argument("--catalog", default="docs/catalog.json")
    plan.add_argument("--today", help="YYYY-MM-DD override")
    plan.add_argument("--force-slug", default="")
    plan.add_argument("--force", action="store_true")
    plan.add_argument("--max-jobs", type=int, default=library.MAX_JOBS)
    plan.add_argument("--output")
    plan.add_argument("--github-output")
    plan.set_defaults(func=cmd_plan)

    build = sub.add_parser("build")
    build.add_argument("--slug", required=True)
    build.add_argument("--year", type=int, required=True)
    build.add_argument("--output", required=True)
    build.set_defaults(func=cmd_build)

    merge = sub.add_parser("merge-catalog")
    merge.add_argument("--catalog", default="docs/catalog.json")
    merge.add_argument("--fragments-dir", default="")
    merge.add_argument("--today")
    merge.add_argument("--repo", default="")
    merge.add_argument("--github-output")
    merge.set_defaults(func=cmd_merge_catalog)

    prune = sub.add_parser("prune-list")
    prune.add_argument("--catalog", required=True)
    prune.add_argument("--assets", required=True)
    prune.set_defaults(func=cmd_prune_list)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
