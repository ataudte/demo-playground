# no-as-a-service.sh

## Description
Answers any valid yes/no question with a **firm “No”** and a randomly generated, nonsense justification.

What it does:
- Takes your question as a single string (all CLI args)
- Checks whether it *looks like* a yes/no question (based on common starters like `can`, `should`, `is`, `have`, …)
- Pulls random words from the system dictionary and prints:

```
Q: <your question>
A: No, because <noun> <verb> <adverb>.
```

---

## Usage
Make it executable (once):

```bash
chmod +x no-as-a-service.sh
```

Run it with a yes/no question:

```bash
./no-as-a-service.sh "Can I deploy on Friday?"
./no-as-a-service.sh "Should we enable DNSSEC everywhere?"
./no-as-a-service.sh "Is it a good idea to do this in production?"
```

If the input does not resemble a yes/no question, the script exits with an error message.

---

## Requirements
- Bash (tested with typical Linux `/bin/bash`)
- A system word list at:

  - `/usr/share/dict/words`

- Common Unix tools (usually preinstalled):
  - `grep`, `awk`, `sed`, `tr`, `sort`, `head`

---

## Input / Output
- **Input:** One yes/no question passed as command-line arguments (quoted string recommended).
- **Output:** Two lines:
  - `Q: ...` (echoes your question)
  - `A: No, because ...` (randomized excuse)

Exit codes:
- `0` on success
- `1` on missing input or invalid (non-yes/no) question

---

## Notes
- The “noun/verb/adverb” selection is a heuristic based on word endings (suffix matching). It is intentionally silly and not linguistically accurate.
- If your system does not provide `/usr/share/dict/words`, install a wordlist package (name varies by distro) or adapt the `DICT` path in the script.
- Randomness comes from `sort -R`, which may behave differently across platforms.

---

## License
This script is covered under the repository’s main [MIT License](../LICENSE).
