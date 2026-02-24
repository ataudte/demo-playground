# gen_phrase.sh

## Description
Generates **10 random corporate-buzzword phrases** by combining an adjective, a noun, a verb, and an adverb, then prints them to stdout (one per line).

Example output:
- `Dynamic Innovation disrupts collaboratively.`
- `Customer-centric Strategy accelerates strategically.`

---

## Usage
Make the script executable and run it:

```bash
chmod +x gen_phrase.sh
./gen_phrase.sh
```

---

## Requirements
- Bash (works on most Linux/macOS systems; also works in WSL on Windows)
- No external dependencies

---

## Input / Output
- **Input:** None (phrase components are defined in arrays inside the script).
- **Output:** 10 lines of text printed to stdout, each in the form:

  `<Adjective> <Noun> <Verb> <Adverb>.`

---

## Notes
- Uses Bash’s `$RANDOM` for selection, which is **not cryptographically secure** (fine for fun text generation).
- To change how many phrases are printed, adjust the loop:
  - `for i in {1..10}; do ...` → change `10` to your desired count.
- You can customize the phrase “style” by editing the arrays:
  - `adjectives=(...)`, `nouns=(...)`, `verbs=(...)`, `adverbs=(...)`
- The adverb list currently contains `optimaly` (typo). If you want, change it to `optimally`.

---

## License
This script is covered under the repository’s main [MIT License](../LICENSE).
