"""HTML checks shared by the release gate and its regression tests."""
from html.parser import HTMLParser
from urllib.parse import unquote, urlsplit


def local_asset_path(site_root, value):
    """Resolve local URL paths, excluding query strings and fragments."""
    url = urlsplit(value)
    if url.scheme or url.netloc or not url.path:
        return None
    return (site_root / unquote(url.path).lstrip("/")).resolve()


class PageHeading(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_heading = False
        self.has_heading = False

    def handle_starttag(self, tag, attrs):
        if tag == "h1":
            self.in_heading = True

    def handle_endtag(self, tag):
        if tag == "h1":
            self.in_heading = False

    def handle_data(self, data):
        if self.in_heading and data.strip():
            self.has_heading = True


def has_page_heading(html):
    page = PageHeading()
    page.feed(html)
    return page.has_heading
