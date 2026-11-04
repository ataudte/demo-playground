# download_oarc.sh

## Description

Downloads presentation files from a DNS-OARC Indico event and gives them consistent filenames. The script creates or reuses a Python virtual environment, reads the current timetable, and prefers PDF over other presentation formats. It also generates a CSV index and, by default, a ZIP archive.

The event number fills the URL template defined near the top of the script:

```bash
URL_TEMPLATE='https://indico.dns-oarc.net/event/{event_number}/timetable/#all.detailed'
```

For example, event `58` points to the OARC 47 timetable. The Indico event number and the OARC workshop number are separate values.

---

## Usage

Run the script with the Indico event number:

```bash
bash /path/to/download_oarc.sh EVENT_NUMBER [output-directory] [options]
```

Download presentations for event 58 using the default destination:

```bash
bash /path/to/download_oarc.sh 58
```

Choose a destination, preview the timetable, or use an existing authenticated session:

```bash
bash /path/to/download_oarc.sh 58 ~/Downloads/OARC47
bash /path/to/download_oarc.sh 58 --list
bash /path/to/download_oarc.sh 58 --cookies ~/Downloads/cookies.txt
```

| Option | Purpose |
| --- | --- |
| `--prefix PREFIX` | Override the filename prefix and the default output-directory prefix, for example `--prefix OARC47`. |
| `--cookies FILE` | Load a Netscape-format cookie file exported from your own signed-in browser. Site permissions still apply. |
| `--no-zip` | Generate presentation files and `index.csv` without creating a ZIP. |
| `--list` | Preview talk titles and listed formats. This still sets up the environment and fetches the timetable; file access is not checked. |
| `-h`, `--help` | Show compact help. |

The script creates `.oarc-downloader-venv` beside itself on the first run and reuses it on later runs. It invokes that environment's Python directly; manual activation and package installation are unnecessary.

---

## Requirements

- macOS with Bash; the launcher uses syntax compatible with Bash 3.2.
- Python 3.8 or newer, including the standard `venv` module. The default interpreter is `python3`.
- Internet access to the timetable and its linked presentation files.
- Write access to the environment directory and the output location.

The downloader uses only Python's standard library. No pip packages are required.

Check your Python installation with:

```bash
python3 --version
```

---

## Input / Output

**Input**

| Input | Meaning |
| --- | --- |
| `EVENT_NUMBER` | Required positive Indico event number taken from `/event/NUMBER/` in the URL, for example `58`. |
| `output-directory` | Optional destination. Defaults to `PREFIX_presentations` in the directory from which you run the command. |
| Cookie file | Optional authenticated session supplied with `--cookies`. |

The prefix comes from the event page title, for example `OARC47`. If the title has no recognized OARC number, the prefix is `event-EVENT_NUMBER`. Use `--prefix` to choose it explicitly.

**Output**

- Presentation files named `PREFIX_<speaker-name>_<title-of-talk>.<extension>`.
- `index.csv` inside the output directory, listing discovered talks, status, speakers, titles, event dates/times and timezones, source URLs, original filenames, byte sizes, SHA-256 checksums, and any download errors.
- A ZIP beside the output directory, named `<output-directory-name>.zip`, containing successful downloads from the current run and `index.csv` under a `PREFIX/` folder.

With the default settings for event 58, the output directory is `OARC47_presentations` and the archive is `OARC47_presentations.zip`. An example filename is:

```text
OARC47_John-Todd_Cuckoo-Clock-Managing-billions-of-names.pdf
```

Supported extensions, in preference order: `.pdf`, `.pptx`, `.ppt`, `.odp`, `.key`, `.ppsx`, `.pps`. Files retain their original format and bytes; the script does not convert them to PDF.

---

## Notes

- Each run fetches the current timetable and presentation files again. Existing filenames are refreshed after the downloaded file passes validation. Files left from earlier runs may remain in the output directory; the ZIP reflects the current run.
- Spaces and punctuation in filenames become hyphens, accents are transliterated, and speaker honorifics are removed. Multiple speakers are joined with `-and-`. Long or colliding filenames receive a talk-ID suffix and may be shortened.
- Current slide attachments take precedence over archived versions. Archived files are considered when no current slide attachments are listed. Reference links and attachments without a supported presentation extension are skipped.
- Restricted slides are recorded as `Sign-in required`. Talks without slide attachments are recorded as `No presentation file published`. Other unsuccessful downloads are recorded as `Download failed`; valid downloads are recorded as `Downloaded`.
- `--list` previews availability as advertised in the timetable. Downloading the files checks whether access is allowed.
- If Indico changes the embedded timetable structure, the parser may need updating. Change `URL_TEMPLATE` if the host or timetable URL structure changes.

Environment settings are optional:

| Variable | Default | Purpose |
| --- | --- | --- |
| `OARC_VENV_DIR` | `.oarc-downloader-venv` beside the script | Choose another virtual-environment location. |
| `OARC_PYTHON` | `python3` | Choose the interpreter used when creating a new environment. Existing environments are reused. |

For example:

```bash
OARC_VENV_DIR="$HOME/.venvs/oarc-downloader" bash /path/to/download_oarc.sh 58
```

Common exit codes:

| Code | Meaning |
| --- | --- |
| `0` | Completed, listed talks, or displayed help. Missing and restricted slides are reported without making the run fail. |
| `1` | A download failed or another runtime error occurred. |
| `2` | Invalid or missing command-line arguments. |
| `127` | The interpreter needed to create the environment was not found. |

---

## License

This script is covered under the repository’s main [MIT License](../LICENSE).
