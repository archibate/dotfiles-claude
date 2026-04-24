"""Fetch a random joke from jokeapi.dev and print it."""
import argparse
import json
import sys
import urllib.request

CATEGORIES = ["Any", "Programming", "Misc", "Pun", "Spooky", "Christmas", "Dark"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "-c",
        "--category",
        default="Any",
        choices=CATEGORIES,
        help="Joke category (default: Any)",
    )
    parser.add_argument(
        "--unsafe",
        action="store_true",
        help="Disable safe-mode (allow NSFW / offensive jokes)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit the raw JSON response instead of a rendered joke",
    )
    args = parser.parse_args()

    url = f"https://v2.jokeapi.dev/joke/{args.category}"
    if not args.unsafe:
        url += "?safe-mode"

    with urllib.request.urlopen(url, timeout=10) as resp:
        data = json.load(resp)

    if args.json:
        json.dump(data, sys.stdout, indent=2)
        print()
        return 0

    if data.get("error"):
        print(f"API error: {data.get('message', data)}", file=sys.stderr)
        return 1

    if data["type"] == "twopart":
        print(data["setup"])
        print(data["delivery"])
    else:
        print(data["joke"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
