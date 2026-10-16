#!/usr/bin/env python3
"""Dependency-free checks for the public Pi-Control landing page."""
from html.parser import HTMLParser
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
SITE_URL = "https://pi-control-public.steindlsimon12.workers.dev/"


class PageParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.title_parts = []
        self.in_title = False
        self.lang = None
        self.meta = {}
        self.links = []
        self.h1_count = 0
        self.ids = set()
        self.anchors = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "html":
            self.lang = attrs.get("lang")
        if tag == "title":
            self.in_title = True
        if tag == "meta":
            key = attrs.get("name") or attrs.get("property")
            if key:
                self.meta[key] = attrs.get("content", "")
        if tag == "link" and attrs.get("rel") == "canonical":
            self.meta["canonical"] = attrs.get("href", "")
        if tag == "a":
            href = attrs.get("href", "")
            if href:
                self.links.append(href)
                if href.startswith("#"):
                    self.anchors.append(href[1:])
        if attrs.get("id"):
            self.ids.add(attrs["id"])
        if tag == "h1":
            self.h1_count += 1

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False

    def handle_data(self, data):
        if self.in_title:
            self.title_parts.append(data.strip())


def main():
    html = (ROOT / "index.html").read_text(encoding="utf-8")
    parser = PageParser()
    parser.feed(html)
    title = " ".join(part for part in parser.title_parts if part)
    assert parser.lang == "en", "Set the document language."
    assert len(title) >= 20, "Add a descriptive page title."
    assert len(parser.meta.get("description", "")) >= 80, "Add a useful meta description."
    assert parser.meta.get("canonical") == SITE_URL, "Canonical URL must match the deployed site."
    assert parser.meta.get("og:url") == SITE_URL, "Open Graph URL must match canonical."
    assert parser.meta.get("og:title"), "Open Graph title is missing."
    assert parser.meta.get("google-site-verification"), "Keep Google Search Console verification."
    assert parser.h1_count == 1, "The page should have exactly one primary heading."
    assert all(anchor in parser.ids for anchor in parser.anchors), "A local navigation link points to a missing ID."
    assert "https://github.com/SimonSteindl/pi-control" in parser.links, "Repository link is missing."
    assert "https://github.com/SimonSteindl/pi-control/releases" in parser.links, "Release link is missing."
    assert "Illustrative preview" in html and "not live device telemetry" in html, "Dashboard preview must be labelled as illustrative."

    sitemap = ET.parse(ROOT / "sitemap.xml").getroot()
    ns = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9"}
    locations = [node.text for node in sitemap.findall(".//s:loc", ns)]
    assert locations == [SITE_URL], "Sitemap should contain the canonical landing page."
    robots = (ROOT / "robots.txt").read_text(encoding="utf-8")
    assert f"Sitemap: {SITE_URL}sitemap.xml" in robots, "robots.txt sitemap URL is incorrect."
    assert not re.search(r"(?i)(api[_-]?key|secret[_-]?token)\s*=", html), "Potential secret found in public HTML."
    print("Public-site checks passed.")


if __name__ == "__main__":
    main()
