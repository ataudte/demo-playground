# dns_look-a-like.sh

## Description
Demo script for generating **look‑alike domain names** (homoglyph / typo‑style variants) based on a legitimate base domain.

The script creates visually or structurally similar domain names that are commonly used in:
- Phishing demonstrations
- DNS security awareness
- Detection testing (typosquatting / look‑alike domains)

It is designed purely for **education, demos, and testing**, not for abuse.

---

## Usage
Make the script executable and run it with a base domain:

```bash
chmod +x dns_look-a-like.sh
./dns_look-a-like.sh example.com
```

---

## Requirements
- Bash (tested with Bash 4+)
- Standard Unix utilities (sed, awk, tr)

No external libraries or network access required.

---

## Input / Output
- **Input:**  
  A single fully qualified domain name passed as a command‑line argument.

- **Output:**  
  List of generated look‑alike domain names printed to STDOUT.

---

## Notes
- Generated domains are **not validated or registered**; the script performs no DNS lookups.
- The character substitutions are intentionally simple and deterministic for clarity.
- Intended as a teaching and demo tool, not a comprehensive typosquatting engine.
- Useful in combination with DNS logging, RPZ demos, or security workshops.

---

## License
This script is covered under the repository’s main [MIT License](../LICENSE).
