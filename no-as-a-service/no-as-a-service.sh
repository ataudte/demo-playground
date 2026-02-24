#!/bin/bash

# Check for user input
if [ $# -eq 0 ]; then
    echo "Usage: $0 <your yes/no question>"
    exit 1
fi

QUESTION="$*"

# Normalize input: lowercase and remove punctuation at the start
QUESTION_NORMALIZED=$(echo "$QUESTION" | tr '[:upper:]' '[:lower:]' | sed 's/^[^a-zA-Z]*//')

# Extract first word of the question
FIRST_WORD=$(echo "$QUESTION_NORMALIZED" | awk '{print $1}')

# Common yes/no question starters
YESNO_STARTERS="can could should would will do does did is are was were have has had may might must"

# Validate yes/no question
if ! echo "$YESNO_STARTERS" | grep -qw "$FIRST_WORD"; then
    echo "That doesn't look like a yes/no question."
    exit 1
fi

# Dictionary source
DICT="/usr/share/dict/words"

# Get random noun (simple suffix-based guess)
get_random_noun() {
    grep -E "^[a-z]{4,}$" "$DICT" | grep -vE "[A-Z]" | \
    grep -Ei '(tion|ment|ness|ity|ship|age|ance|ence|hood|ism|ist|ure|dom|er|or)$' | \
    sort -R | head -n 1
}

# Get random verb
get_random_verb() {
    grep -E "^[a-z]{4,}$" "$DICT" | grep -vE "[A-Z]" | \
    grep -Ei '(ate|fy|en|ize|ing|ed)$' | \
    sort -R | head -n 1
}

# Get random adverb (ends with -ly)
get_random_adverb() {
    grep -Ei "^[a-z]{4,}ly$" "$DICT" | grep -vE "[A-Z]" | \
    sort -R | head -n 1
}

# Fetch words
NOUN=$(get_random_noun)
VERB=$(get_random_verb)
ADVERB=$(get_random_adverb)

# Final response
echo "Q: $QUESTION"
echo "A: No, because $NOUN $VERB $ADVERB."
