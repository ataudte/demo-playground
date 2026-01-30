#!/bin/bash

# Function to convert string to Punycode
to_punycode() {
    local domain="$1"
    local -a labels=()  # Array to hold the processed labels
    IFS="." read -ra parts <<< "$domain"  # Split the domain into labels using the dot as a delimiter

    # Convert each label to Punycode
    for label in "${parts[@]}"; do
        local punycode=$(echo "$label" | idn -t -a)
        labels+=("$punycode")
    done

    # Join the Punycode labels using dots and return the result
    local IFS="."
    echo "${labels[*]}"
}

# Check if input was provided
if [ -z "$1" ]; then
    echo "Usage: $0 <domain>"
    exit 1
fi

input_string="$1"
echo "----"
echo "original: $input_string"
echo "punycode: $(to_punycode "$input_string")"


# indexed arrays
ascii_chars=("a" "o" "e" "p" "y" "c" "x" "b" "i" "z" "s" "g" "u" "h" "j" "r")
homoglyphs=("а" "ο" "е" "р" "у" "с" "х" "ь" "і" "ƶ" "š" "ğ" "ù" "һ" "ј" "г")

for index in "${!ascii_chars[@]}"; do
    char="${ascii_chars[$index]}"
    if [[ $input_string == *$char* ]]; then
        modified=${input_string//$char/${homoglyphs[$index]}}
        echo "----"
        echo "modified: $modified"
        echo "punycode: $(to_punycode "$modified")"
    fi
done
echo "----"
