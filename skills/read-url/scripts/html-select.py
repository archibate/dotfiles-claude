#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["beautifulsoup4"]
# ///
"""Read HTML from stdin, print text of all elements matching the CSS selector.

Usage: curl -sL <url> | html-select.py '<css selector>'
"""
import sys
from bs4 import BeautifulSoup

if len(sys.argv) != 2:
    sys.exit("usage: html-select.py '<css selector>' < page.html")

soup = BeautifulSoup(sys.stdin.read(), "html.parser")
for el in soup.select(sys.argv[1]):
    print(el.get_text("\n", strip=True))
    print()
