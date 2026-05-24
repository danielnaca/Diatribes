"""Paginate a logged-in listings page, filter titles by age pattern, save matches to JSON.

Usage:
    export SITE_USERNAME=...
    export SITE_PASSWORD=...
    python scraper.py                          # uses defaults in CONFIG
    python scraper.py --max-pages 10           # override page cap
    python scraper.py --min-age 25 --max-age 35
    python scraper.py --dry-run                # don't write output; print matches

Fill in the site-specific URLs and selectors in CONFIG before running.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

CONFIG = {
    # Login
    "login_url": "https://example.com/login",
    "login_method": "POST",
    "username_field": "username",
    "password_field": "password",
    "extra_login_fields": {},  # e.g. CSRF tokens — see fetch_login_extras below
    "login_success_indicator": "logout",  # substring expected in response when logged in

    # Listings
    "listing_url": "https://example.com/listings",
    "page_query_param": "page",  # ?page=1, ?page=2, ...
    "page_start": 1,

    # HTML selectors (CSS)
    "listing_item_selector": "div.listing",       # each listing card
    "title_selector": "h2.title, .listing-title", # title inside a card
    "link_selector": "a",                         # detail link inside a card

    # Misc
    "request_delay_seconds": 1.0,
    "user_agent": "Mozilla/5.0 (compatible; ListingScraper/1.0)",
}


@dataclass
class Listing:
    page: int
    title: str
    url: str | None
    matched_token: str


def build_session(user_agent: str) -> requests.Session:
    s = requests.Session()
    s.headers.update({"User-Agent": user_agent})
    return s


def fetch_login_extras(session: requests.Session, login_url: str) -> dict:
    """GET the login page first to grab any hidden inputs (CSRF tokens, etc.)."""
    resp = session.get(login_url, timeout=30)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")
    form = soup.find("form")
    extras = {}
    if form:
        for inp in form.find_all("input", attrs={"type": "hidden"}):
            name = inp.get("name")
            value = inp.get("value", "")
            if name:
                extras[name] = value
    return extras


def login(session: requests.Session, username: str, password: str) -> None:
    cfg = CONFIG
    extras = fetch_login_extras(session, cfg["login_url"])
    extras.update(cfg["extra_login_fields"])
    payload = {
        cfg["username_field"]: username,
        cfg["password_field"]: password,
        **extras,
    }
    resp = session.request(cfg["login_method"], cfg["login_url"], data=payload, timeout=30)
    resp.raise_for_status()
    indicator = cfg["login_success_indicator"].lower()
    if indicator and indicator not in resp.text.lower():
        raise RuntimeError(
            f"Login appears to have failed: '{cfg['login_success_indicator']}' "
            f"not found in response (status {resp.status_code})."
        )


def fetch_page(session: requests.Session, page_num: int) -> str:
    cfg = CONFIG
    params = {cfg["page_query_param"]: page_num}
    resp = session.get(cfg["listing_url"], params=params, timeout=30)
    resp.raise_for_status()
    return resp.text


def parse_listings(html: str, page_num: int) -> list[tuple[str, str | None]]:
    cfg = CONFIG
    soup = BeautifulSoup(html, "html.parser")
    items = soup.select(cfg["listing_item_selector"])
    out: list[tuple[str, str | None]] = []
    for item in items:
        title_el = item.select_one(cfg["title_selector"])
        if not title_el:
            continue
        title = title_el.get_text(strip=True)
        link_el = item.select_one(cfg["link_selector"])
        href = link_el.get("href") if link_el else None
        url = urljoin(cfg["listing_url"], href) if href else None
        out.append((title, url))
    return out


def make_age_pattern(min_age: int, max_age: int) -> re.Pattern[str]:
    # Match an age within [min_age, max_age] followed by F (case-insensitive),
    # with non-digit boundaries so 125F doesn't match 25F, and 30FT doesn't match 30F.
    ages = "|".join(str(a) for a in range(min_age, max_age + 1))
    return re.compile(rf"(?<!\d)({ages})F(?!\w)", re.IGNORECASE)


def iter_matches(
    session: requests.Session,
    pattern: re.Pattern[str],
    max_pages: int,
    delay: float,
) -> Iterable[Listing]:
    cfg = CONFIG
    seen_titles: set[str] = set()
    consecutive_empty = 0
    for offset in range(max_pages):
        page_num = cfg["page_start"] + offset
        html = fetch_page(session, page_num)
        listings = parse_listings(html, page_num)
        if not listings:
            consecutive_empty += 1
            print(f"[page {page_num}] no listings found")
            if consecutive_empty >= 2:
                print("Two consecutive empty pages — stopping.")
                return
        else:
            consecutive_empty = 0
            print(f"[page {page_num}] {len(listings)} listings")
        for title, url in listings:
            if title in seen_titles:
                continue
            seen_titles.add(title)
            m = pattern.search(title)
            if m:
                yield Listing(page=page_num, title=title, url=url, matched_token=m.group(0))
        time.sleep(delay)


def save_matches(matches: list[Listing], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    data = [asdict(m) for m in matches]
    output_path.write_text(json.dumps(data, indent=2, ensure_ascii=False))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--min-age", type=int, default=21)
    parser.add_argument("--max-age", type=int, default=37)
    parser.add_argument("--max-pages", type=int, default=50)
    parser.add_argument("--output", type=Path, default=Path("matches.json"))
    parser.add_argument("--delay", type=float, default=CONFIG["request_delay_seconds"])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    username = os.environ.get("SITE_USERNAME")
    password = os.environ.get("SITE_PASSWORD")
    if not username or not password:
        print("ERROR: set SITE_USERNAME and SITE_PASSWORD env vars.", file=sys.stderr)
        return 2

    if "example.com" in CONFIG["login_url"] or "example.com" in CONFIG["listing_url"]:
        print(
            "ERROR: CONFIG still has example.com placeholders. "
            "Edit scraper.py CONFIG with the real site URLs and selectors.",
            file=sys.stderr,
        )
        return 2

    pattern = make_age_pattern(args.min_age, args.max_age)
    session = build_session(CONFIG["user_agent"])

    print(f"Logging in to {CONFIG['login_url']} as {username} ...")
    login(session, username, password)
    print("Logged in. Starting pagination.")

    matches = list(iter_matches(session, pattern, args.max_pages, args.delay))

    print(f"\nFound {len(matches)} matches.")
    for m in matches:
        print(f"  [{m.matched_token}] {m.title}  -> {m.url}")

    if args.dry_run:
        print("(dry run — not writing output)")
    else:
        save_matches(matches, args.output)
        print(f"Saved to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
