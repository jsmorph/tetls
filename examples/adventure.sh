#!/bin/bash

# This script requires adventure.js, which contains the Javascript
# we'll execute.  See adventure-transcript.txt for example output.

if [ -z "$TEO_AUTH" ]; then
    echo "Need TEO_AUTH"; exit 1
fi

FILENAME=${1:-adventure.sh}

set -e

# Format our request.
jq -n --rawfile src "$FILENAME" '{arg: "'$OPENAI_API_KEY'",source: ($src | split("\n"))}' > request.json

# Execute the code and get the result and attestation.
curl -H "X-TEO-Authorization: $TEO_AUTH" -X POST -d @request.json https://api.tetls.net/js |
    tee adventure.json |
    jq -r .parsed_response_body.parsed_response.rolls

# Format the output nicely.
cat adventure.json |
    jq -r .parsed_response_body.parsed_response.rolls |
    jq -r '
  to_entries[] as $entry |
  (
    $entry.value.prompt | fromjson as $p |
    "## Roll \($entry.key + 1)\n\n\($p.text)\n\nPossible actions:\n" +
    ($p.actions | map("  - " + .) | join("\n")) +
    "\n\nAction taken: \($entry.value.action)\n"
  )
' | tee adventure-transcript.txt

