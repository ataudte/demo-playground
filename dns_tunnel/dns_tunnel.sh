#!/bin/bash

# Client script to simulate sending a file as DNS hostnames
if [ "$1" == "client" ]; then

    # Check if the file parameter is provided
    if [ "$#" -ne 2 ]; then
        echo "Usage: $0 client <file-to-send>"
        exit 1
    fi

    INPUT_FILE="$2"
    LOG_FILE="dns_tunnel.log"
    RANDOM_DOMAIN=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-z' | fold -w 8 | head -n 1).com

    # Create a clean log file
    > "$LOG_FILE"

    # Split the file into base64 chunks and generate hostnames
    base64 -i "$INPUT_FILE" | while read -r LINE; do
        # Split the base64 string into smaller chunks of up to 63 characters (valid hostname limit)
        while [ -n "$LINE" ]; do
            CHUNK=${LINE:0:63}
            LINE=${LINE:63}
            echo "$CHUNK.$RANDOM_DOMAIN" >> "$LOG_FILE"
        done
    done

    echo "File encoded as DNS hostnames and saved to $LOG_FILE"

# Server script to reconstruct a file from DNS hostnames log
elif [ "$1" == "server" ]; then

    # Check if the log file parameter is provided
    if [ "$#" -ne 2 ]; then
        echo "Usage: $0 server <log-file>"
        exit 1
    fi

    LOG_FILE="$2"
    OUTPUT_DIR="tunnel"
    OUTPUT_FILE="$OUTPUT_DIR/reconstructed_file"

    # Create the output directory if it doesn't exist
    mkdir -p "$OUTPUT_DIR"

    # Extract base64 content from hostnames in the log file
    awk -F '.' '{print $1}' "$LOG_FILE" | base64 -D -o "$OUTPUT_FILE"

    if [ $? -eq 0 ]; then
        echo "File successfully reconstructed and saved to $OUTPUT_FILE"
    else
        echo "An error occurred during reconstruction."
    fi

else
    echo "Invalid mode. Use 'client' or 'server'."
    exit 1
fi
