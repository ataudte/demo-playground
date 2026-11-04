#!/bin/bash
# Download and rename presentations from a DNS-OARC Indico event.
# Creates or reuses a Python environment, prefers PDFs, and generates a ZIP and CSV index.
# Requires Python 3.8+; no additional packages.
# Usage: bash download_oarc.sh EVENT_NUMBER [output-directory] [options]
set -euo pipefail

URL_TEMPLATE='https://indico.dns-oarc.net/event/{event_number}/timetable/#all.detailed'

usage() {
    cat <<'USAGE'
Usage: bash download_oarc.sh EVENT_NUMBER [output-directory] [options]
Options: --prefix PREFIX, --cookies FILE, --no-zip, --list, -h/--help
Example: bash download_oarc.sh 58
See readme.md for requirements, setup and examples.
USAGE
}

if [[ $# -eq 0 ]]; then
    usage >&2
    exit 2
fi
if [[ "$1" == '-h' || "$1" == '--help' ]]; then
    usage
    exit 0
fi
if [[ ! "$1" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s\n' 'Error: the first argument must be a positive event number, e.g. 58.' >&2
    exit 2
fi
for argument in "$@"; do
    if [[ "$argument" == '-h' || "$argument" == '--help' ]]; then
        usage
        exit 0
    fi
done

EVENT_NUMBER="$1"
URL="${URL_TEMPLATE//\{event_number\}/${EVENT_NUMBER}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${OARC_VENV_DIR:-${SCRIPT_DIR}/.oarc-downloader-venv}"
VENV_PYTHON="${VENV_DIR}/bin/python3"

if [[ ! -x "$VENV_PYTHON" || ! -f "${VENV_DIR}/pyvenv.cfg" ]]; then
    PYTHON_BIN="${OARC_PYTHON:-python3}"
    if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
        printf '%s\n' 'Python 3 is required. If you use Homebrew: brew install python' >&2
        exit 127
    fi
    if ! "$PYTHON_BIN" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)'; then
        printf '%s\n' 'Python 3.8 or newer is required.' >&2
        exit 1
    fi
    printf 'Creating Python environment: %s\n' "$VENV_DIR"
    # The downloader uses only Python's standard library.
    "$PYTHON_BIN" -m venv --without-pip "$VENV_DIR"
else
    printf 'Using Python environment: %s\n' "$VENV_DIR"
fi

exec "$VENV_PYTHON" - "$URL" "$@" <<'PYTHON'
import argparse
import csv
import hashlib
import html
import http.client
import http.cookiejar
import io
import json
import os
import re
import sys
import tempfile
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from collections import Counter
from pathlib import Path

FORMATS = (".pdf", ".pptx", ".ppt", ".odp", ".key", ".ppsx", ".pps")


class AccessRequired(Exception):
    pass


def fetch(opener, url):
    """Retry transient failures; never treat a sign-in page as a download."""
    if urllib.parse.urlsplit(url).scheme not in ("https", "http"):
        raise ValueError("Unsupported download URL scheme")
    url = urllib.parse.quote(url, safe=":/?#[]@!$&'()*+,;=%")
    request = urllib.request.Request(url, headers={"User-Agent": "DNS-OARC-presentation-downloader/1.0"})
    for attempt in range(3):
        try:
            with opener.open(request, timeout=60) as response:
                if re.search(r"/(?:login|signin|sign-in)(?:/|$)", urllib.parse.urlsplit(response.geturl()).path):
                    raise AccessRequired("The site redirected to its sign-in page")
                return response.read()
        except urllib.error.HTTPError as exc:
            if exc.code in (401, 403):
                raise AccessRequired("HTTP {}: sign-in or permission required".format(exc.code)) from exc
            if exc.code not in (408, 425, 429, 500, 502, 503, 504) or attempt == 2:
                raise
            delay = exc.headers.get("Retry-After", "")
            time.sleep(min(int(delay), 30) if delay.isdigit() else 2 ** attempt)
        except (urllib.error.URLError, TimeoutError, ConnectionError, http.client.IncompleteRead):
            if attempt == 2:
                raise
            time.sleep(2 ** attempt)


def parse_talks(html):
    # Indico embeds its complete schedule as JSON in timetableArgs.
    # Decode the first two arguments as data; never execute page JavaScript.
    match = re.search(r"\bvar\s+timetableArgs\s*=\s*\[", html)
    if not match:
        raise ValueError("Cannot find Indico's timetable data; the website layout may have changed")
    position = match.end()
    decoder = json.JSONDecoder()
    schedule = None
    for _ in range(2):
        while position < len(html) and (html[position].isspace() or html[position] == ","):
            position += 1
        schedule, position = decoder.raw_decode(html, position)
    if not isinstance(schedule, dict):
        raise ValueError("Unexpected timetable data structure")

    talks = {}

    def walk(value):
        if isinstance(value, dict):
            if value.get("entryType") == "Contribution" and value.get("contributionId") is not None:
                if value.get("presenters") or candidates(value):
                    talks[value["contributionId"]] = value
            for item in value.values():
                walk(item)
        elif isinstance(value, list):
            for item in value:
                walk(item)

    walk(schedule)
    if not talks:
        raise ValueError("No talks found; the timetable may be empty or its layout may have changed")
    return sorted(talks.values(), key=lambda c: (
        (c.get("startDate") or {}).get("date", ""),
        (c.get("startDate") or {}).get("time", ""), c["contributionId"]))


def extension(attachment):
    for value in (attachment.get("title", ""), attachment.get("download_url", "")):
        suffix = Path(urllib.parse.unquote(urllib.parse.urlsplit(value).path)).suffix.lower()
        if suffix in FORMATS:
            return suffix
    return None


def candidates(talk):
    attachments = talk.get("attachments") or {}
    current = [f for f in attachments.get("files") or [] if extension(f) and f.get("download_url")]
    archived = [f for folder in attachments.get("folders") or []
                for f in folder.get("attachments") or [] if extension(f) and f.get("download_url")]
    # Use current slides ahead of an explicitly archived older version.
    return sorted(current or archived, key=lambda f: (FORMATS.index(extension(f)), -int(f.get("id") or 0)))


def speaker_name(person):
    value = person.get("name") or " ".join(filter(None, (person.get("firstName"), person.get("familyName"))))
    value = re.sub(r"^(?:(?:Dr|Mr|Ms|Mrs|Prof)\.?\s+)+", "", value, flags=re.I)
    return " ".join(p.capitalize() if p.isupper() and len(p) > 2 else p for p in value.split()) or "Unknown speaker"


def slug(text):
    text = re.sub(r"['’]", "", text).replace("—", "-").replace("–", "-")
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^A-Za-z0-9]+", "-", text).strip("-") or "Untitled"


def event_prefix(page_html, event_number):
    title = re.search(r"<title\b[^>]*>(.*?)</title>", page_html, re.I | re.S)
    text = html.unescape(title.group(1)) if title else ""
    match = re.search(r"\bOARC\s*[-–]?\s*(\d+)\b", text, re.I)
    return "OARC" + match.group(1) if match else "event-{}".format(event_number)


def filename_for(talk, suffix, claimed, event_label):
    speakers = talk.get("presenters") or [{"name": "Unknown speaker"}]
    prefix = event_label + "_" + "-and-".join(slug(speaker_name(p)) for p in speakers) + "_"
    title = slug(talk.get("title") or "Untitled")
    name = prefix + title + suffix
    if len(name) > 240 or (name in claimed and claimed[name] != talk["contributionId"]):
        tag = "-talk-{}".format(talk["contributionId"])
        prefix = prefix[:160]
        name = prefix + title[:240 - len(prefix) - len(tag) - len(suffix)].rstrip("-") + tag + suffix
    claimed[name] = talk["contributionId"]
    return name


def validate(body, suffix):
    """Check file signatures and Office ZIP integrity without extra packages."""
    if suffix == ".pdf":
        if b"%PDF-" not in body[:1024] or b"%%EOF" not in body[-65536:]:
            raise ValueError("Response is not a complete PDF")
    elif suffix in (".pptx", ".ppsx", ".odp", ".key"):
        with zipfile.ZipFile(io.BytesIO(body)) as archive:
            if archive.testzip() is not None:
                raise ValueError("Presentation ZIP integrity check failed")
            names = set(archive.namelist())
            if suffix in (".pptx", ".ppsx") and "ppt/presentation.xml" not in names:
                raise ValueError("Response is not a PowerPoint presentation")
            if suffix == ".odp" and ("mimetype" not in names or archive.read("mimetype").strip() != b"application/vnd.oasis.opendocument.presentation"):
                raise ValueError("Response is not an OpenDocument presentation")
    elif not body.startswith(bytes.fromhex("d0cf11e0a1b11ae1")):
        raise ValueError("Response is not a legacy PowerPoint presentation")


def atomic_write(path, body):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=str(path.parent), prefix=".oarc-", delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(body)
        os.replace(str(temporary), str(path))
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def main(timetable_url, argv=None):
    parser = argparse.ArgumentParser(
        prog="download_oarc.sh",
        description="Download presentations for a DNS-OARC Indico event. Prefer PDF, then other slide formats.",
        epilog="Requires Python 3.8+; no pip packages. Every run fetches the timetable and presentation files again. "
               "Matching filenames are refreshed only after validation. Missing/restricted slides are recorded in index.csv. "
               "The ZIP contains files downloaded in this run, plus the index.")
    parser.add_argument("event_number", type=int, help="Indico event number, e.g. 58 (not the OARC workshop number)")
    parser.add_argument("output_directory", nargs="?", help="Destination (default: ./PREFIX_presentations)")
    parser.add_argument("--prefix", help="Override the prefix derived from the event title, e.g. OARC47")
    parser.add_argument("--cookies", metavar="FILE", help="Optional Netscape-format cookies.txt from your own signed-in browser; file stays local")
    parser.add_argument("--no-zip", action="store_true", help="Download files and index.csv without creating a ZIP")
    parser.add_argument("--list", action="store_true", help="List the current talks and available formats without downloading files")
    args = parser.parse_args(argv)
    if args.event_number < 1:
        parser.error("event_number must be positive")

    cookie_jar = http.cookiejar.MozillaCookieJar()
    if args.cookies:
        cookie_jar.load(str(Path(args.cookies).expanduser()), ignore_discard=True)
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookie_jar))
    print("Fetching timetable: {}".format(timetable_url), flush=True)
    page_html = fetch(opener, timetable_url).decode("utf-8")
    talks = parse_talks(page_html)
    event_label = slug(args.prefix) if args.prefix else event_prefix(page_html, args.event_number)
    print("Filename prefix: {}".format(event_label), flush=True)
    if args.list:
        for talk in talks:
            formats = ", ".join(dict.fromkeys(extension(f) for f in candidates(talk))) or "no slides posted"
            print("{} | {} | {}".format("; ".join(speaker_name(p) for p in talk.get("presenters") or []), talk.get("title", ""), formats))
        print("{} talks; {} have slide files listed (access not checked).".format(len(talks), sum(bool(candidates(c)) for c in talks)))
        return 0

    output = Path(args.output_directory or (event_label + "_presentations")).expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    rows, included, claimed = [], [], {}
    base_url = urllib.parse.urljoin(timetable_url, "/")
    for number, talk in enumerate(talks, 1):
        attachments = candidates(talk)
        start = talk.get("startDate") or {}
        row = dict(status="No presentation file published", filename="",
                   speakers="; ".join(speaker_name(p) for p in talk.get("presenters") or []),
                   title=talk.get("title", "Untitled"), date=start.get("date", ""),
                   time=start.get("time", ""), timezone=start.get("tz", ""),
                   talk_url=urllib.parse.urljoin(base_url, talk.get("url") or "/event/{}/contributions/{}/".format(args.event_number, talk["contributionId"])),
                   download_url="", original_filename="", bytes="", sha256="", notes="")
        errors, restricted, attempted_urls = [], 0, []
        for attachment in attachments:
            suffix = extension(attachment)
            url = urllib.parse.urljoin(base_url, attachment["download_url"])
            attempted_urls.append(url)
            try:
                body = fetch(opener, url)
                validate(body, suffix)
                filename = filename_for(talk, suffix, claimed, event_label)
                atomic_write(output / filename, body)
                row.update(status="Downloaded", filename=filename, download_url=url,
                           original_filename=attachment.get("title", ""), bytes=len(body),
                           sha256=hashlib.sha256(body).hexdigest())
                included.append(output / filename)
                break
            except AccessRequired as exc:
                restricted += 1
                errors.append("{}: {}".format(attachment.get("title", suffix), exc))
            except (OSError, urllib.error.URLError, ValueError, zipfile.BadZipFile) as exc:
                errors.append("{}: {}".format(attachment.get("title", suffix), exc))
        else:
            if attachments:
                row["status"] = "Sign-in required" if restricted == len(attachments) else "Download failed"
                row["download_url"] = "; ".join(attempted_urls)
                row["original_filename"] = "; ".join(f.get("title", "") for f in attachments)
        row["notes"] = " | ".join(errors)
        rows.append(row)
        print("[{}/{}] {}: {}".format(number, len(talks), row["status"], row["title"]), flush=True)

    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
    index = output / "index.csv"
    atomic_write(index, stream.getvalue().encode("utf-8-sig"))

    if not args.no_zip:
        archive_path = output.parent / (output.name + ".zip")
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(dir=str(output.parent), prefix=".oarc-", delete=False) as handle:
                temporary = Path(handle.name)
            with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
                for path in included + [index]:
                    archive.write(path, event_label + "/" + path.name)
            os.replace(str(temporary), str(archive_path))
        finally:
            if temporary is not None and temporary.exists():
                temporary.unlink()
        print("ZIP: {}".format(archive_path))

    statuses = Counter(row["status"] for row in rows)
    formats = Counter(path.suffix for path in included)
    print("\nDownloaded {} presentation(s): {}".format(len(included), ", ".join("{} {}".format(count, suffix) for suffix, count in sorted(formats.items())) or "none"))
    print("{} require sign-in; {} have no slides posted; {} failed.".format(
        statuses["Sign-in required"], statuses["No presentation file published"], statuses["Download failed"]))
    print("Index: {}".format(index))
    return 1 if statuses["Download failed"] else 0


if __name__ == "__main__":
    if sys.version_info < (3, 8):
        sys.exit("Python 3.8 or newer is required.")
    try:
        source_url = sys.argv.pop(1)  # Expanded from URL_TEMPLATE by the Bash launcher.
        sys.exit(main(source_url))
    except KeyboardInterrupt:
        sys.exit("\nStopped. Run the script again to refresh the downloads.")
    except Exception as exc:
        sys.exit("Error: {}".format(exc))
PYTHON
