#!/usr/bin/env python3
"""Build the public Pi-Control site into ``dist/``.

Single source of truth for which files are published. Used by:
- ``wrangler.jsonc`` (``build.command``) for every ``wrangler dev``/``deploy``,
- the GitHub Actions workflow ``deploy-public-site.yml``.

Only the files listed in PUBLIC_FILES are copied. Everything else in this
folder (README, wrangler config, tests, this script) stays private.
"""
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parent
DIST = ROOT / "dist"
PUBLIC_FILES = ("index.html", "robots.txt", "sitemap.xml")


def build() -> None:
    sys.dont_write_bytecode = True  # keep the source folder clean
    sys.path.insert(0, str(ROOT))
    import test_site  # noqa: E402  (local, dependency-free checks)

    test_site.main()

    missing = [name for name in PUBLIC_FILES if not (ROOT / name).is_file()]
    if missing:
        raise SystemExit(f"Missing public files: {', '.join(missing)}")

    if DIST.is_symlink():
        raise SystemExit(f"Refusing to build: {DIST} is a symlink.")
    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir()

    for name in PUBLIC_FILES:
        shutil.copy2(ROOT / name, DIST / name)

    published = sorted(p.name for p in DIST.iterdir())
    if published != sorted(PUBLIC_FILES):
        raise SystemExit(f"Unexpected dist contents: {published}")
    print(f"Built {DIST.relative_to(ROOT)}/ with: {', '.join(published)}")


if __name__ == "__main__":
    build()
