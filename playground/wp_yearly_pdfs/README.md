# wp_yearly_pdfs.py

## Description
Builds one PDF per year from all images found in the posts of any public WordPress blog.  
Each PDF page shows a single image with the post title and publication date underneath. The year is the post's publication year.

Key features:
- Collects posts via the WordPress REST API (`/wp-json/wp/v2/posts`), with automatic fallback to scraping the HTML pages.
- Includes featured images and images embedded in the post content; prefers the full-size original over WordPress thumbnails (`-300x200` style suffixes are stripped).
- Every image is used only once across the whole blog (oldest post first).
- Skips icons, emojis, avatars and tracking pixels (by URL pattern and minimum pixel size).
- Page orientation follows the image (landscape A4 / portrait A4); EXIF rotation and transparency are handled.
- Captions use the first system TrueType font that covers all characters (Latin, Cyrillic, Greek, CJK, Korean).
- Downloaded images are cached, so an interrupted run can simply be restarted.
- Self-managing environment: on first run it creates a private virtual environment (`.wp_pdf_venv` next to the script), installs missing packages there and re-launches itself. Nothing is installed globally.

Example: *Turn the whole photo archive of `https://ataudte.de/` into one PDF per year.*

---

## Usage
```bash
python3 wp_yearly_pdfs.py https://ataudte.de/
python3 wp_yearly_pdfs.py example.com/blog --years 2024 2025
python3 wp_yearly_pdfs.py example.com --max-px 2400 --workers 8
python3 wp_yearly_pdfs.py example.com --reset-env     # rebuild the private environment
python3 wp_yearly_pdfs.py example.com --no-venv       # use the current Python instead
```

### Arguments

| Argument | Description | Default |
|---|---|---|
| `url` | Address of the WordPress blog (scheme optional, e.g. `example.com/blog`) | *required* |
| `--out DIR` | Output folder | `<host>_pdfs` |
| `--years Y [Y ...]` | Only build these years | all years |
| `--max-px N` | Longest image edge in the PDF, in pixels | `2000` |
| `--min-px N` | Skip images smaller than this (icons, spacers) | `300` |
| `--workers N` | Parallel downloads | `4` |
| `--delay SEC` | Pause per request in seconds (be polite to the server) | `0.2` |
| `--font PATH` | TrueType font for captions | best matching system font |
| `--no-featured` | Ignore featured images | off |
| `--html-only` | Skip the REST API and scrape the HTML pages | off |
| `--reset-env` | Delete and rebuild the private virtual environment | off |
| `--no-venv` | Use the current Python instead of a private venv (missing packages are installed there) | off |

---

## Requirements
- Python 3.8+
- Internet access (for the blog and, on first run, for `pip`)
- External modules (installed automatically into `.wp_pdf_venv`):
  - requests
  - beautifulsoup4
  - pillow
  - reportlab
- Optional: a Unicode TrueType font for captions. The script looks for DejaVu Sans, FreeSans, WenQuanYi, Droid Sans Fallback, Nanum Gothic (Linux), Arial / Arial Unicode (macOS) and Arial, Segoe UI, Microsoft YaHei, MS Gothic, Malgun Gothic, SimSun (Windows). Use `--font` to supply your own.
- On Debian/Ubuntu, creating the venv may require: `sudo apt install python3-venv` (or use `--no-venv`).

---

## Input / Output
- **Input:** The URL of a public WordPress blog (positional argument). If no scheme is given, HTTPS is tried first, then HTTP. If the posts live under a sub-path (e.g. `/blog/`), pass that full URL.
- **Output:**
  - `./<host>_pdfs/<host>_<year>.pdf`: one PDF per year (if the blog URL contains a path, it becomes part of the name, e.g. `example.com_blog_2024.pdf`)
  - `./<host>_pdfs/cache/`: cached image downloads
  - Progress and a final per-year summary (images used, images skipped) are printed to stderr.

---

## Notes
- Works only with public WordPress blogs; password-protected or private content is not accessible.
- REST API results are used first; if the API is unavailable or disabled, the script falls back to scraping listing pages and individual posts (`--html-only` forces this).
- Images without a usable post date are assigned to the year found in their `/uploads/YYYY/` path, otherwise to `unknown`.
- Only the first frame of animated images (e.g. GIF) is used. Images are re-encoded as JPEG (quality 85) inside the PDF; transparent areas become white.
- Image formats depend on the installed Pillow build (e.g. AVIF may not be supported everywhere); unreadable files are skipped and reported.
- Requests are throttled (`--delay`) and retried on HTTP 429/5xx. Please respect the blog owner's terms and copyright when using or sharing the resulting PDFs.
- If the environment breaks (e.g. after a Python upgrade), run once with `--reset-env`.
- Press `Ctrl+C` to stop; run again to resume from the cache.
- Related docs: [WordPress REST API Handbook](https://developer.wordpress.org/rest-api/)

---

## License
This script is covered under the repository’s main [MIT License](../LICENSE).  
