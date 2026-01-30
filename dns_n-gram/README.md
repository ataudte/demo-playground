# dns_n-gram.sh

## Description
Demo script for **analyzing domain labels using bi-grams and tri-grams** and comparing them against an English dictionary.

The script extracts the hostname part of a fully qualified domain name, splits it on dashes, generates:
- all **trigrams (3-grams)**
- all **bigrams (2-grams)**

It then checks whether these n-grams appear as:
- full English words
- common English prefixes or suffixes

This is useful for:
- DNS security demos
- DGA vs. human-readable domain analysis
- Teaching basic lexical analysis techniques used in detection systems

---

## Usage
Make the script executable and run it with a single FQDN:

```bash
chmod +x dns_n-gram.sh
./dns_n-gram.sh example-domain.com
```

The script prints each generated n-gram with a short classification and ends with a simple percentage indicating how “English-like” each hostname label is.

---

## Requirements
- Bash (tested with Bash 4+)
- Standard Unix utilities: `cut`, `grep`, `bc`
- Local English dictionary file:
  - `/usr/share/dict/words`

No network access required.

---

## Input / Output
- **Input:**  
  - One fully qualified domain name passed as `$1`

- **Output:**  
  - Per n-gram classification:
    - valid English word
    - common English prefix/suffix
    - not an English word
  - Summary percentage per hostname label indicating how many n-grams matched English words

All output is written to STDOUT.

---

## Notes
- Only the hostname (string before the first dot) is analyzed.
- Hostnames are split on dashes and evaluated per segment.
- N-gram size is **fixed** to bi-grams and tri-grams; there is no configurable `$2` parameter.
- Dictionary-based detection is intentionally simple and deterministic.
- Intended as a **demo and teaching tool**, not a production-grade detection engine.

---

## License
This script is covered under the repository’s main [MIT License](../LICENSE).
