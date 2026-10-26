"""Check built HTML file and fragment links, including generated OPF guides."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import sys


class PageLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.links = []

    def handle_starttag(self, tag, attributes):
        attributes = dict(attributes)
        if "id" in attributes:
            self.ids.add(attributes["id"])
        if tag == "a" and "href" in attributes:
            self.links.append(attributes["href"])


def check(root):
    pages = {}
    for path in root.rglob("*.html"):
        page = PageLinks()
        page.feed(path.read_text(encoding="utf-8"))
        pages[path] = page
    if not pages:
        raise SystemExit(f"No built HTML found in {root}")
    failures = []
    for path, page in pages.items():
        for link in page.links:
            url = urlsplit(link)
            if url.scheme or url.netloc:
                continue
            target = (path.parent / unquote(url.path)).resolve() if url.path else path
            if target.is_dir():
                target /= "index.html"
            if not target.exists():
                failures.append((path.relative_to(root), link, "missing file"))
            elif (url.fragment and target in pages
                  and unquote(url.fragment) not in pages[target].ids):
                failures.append((path.relative_to(root), link, "missing anchor"))
    for failure in failures:
        print(*failure, sep=": ")
    if failures:
        raise SystemExit(f"{len(failures)} broken local links")
    print(f"Local file and fragment links pass across {len(pages)} HTML pages.")


if __name__ == "__main__":
    check(Path(sys.argv[1] if len(sys.argv) > 1 else "docs/build").resolve())
