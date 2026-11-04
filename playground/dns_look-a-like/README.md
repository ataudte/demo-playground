# dns_look-a-like.sh

## Description
Generates **look-a-like (homoglyph) domain variants** and prints their **Punycode** representation.

What it does:
- Takes a domain name as input
- Splits it into:
  - **LEFT**: everything except the last label
  - **TLD**: the last label
- Replaces ASCII characters in **LEFT** with visually similar Unicode homoglyphs (Cyrillic, Greek, and Latin extensions)
- Prints each modified domain and its Punycode form (label-by-label conversion)

This is useful for:
- Defensive testing and awareness work around IDN homograph / phishing risk
- Quickly seeing how Unicode variants map to `xn--` Punycode

---

## Usage
```bash
./dns_look-a-like.sh <domain>
```

Example:
```bash
./dns_look-a-like.sh example.com
./dns_look-a-like.sh my-service.internal
```

Output format (per candidate):
- `original:` / `modified:` domain
- `punycode:` label-by-label Punycode using `idn -t -a`

---

## Requirements
- Bash
- `idn` command available in PATH  
  - Provided by GNU **libidn** or **libidn2** packages on many systems
- UTF-8 capable terminal recommended (so homoglyphs render correctly)

---

## Input / Output
- **Input:** One domain name as a single argument (e.g. `example.com`)
- **Output:** Printed to stdout
  - Original domain and its Punycode
  - One modified candidate per supported ASCII character found in the LEFT part, plus its Punycode

---

## Notes
- **TLD is not modified.** Only the portion before the last dot is subject to replacement.
- This script generates **one replacement at a time** (not all combinations).  
  Example: if multiple replaceable characters exist, you will get one output per character type, not every permutation.
- Some homoglyphs are **font-dependent** and may not look identical in all environments.
- This is intended for **testing/awareness**. Do not use it for abuse.

---

## License
This script is covered under the repository’s main [MIT License](../LICENSE).
