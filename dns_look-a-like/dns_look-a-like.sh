#!/bin/bash

# Function to convert string to Punycode (label by label)
to_punycode() {
    local domain="$1"
    local -a labels=()
    IFS="." read -ra parts <<< "$domain"

    for label in "${parts[@]}"; do
        local punycode
        punycode=$(echo "$label" | idn -t -a)
        labels+=("$punycode")
    done

    local IFS="."
    echo "${labels[*]}"
}

# Split into LEFT (everything except last label) and TLD (last label)
split_domain_ignore_tld() {
    local domain="$1"
    local -a parts
    IFS="." read -ra parts <<< "$domain"
    local n=${#parts[@]}

    if (( n >= 2 )); then
        TLD="${parts[$((n-1))]}"
        LEFT="${parts[*]:0:$((n-1))}"
        LEFT="${LEFT// /.}"   # space-joined -> dot-joined
    else
        # No dot: nothing to "ignore"; work on whole string
        TLD=""
        LEFT="$domain"
    fi
}

# Re-join LEFT + TLD
join_domain() {
    local left="$1"
    local tld="$2"

    if [[ -n "$tld" ]]; then
        echo "${left}.${tld}"
    else
        echo "${left}"
    fi
}

# Check if input was provided
if [ -z "$1" ]; then
    echo "Usage: $0 <domain>"
    exit 1
fi

input_string="$1"

split_domain_ignore_tld "$input_string"
original_full="$(join_domain "$LEFT" "$TLD")"

echo "----"
echo "original: $original_full"
echo "punycode: $(to_punycode "$original_full")"

# indexed arrays

ascii_chars=(
  # Cyrillic lookalikes
  "a" "e" "o" "p" "c" "y" "x" "i" "j" "h" "b" "r"
  # Greek lookalikes
  "a" "b" "e" "i" "k" "o" "p" "t" "y" "x" "s" "v"
  # Latin extensions lookalikes
  "z" "s" "g" "u" "i" "l" "i" "i" "l"
  # font-dependent
  "d" "f" "g" "q" "m" "n" "t" "v" "w" "l" "s"
)

homoglyphs=(
  # Cyrillic lookalikes
  "а" "е" "о" "р" "с" "у" "х" "і" "ј" "һ" "ь" "г"
  # Greek lookalikes
  "α" "β" "ε" "ι" "κ" "ο" "ρ" "τ" "υ" "χ" "σ" "ν"
  # Latin extensions lookalikes
  "ƶ" "š" "ğ" "ù" "ı" "ⅼ" "ɩ" "ɪ" "ʟ"
  # font-dependent
  "ԁ" "ƒ" "ɡ" "ԛ" "ｍ" "п" "т" "ѵ" "ѡ" "ӏ" "ѕ"
)

# Apply replacements to LEFT only (everything except last label)
for index in "${!ascii_chars[@]}"; do
    char="${ascii_chars[$index]}"
    if [[ "$LEFT" == *$char* ]]; then
        modified_left="${LEFT//$char/${homoglyphs[$index]}}"
        modified_full="$(join_domain "$modified_left" "$TLD")"
        echo "----"
        echo "modified: $modified_full"
        echo "punycode: $(to_punycode "$modified_full")"
    fi
done

echo "----"