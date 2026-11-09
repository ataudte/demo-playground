#!/usr/bin/env python3
"""
wp_yearly_pdfs.py - build one PDF per year from all images in a WordPress blog.

Each page shows one image with its post title and date. Missing packages are
installed automatically into a private venv (.wp_pdf_venv) next to this script.

Usage:
    python3 wp_yearly_pdfs.py https://example.com/
    python3 wp_yearly_pdfs.py example.com/blog --years 2024 2025
    python3 wp_yearly_pdfs.py example.com --reset-env   # rebuild the venv
    python3 wp_yearly_pdfs.py example.com --no-venv     # use current Python

Output: ./<host>_pdfs/<host>_<year>.pdf (downloaded images cached in ./cache)
See README.md for all options and details.
"""
import argparse
import hashlib
import html
import importlib.util
import io
import os
import re
import shutil
import subprocess
import sys
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import urljoin, urlparse, urlunparse

# --------------------------------------------------------------------------
# Environment bootstrap (standard library only)
# --------------------------------------------------------------------------
MIN_PYTHON = (3, 8)
# import name -> pip package name
REQUIRED = {
    "requests": "requests",
    "bs4": "beautifulsoup4",
    "PIL": "pillow",
    "reportlab": "reportlab",
}
VENV_DIR = Path(__file__).resolve().parent / ".wp_pdf_venv"
BOOTSTRAP_FLAG = "WP_PDF_BOOTSTRAPPED"


def _log(msg):
    print(f"[setup] {msg}", file=sys.stderr)


def _fail(msg):
    print(f"\n[setup] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def _venv_python(venv_dir):
    if os.name == "nt":
        return venv_dir / "Scripts" / "python.exe"
    return venv_dir / "bin" / "python"


def _missing_packages():
    return [pip for mod, pip in REQUIRED.items() if importlib.util.find_spec(mod) is None]


def _pip_install(python, packages):
    _log(f"Installing missing packages: {', '.join(packages)}")
    cmd = [str(python), "-m", "pip", "install", "--disable-pip-version-check", "-q", *packages]
    if subprocess.call(cmd) != 0:
        _fail("pip could not install " + ", ".join(packages) + ".\n"
              "        Check your internet connection / proxy, then run again.\n"
              "        Manual fallback: " + " ".join(cmd))


def _create_venv(venv_dir):
    import venv
    _log(f"Creating virtual environment in {venv_dir}")
    try:
        venv.EnvBuilder(with_pip=True, clear=True).create(venv_dir)
    except Exception as e:
        shutil.rmtree(venv_dir, ignore_errors=True)
        hint = ""
        if sys.platform.startswith("linux"):
            v = f"{sys.version_info.major}.{sys.version_info.minor}"
            hint = (f"\n        On Debian/Ubuntu install it with: sudo apt install python{v}-venv"
                    "\n        Or run with --no-venv to use the current Python.")
        _fail(f"could not create the virtual environment ({e}).{hint}")


def bootstrap():
    """Make sure we run inside a working environment with all packages present."""
    if sys.version_info < MIN_PYTHON:
        _fail(f"Python {'.'.join(map(str, MIN_PYTHON))}+ required, "
              f"found {sys.version.split()[0]}.")

    use_venv = "--no-venv" not in sys.argv
    in_our_venv = Path(sys.prefix).resolve() == VENV_DIR.resolve()

    if use_venv and not in_our_venv:
        if os.environ.get(BOOTSTRAP_FLAG):
            _fail("relaunch loop detected; the virtual environment seems broken. "
                  "Run again with --reset-env.")
        py = _venv_python(VENV_DIR)
        if "--reset-env" in sys.argv and VENV_DIR.exists():
            _log("Removing existing environment (--reset-env)")
            shutil.rmtree(VENV_DIR)
        # (Re)create if missing or broken (e.g. Python was upgraded/moved)
        if not py.exists() or subprocess.call(
                [str(py), "-c", "import pip"], stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL) != 0:
            _create_venv(VENV_DIR)
        env = dict(os.environ, **{BOOTSTRAP_FLAG: "1"})
        args = [a for a in sys.argv[1:] if a != "--reset-env"]
        sys.exit(subprocess.call([str(py), str(Path(__file__).resolve()), *args], env=env))

    missing = _missing_packages()
    if missing:
        if not use_venv:
            _log("--no-venv: installing into the current Python environment")
        _pip_install(sys.executable, missing)
        importlib.invalidate_caches()
        still = _missing_packages()
        if still:
            _fail("packages still not importable after install: " + ", ".join(still))
    _log("Environment OK (" + sys.executable + ")")


if __name__ == "__main__":
    bootstrap()

# --------------------------------------------------------------------------
# Third-party imports (available once bootstrap() has run)
# --------------------------------------------------------------------------
import requests
from bs4 import BeautifulSoup
from PIL import Image, ImageOps
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; wp-yearly-pdfs/1.0)"}
IMG_EXT = re.compile(r"\.(jpe?g|png|webp|gif|avif|bmp|tiff?)$", re.I)
SIZE_SUFFIX = re.compile(r"-\d+x\d+(?=\.\w+$)")  # WordPress thumbnail suffix
SKIP_URL = re.compile(
    r"(gravatar\.com|s\.w\.org|/wp-includes/|/emoji/|wpcom-smileys|"
    r"stats\.wp\.com|pixel\.wp\.com|feedburner|/plugins/.*/(icons?|images)/)", re.I)
# Caption fonts, tried in order; for each caption the first font that has every
# character is used (Latin/Cyrillic/Greek first, then CJK/Korean fallbacks).
# Only TrueType-outline fonts work with ReportLab; others are skipped silently.
FONT_CANDIDATES = [
    # Linux
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
    "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
    "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
    "/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf",
    "/usr/share/fonts/truetype/arphic/uming.ttc",
    "/usr/share/fonts/truetype/nanum/NanumGothic.ttf",
    # macOS
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/Library/Fonts/Arial.ttf",
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "/Library/Fonts/Arial Unicode.ttf",
    # Windows
    r"C:\Windows\Fonts\arial.ttf",
    r"C:\Windows\Fonts\segoeui.ttf",
    r"C:\Windows\Fonts\arialuni.ttf",
    r"C:\Windows\Fonts\msyh.ttc",
    r"C:\Windows\Fonts\msgothic.ttc",
    r"C:\Windows\Fonts\malgun.ttf",
    r"C:\Windows\Fonts\simsun.ttc",
]

session = requests.Session()
session.headers.update(HEADERS)
DELAY = 0.2


def log(msg, end="\n"):
    print(msg, end=end, file=sys.stderr, flush=True)


# --------------------------------------------------------------------------
# HTTP helpers
# --------------------------------------------------------------------------
def get(url, params=None):
    """GET with retries for transient errors. Returns the response (any status)."""
    last = None
    for attempt in range(4):
        try:
            time.sleep(DELAY)
            r = session.get(url, params=params, timeout=30)
            if r.status_code in (429, 500, 502, 503, 504):
                last = f"HTTP {r.status_code}"
                time.sleep(3 * (attempt + 1))
                continue
            return r
        except (requests.ConnectionError, requests.Timeout) as e:
            last = e
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"Failed to fetch {url} ({last})")


def normalize_base(url):
    if not re.match(r"https?://", url, re.I):
        url = "https://" + url
    p = urlparse(url)
    path = p.path if p.path.endswith("/") else p.path + "/"
    return urlunparse((p.scheme, p.netloc, path, "", "", ""))


def clean_image_url(u):
    """Drop fragments; drop the query on plain image files (resize params, ?ver=)."""
    p = urlparse(u)
    query = "" if IMG_EXT.search(p.path) else p.query
    return urlunparse((p.scheme, p.netloc, p.path, "", query, ""))


# --------------------------------------------------------------------------
# Image discovery
# --------------------------------------------------------------------------
def _largest_from_srcset(srcset):
    best, best_w = None, -1
    for part in srcset.split(","):
        bits = part.strip().split()
        if not bits:
            continue
        w = 0
        if len(bits) > 1 and bits[1][:-1].replace(".", "").isdigit():
            w = float(bits[1][:-1]) * (1000 if bits[1].endswith("x") else 1)
        if w > best_w:
            best, best_w = bits[0], w
    return best


def _img_src(img):
    for attr in ("data-orig-file", "data-large-file"):
        if img.get(attr):
            return img[attr]
    for attr in ("srcset", "data-srcset", "data-lazy-srcset"):
        if img.get(attr):
            s = _largest_from_srcset(img[attr])
            if s:
                return s
    for attr in ("data-lazy-src", "data-src", "data-original", "src"):
        v = img.get(attr)
        if v and not v.startswith("data:"):
            return v
    return None


def images_from_html(fragment, page_url):
    """
    Return image candidates in document order. Each item is a list of URLs to
    try in order: the original upload first, then the URL as found in the page.
    """
    soup = BeautifulSoup(fragment, "html.parser")
    found = []
    linked_imgs = set()
    for el in soup.find_all(["a", "img"]):
        if el.name == "a":
            href = el.get("href", "")
            if href and IMG_EXT.search(urlparse(href).path):
                found.append(href)
                linked_imgs.update(id(i) for i in el.find_all("img"))
        elif id(el) not in linked_imgs:
            src = _img_src(el)
            if src:
                found.append(src)

    out, seen = [], set()
    for raw in found:
        u = clean_image_url(urljoin(page_url, raw.strip()))
        if not u.startswith("http") or SKIP_URL.search(u):
            continue
        original = SIZE_SUFFIX.sub("", u)
        if original in seen:
            continue
        seen.add(original)
        out.append([original] if original == u else [original, u])
    return out


# --------------------------------------------------------------------------
# Post collection: REST API first, HTML scraping as fallback
# --------------------------------------------------------------------------
def rest_roots(base, home):
    roots = []
    link = home.links.get("https://api.w.org/", {}).get("url") if home is not None else None
    if link:
        roots.append(link)
    if home is not None and "html" in home.headers.get("content-type", ""):
        tag = BeautifulSoup(home.text, "html.parser").find("link", rel="https://api.w.org/")
        if tag and tag.get("href"):
            roots.append(tag["href"])
    roots += [base + "wp-json/", base + "?rest_route=/"]
    out = []
    for r in roots:
        r = r if r.endswith("/") else r + "/"
        if r not in out:
            out.append(r)
    return out


def collect_via_rest(base, home, include_featured):
    for root in rest_roots(base, home):
        endpoint = root + "wp/v2/posts"
        params = {"per_page": 100, "page": 1}
        if include_featured:
            params["_embed"] = "wp:featuredmedia"
        r = get(endpoint, params)
        try:
            data = r.json() if r.status_code == 200 else None
        except ValueError:
            data = None
        if not isinstance(data, list):
            continue
        log(f"Using REST API: {endpoint}")
        posts, page = [], 1
        total = int(r.headers.get("X-WP-TotalPages", 1) or 1)
        while True:
            for p in data:
                title = BeautifulSoup(html.unescape(p.get("title", {}).get("rendered", "")),
                                      "html.parser").get_text().strip()
                link = p.get("link") or base
                imgs = []
                if include_featured:
                    for m in (p.get("_embedded", {}).get("wp:featuredmedia") or []):
                        if isinstance(m, dict) and m.get("source_url"):
                            imgs.append([clean_image_url(m["source_url"])])
                imgs += images_from_html(p.get("content", {}).get("rendered", ""), link)
                posts.append({"date": (p.get("date") or "")[:10], "title": title, "images": imgs})
            log(f"  page {page}/{total}", end="\r")
            if page >= total:
                break
            page += 1
            params["page"] = page
            r = get(endpoint, params)
            if r.status_code != 200:
                break
            data = r.json()
            if not data:
                break
        log("")
        return posts
    return None


def _post_links_from_listing(soup, base_host):
    links = []
    blocks = soup.find_all("article") or soup.select(".hentry, .post, .type-post")
    for b in blocks:
        a = (b.find("a", rel="bookmark")
             or b.select_one(".entry-title a, h1 a, h2 a, h3 a"))
        if a and a.get("href") and urlparse(a["href"]).netloc in ("", base_host):
            links.append(a["href"])
    return links


def _next_page(soup):
    tag = (soup.find("link", rel="next")
           or soup.select_one("a.next, a[rel~=next], .nav-previous a, .older-posts a"))
    return tag.get("href") if tag else None


def _parse_post(url):
    r = get(url)
    if r.status_code != 200:
        return None
    soup = BeautifulSoup(r.text, "html.parser")
    date = ""
    meta = soup.find("meta", property="article:published_time")
    if meta and meta.get("content"):
        date = meta["content"][:10]
    else:
        t = soup.select_one("time.published[datetime], time.entry-date[datetime], time[datetime]")
        if t:
            date = t["datetime"][:10]
    og = soup.find("meta", property="og:title")
    h = soup.select_one("h1.entry-title, .entry-title, article h1, h1")
    title = (h.get_text(strip=True) if h else "") or (og.get("content", "") if og else "")
    container = soup.find("article") or soup.find("main") or soup.body or soup
    return {"date": date, "title": title, "images": images_from_html(str(container), r.url)}


def collect_via_html(base, workers):
    log("Using HTML pages (REST API not available)")
    host = urlparse(base).netloc
    url, seen_pages, post_links = base, set(), []
    while url and url not in seen_pages:
        seen_pages.add(url)
        r = get(url)
        if r.status_code != 200:
            break
        soup = BeautifulSoup(r.text, "html.parser")
        links = _post_links_from_listing(soup, host)
        if not links:
            break
        post_links += [urljoin(r.url, l) for l in links]
        log(f"  listing page {len(seen_pages)}: {len(post_links)} posts so far", end="\r")
        nxt = _next_page(soup)
        url = urljoin(r.url, nxt) if nxt else None
    log("")
    post_links = list(dict.fromkeys(post_links))
    posts = []
    with ThreadPoolExecutor(workers) as ex:
        for i, p in enumerate(ex.map(_parse_post, post_links), 1):
            log(f"  reading posts {i}/{len(post_links)}", end="\r")
            if p:
                posts.append(p)
    log("")
    return posts


# --------------------------------------------------------------------------
# Downloading and PDF building
# --------------------------------------------------------------------------
def download(candidates, cache_dir, min_px):
    """Return a local path for the first candidate that downloads as a usable image."""
    for url in candidates:
        ext = (IMG_EXT.search(urlparse(url).path) or [".img"])[0].lower()
        path = cache_dir / (hashlib.sha1(url.encode()).hexdigest()[:20] + ext)
        if not path.exists():
            try:
                r = get(url)
            except RuntimeError:
                continue
            if r.status_code != 200 or not r.content:
                continue
            path.write_bytes(r.content)
        try:
            with Image.open(path) as im:
                if max(im.size) < min_px:
                    return None  # icon / spacer / emoji
            return path
        except Exception:
            path.unlink(missing_ok=True)  # not an image (HTML error page etc.)
    return None


def load_image(path, max_px):
    im = Image.open(path)
    if getattr(im, "is_animated", False):
        im.seek(0)
    im = ImageOps.exif_transpose(im)
    if im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info):
        im = im.convert("RGBA")
        bg = Image.new("RGB", im.size, "white")
        bg.paste(im, mask=im.split()[-1])
        im = bg
    else:
        im = im.convert("RGB")
    im.thumbnail((max_px, max_px), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=85, optimize=True)
    buf.seek(0)
    return buf, im.size


class CaptionFonts:
    """Picks, per caption, the first available font that covers every character."""

    def __init__(self, user_font=None):
        self.fonts = []  # (name, set of code points)
        if user_font and not self._add(user_font):
            log(f"! could not load font {user_font} (must be TrueType), using system fonts")
        for path in FONT_CANDIDATES:
            self._add(path)
        if not self.fonts:
            log("! no Unicode TrueType font found, captions use Helvetica "
                "(non-Latin titles may show boxes; use --font)")

    def _add(self, path):
        if not Path(path).is_file():
            return False
        name = f"Caption{len(self.fonts)}"
        try:
            kw = {"subfontIndex": 0} if path.lower().endswith(".ttc") else {}
            font = TTFont(name, path, **kw)
            pdfmetrics.registerFont(font)
        except Exception:
            return False
        self.fonts.append((name, set(font.face.charToGlyph)))
        return True

    def for_text(self, text):
        needed = {ord(ch) for ch in text if not ch.isspace()}
        for name, cmap in self.fonts:
            if needed <= cmap:
                return name
        if self.fonts:  # nothing covers all: take the one covering the most
            return max(self.fonts, key=lambda f: len(needed & f[1]))[0]
        return "Helvetica"


def fit_text(text, font, size, max_w):
    if pdfmetrics.stringWidth(text, font, size) <= max_w:
        return text
    while text and pdfmetrics.stringWidth(text + "…", font, size) > max_w:
        text = text[:-1]
    return text.rstrip() + "…"


def build_pdf(path, doc_title, items, fonts, max_px):
    c = canvas.Canvas(str(path))
    c.setTitle(doc_title)
    margin, caption_h = 28, 36
    pages = 0
    for it in items:
        try:
            buf, (w, h) = load_image(it["file"], max_px)
        except Exception as e:
            log(f"  ! skipped {it['file'].name}: {e}")
            continue
        pw, ph = landscape(A4) if w >= h else A4
        c.setPageSize((pw, ph))
        avail_w, avail_h = pw - 2 * margin, ph - 2 * margin - caption_h
        scale = min(avail_w / w, avail_h / h)
        dw, dh = w * scale, h * scale
        c.drawImage(ImageReader(buf), (pw - dw) / 2,
                    margin + caption_h + (avail_h - dh) / 2, dw, dh)
        font = fonts.for_text(it["title"])
        c.setFont(font, 11)
        c.drawCentredString(pw / 2, margin + 18, fit_text(it["title"], font, 11, avail_w))
        c.setFont(fonts.for_text(it["date"]), 9)
        c.drawCentredString(pw / 2, margin + 4, it["date"])
        c.showPage()
        pages += 1
    if pages:
        c.save()
    return pages


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
def main():
    global DELAY
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("url", help="address of the WordPress blog, e.g. https://example.com/blog")
    ap.add_argument("--out", help="output folder (default: <host>_pdfs)")
    ap.add_argument("--years", nargs="*", help="only build these years")
    ap.add_argument("--max-px", type=int, default=2000, help="longest image edge in the PDF (default 2000)")
    ap.add_argument("--min-px", type=int, default=300,
                    help="skip images smaller than this, e.g. icons (default 300)")
    ap.add_argument("--workers", type=int, default=4, help="parallel downloads (default 4)")
    ap.add_argument("--delay", type=float, default=0.2, help="pause per request in seconds (default 0.2)")
    ap.add_argument("--font", help="TrueType font for captions (default: best matching system font)")
    ap.add_argument("--no-featured", action="store_true", help="ignore featured images")
    ap.add_argument("--html-only", action="store_true", help="skip the REST API, scrape pages")
    ap.add_argument("--reset-env", action="store_true", help="delete and rebuild the private environment")
    ap.add_argument("--no-venv", action="store_true", help="use the current Python instead of a private venv")
    args = ap.parse_args()
    DELAY = max(0.0, args.delay)

    base = normalize_base(args.url)
    log(f"Checking {base}")
    home = None
    if not re.match(r"https?://", args.url, re.I):
        try:  # no scheme given: quick HTTPS probe, then fall back to HTTP
            home = session.get(base, timeout=15)
        except requests.RequestException:
            base = "http://" + base[len("https://"):]
            log(f"HTTPS not available, trying {base}")
    if home is None:
        home = get(base)
    if home.status_code >= 400:
        raise RuntimeError(f"{base} answered HTTP {home.status_code}")
    base = normalize_base(home.url)  # follow redirects (http→https, www, …)
    host = urlparse(base).netloc
    slug = re.sub(r"[^\w.-]", "_", (host + urlparse(base).path).strip("/"))

    out_dir = Path(args.out or f"{slug}_pdfs")
    cache_dir = out_dir / "cache"
    cache_dir.mkdir(parents=True, exist_ok=True)

    posts = None if args.html_only else collect_via_rest(base, home, not args.no_featured)
    if posts is None:
        posts = collect_via_html(base, args.workers)
    if not posts:
        sys.exit("No posts found. Is this a public WordPress blog? "
                 "If the posts live under a different address (e.g. /blog/), pass that URL.")

    # One entry per image, oldest first, each image only once across the blog
    entries, seen = [], set()
    for p in sorted(posts, key=lambda p: p["date"] or "9999"):
        for cand in p["images"]:
            if cand[0] in seen:
                continue
            seen.add(cand[0])
            year = p["date"][:4]
            if not year.isdigit():
                m = re.search(r"/uploads/(\d{4})/", cand[0])
                year = m.group(1) if m else "unknown"
            entries.append({"year": year, "date": p["date"], "title": p["title"], "cand": cand})

    by_year = defaultdict(list)
    for e in entries:
        by_year[e["year"]].append(e)
    years = [y for y in sorted(by_year) if not args.years or y in args.years]
    log(f"Found {len(posts)} posts, {len(entries)} images, years: {', '.join(sorted(by_year))}")

    fonts = CaptionFonts(args.font)
    results = []
    for year in years:
        items = by_year[year]
        log(f"{year}: downloading {len(items)} images")
        with ThreadPoolExecutor(args.workers) as ex:
            files = list(ex.map(lambda e: download(e["cand"], cache_dir, args.min_px), items))
        usable = []
        for e, f in zip(items, files):
            if f:
                usable.append(dict(e, file=f))
        path = out_dir / f"{slug}_{year}.pdf"
        n = build_pdf(path, f"{host} – {year}", usable, fonts, args.max_px)
        results.append((year, n, len(items) - n, path if n else None))
        log(f"  ✓ {path} ({n} pages)" if n else f"  – no usable images for {year}")

    log("\nSummary")
    for year, n, skipped, path in results:
        extra = f", {skipped} skipped (small/broken)" if skipped else ""
        log(f"  {year}: {n} images{extra}" + (f" → {path}" if path else ""))


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit("\nInterrupted. Run again to resume (downloaded images are cached).")
    except RuntimeError as e:
        sys.exit(f"\nERROR: {e}\nCheck the address and your internet connection, then run again "
                 "(downloaded images are cached).")
