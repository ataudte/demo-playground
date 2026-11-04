#!/bin/bash

# Check if a parameter is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 [FQDN]"
    exit 1
fi

fqdn=$1
worddb="/usr/share/dict/words"

# Validate FQDN (allow only a-z, A-Z, 0-9, and dashes)
if ! [[ $fqdn =~ ^[a-zA-Z0-9.-]+$ ]]; then
    echo "Invalid FQDN. Only alphanumeric characters and dashes are allowed."
    exit 2
fi

# Function to generate bigrams and trigrams
generate_ngrams() {
    local word=$1
    local length=${#word}
    # Generate trigrams
    for ((i=0; i<=length-3; i++)); do
        echo "${word:i:3}"
    done
    # Generate bigrams
    for ((i=0; i<=length-2; i++)); do
        echo "${word:i:2}"
    done
}

# Function to check if a word is in the dictionary
is_english_word() {
    local word=$1
    grep -q "^$word$" "$worddb"
}

# Common English prefixes and suffixes
common_prefixes="un- re- in- im- il- ir- dis- en- em- non- over- mis- sub- pre- inter- fore- de- trans- super- semi- anti- mid- under-"
common_suffixes="-ly -ful -less -ness -ment -tion -sion -cion -er -or -ist -ian -an -ive -able -ible -al -ial -ed -ing -ize -ise -ous -ious -eous -ship -dom -hood"

# Extract only the hostname (string before the first dot)
hostname=$(echo "$fqdn" | cut -d '.' -f 1)

# Split hostname on dashes and process each part
IFS='-' read -ra ADDR <<< "$hostname"
for word in "${ADDR[@]}"; do
    # Initialize counters
    total_count=0
    valid_count=0

    # Analyze each word
	for ngram in $(generate_ngrams "$word"); do
		((total_count++))
		if is_english_word "$ngram"; then
			((valid_count++))
			# Check if ngram is a bigram (length 2), if so, add an extra space
			if [ ${#ngram} -eq 2 ]; then
				echo "$ngram  - valid word in English"
			else
				echo "$ngram - valid word in English"
			fi
		elif [[ $common_prefixes =~ (^|[[:space:]])$ngram(-|$) ]] || [[ $common_suffixes =~ (^|-)$ngram($|[[:space:]]) ]]; then
			# Add extra space for bigrams in echo
			if [ ${#ngram} -eq 2 ]; then
				echo "$ngram  - common prefix/suffix in English"
			else
				echo "$ngram - common prefix/suffix in English"
			fi
		else
			# Add extra space for bigrams in echo
			if [ ${#ngram} -eq 2 ]; then
				echo "$ngram  - not a valid word in English"
			else
				echo "$ngram - not a valid word in English"
			fi
		fi
	done

    # Calculate and print percentage for each word
    if [ "$total_count" -ne 0 ]; then
        percentage=$(echo "scale=2; $valid_count / $total_count * 100" | bc)
        echo "     '$word' is $percentage% an English word (according to $worddb)"
    else
        echo "no valid n-grams found in '$word'"
    fi
done
