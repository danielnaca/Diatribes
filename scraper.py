"""Paginate FetLife group members, filter by age+gender pattern, save matches to JSON + HTML.

Usage:
    export SITE_USERNAME=...
    export SITE_PASSWORD=...
    python scraper.py                                  # group 10001, pages 1..50
    python scraper.py --group 10001 --max-pages 20
    python scraper.py --min-age 25 --max-age 30
    python scraper.py --dry-run                        # don't write output; print matches

Outputs:
    matches.json  — raw match records
    matches.html  — viewer page (nickname, matched token, profile URL opens in new tab)
"""

from __future__ import annotations

import argparse
import html
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

BASE = "https://fetlife.com"
LOGIN_URL = f"{BASE}/login"
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)
REQUEST_DELAY_SECONDS = 1.5


@dataclass
class Member:
    page: int
    nickname: str
    title: str  # e.g. "27F Switch"
    location: str
    profile_url: str
    avatar_url: str | None
    matched_token: str  # e.g. "27F"


def build_session() -> requests.Session:
    s = requests.Session()
    s.headers.update(
        {
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
        }
    )
    return s


def fetch_authenticity_token(session: requests.Session) -> str:
    resp = session.get(LOGIN_URL, timeout=30)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")
    form = soup.find("form", id="new_user")
    if not form:
        raise RuntimeError("Could not find login form on /login page.")
    token_input = form.find("input", attrs={"name": "authenticity_token"})
    if not token_input or not token_input.get("value"):
        raise RuntimeError("Could not find authenticity_token in login form.")
    return token_input["value"]


def login(session: requests.Session, username: str, password: str) -> None:
    token = fetch_authenticity_token(session)
    payload = {
        "authenticity_token": token,
        "user[otp_attempt]": "step_1",
        "user[locale]": "en",
        "user[login]": username,
        "user[password]": password,
        "user[remember_me]": "1",
    }
    resp = session.post(
        LOGIN_URL,
        data=payload,
        headers={"Referer": LOGIN_URL, "Origin": BASE},
        timeout=30,
        allow_redirects=True,
    )
    resp.raise_for_status()
    # After login FetLife redirects away from /login; the response should contain
    # something that doesn't appear on the login page itself.
    final = resp.url.rstrip("/")
    body = resp.text.lower()
    on_login_page = final.endswith("/login") or 'id="new_user"' in resp.text
    looks_logged_in = "/logout" in body or "log out" in body or "/inbox" in body
    if on_login_page or not looks_logged_in:
        raise RuntimeError(
            f"Login appears to have failed (final URL: {resp.url}). "
            "Check credentials, or whether 2FA / captcha is required."
        )


def fetch_members_page(session: requests.Session, group_id: int, page: int) -> str:
    url = f"{BASE}/groups/{group_id}/members"
    resp = session.get(url, params={"page": page}, timeout=30)
    resp.raise_for_status()
    return resp.text


def parse_members(html_text: str) -> list[dict]:
    soup = BeautifulSoup(html_text, "html.parser")
    cards = soup.select("div[data-member-card]")
    out: list[dict] = []
    for card in cards:
        nickname = card.get("data-member-card", "").strip()
        if not nickname:
            continue
        profile_url = urljoin(BASE, f"/{nickname}")

        # Title = age + gender + role, e.g. "27F Switch"
        title_el = card.select_one("span.text-sm.font-bold.text-gray-300")
        title = title_el.get_text(strip=True) if title_el else ""

        # Location is the next text-sm font-normal div after the title
        location = ""
        loc_el = card.select_one("div.text-sm.font-normal.leading-normal.text-gray-300")
        if loc_el:
            location = loc_el.get_text(" ", strip=True)

        avatar_url = None
        img = card.find("img")
        if img and img.get("src") and "icon-avatar-missing" not in img["src"]:
            avatar_url = img["src"]

        out.append(
            {
                "nickname": nickname,
                "title": title,
                "location": location,
                "profile_url": profile_url,
                "avatar_url": avatar_url,
            }
        )
    return out


def make_age_pattern(min_age: int, max_age: int) -> re.Pattern[str]:
    # Match an age in [min_age, max_age] immediately followed by F (case-insensitive).
    # (?<!\d) — not preceded by another digit (so 137 doesn't match 37)
    # (?!\w)  — not followed by a word char (so 37Female doesn't match 37F)
    # Note: gender codes like CD/TV, MtF, GF, FtM all have a non-F char between
    # the age and the F, so they won't match.
    ages = "|".join(str(a) for a in range(min_age, max_age + 1))
    return re.compile(rf"(?<!\d)({ages})F(?!\w)", re.IGNORECASE)


def iter_matches(
    session: requests.Session,
    group_id: int,
    pattern: re.Pattern[str],
    max_pages: int,
) -> Iterable[Member]:
    seen: set[str] = set()
    consecutive_empty = 0
    for page in range(1, max_pages + 1):
        html_text = fetch_members_page(session, group_id, page)
        members = parse_members(html_text)
        if not members:
            consecutive_empty += 1
            print(f"[page {page}] no member cards found")
            if consecutive_empty >= 2:
                print("Two consecutive empty pages — stopping.")
                return
        else:
            consecutive_empty = 0
            page_matches = 0
            for m in members:
                if m["nickname"] in seen:
                    continue
                seen.add(m["nickname"])
                match = pattern.search(m["title"])
                if match:
                    page_matches += 1
                    yield Member(
                        page=page,
                        nickname=m["nickname"],
                        title=m["title"],
                        location=m["location"],
                        profile_url=m["profile_url"],
                        avatar_url=m["avatar_url"],
                        matched_token=match.group(0),
                    )
            print(f"[page {page}] {len(members)} members, {page_matches} match")
        time.sleep(REQUEST_DELAY_SECONDS)


HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>FetLife matches — group {group_id}</title>
<style>
  :root {{ color-scheme: dark; }}
  body {{
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #0c0c0c; color: #e5e5e5; margin: 0; padding: 24px;
  }}
  h1 {{ font-size: 20px; font-weight: 600; margin: 0 0 4px; }}
  .meta {{ color: #888; font-size: 13px; margin-bottom: 24px; }}
  ul {{ list-style: none; padding: 0; margin: 0; display: grid;
        grid-template-columns: repeat(auto-fill, minmax(360px, 1fr)); gap: 8px; }}
  li {{ background: #1a1a1a; border-radius: 4px; padding: 12px;
        display: flex; align-items: center; gap: 12px; }}
  img.avatar {{ width: 60px; height: 60px; object-fit: cover; border-radius: 4px;
                background: #333; flex: none; }}
  .info {{ min-width: 0; flex: 1; }}
  .name {{ font-weight: 700; }}
  .name a {{ color: #f56565; text-decoration: none; }}
  .name a:hover {{ text-decoration: underline; }}
  .token {{ display: inline-block; background: #c53030; color: #fff;
            font-size: 11px; padding: 1px 6px; border-radius: 3px; margin-left: 6px;
            font-weight: 700; vertical-align: middle; }}
  .title {{ color: #ccc; font-size: 13px; }}
  .loc   {{ color: #888; font-size: 12px; }}
</style>
</head>
<body>
<h1>Matches in group {group_id}</h1>
<div class="meta">{count} matches · ages {min_age}–{max_age} F · scanned up to page {pages}</div>
<ul>
{items}
</ul>
</body>
</html>
"""

ITEM_TEMPLATE = """  <li>
    {avatar}
    <div class="info">
      <div class="name">
        <a href="{url}" target="_blank" rel="noopener noreferrer">{nickname}</a>
        <span class="token">{token}</span>
      </div>
      <div class="title">{title}</div>
      <div class="loc">{location}</div>
    </div>
  </li>"""


def render_html(matches: list[Member], group_id: int, min_age: int, max_age: int, pages: int) -> str:
    items = []
    for m in matches:
        avatar = (
            f'<img class="avatar" src="{html.escape(m.avatar_url)}" alt="">'
            if m.avatar_url
            else '<div class="avatar"></div>'
        )
        items.append(
            ITEM_TEMPLATE.format(
                avatar=avatar,
                url=html.escape(m.profile_url),
                nickname=html.escape(m.nickname),
                token=html.escape(m.matched_token),
                title=html.escape(m.title),
                location=html.escape(m.location),
            )
        )
    return HTML_TEMPLATE.format(
        group_id=group_id,
        count=len(matches),
        min_age=min_age,
        max_age=max_age,
        pages=pages,
        items="\n".join(items),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--group", type=int, default=2756, help="FetLife group ID")
    parser.add_argument("--min-age", type=int, default=21)
    parser.add_argument("--max-age", type=int, default=37)
    parser.add_argument("--max-pages", type=int, default=50)
    parser.add_argument("--json-out", type=Path, default=Path("matches.json"))
    parser.add_argument("--html-out", type=Path, default=Path("matches.html"))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    username = os.environ.get("SITE_USERNAME") or os.environ.get("FETLIFE_USERNAME")
    password = os.environ.get("SITE_PASSWORD") or os.environ.get("FETLIFE_PASSWORD")
    if not username or not password:
        print(
            "ERROR: set SITE_USERNAME and SITE_PASSWORD (or FETLIFE_USERNAME/PASSWORD).",
            file=sys.stderr,
        )
        return 2

    pattern = make_age_pattern(args.min_age, args.max_age)
    session = build_session()

    print(f"Logging in to FetLife as {username} ...")
    login(session, username, password)
    print(f"Logged in. Scanning group {args.group}, up to {args.max_pages} pages.")

    matches = list(iter_matches(session, args.group, pattern, args.max_pages))

    print(f"\nFound {len(matches)} matches.")
    for m in matches:
        print(f"  [{m.matched_token}] {m.nickname} — {m.title} — {m.profile_url}")

    if args.dry_run:
        print("(dry run — not writing output)")
        return 0

    args.json_out.parent.mkdir(parents=True, exist_ok=True)
    args.json_out.write_text(
        json.dumps([asdict(m) for m in matches], indent=2, ensure_ascii=False)
    )
    print(f"Wrote {args.json_out}")

    args.html_out.parent.mkdir(parents=True, exist_ok=True)
    args.html_out.write_text(
        render_html(matches, args.group, args.min_age, args.max_age, args.max_pages)
    )
    print(f"Wrote {args.html_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
