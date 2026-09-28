#!/bin/bash
QUERY=$(node -e "console.log(encodeURIComponent(process.argv[1]))" "$1")
curl -s "https://html.duckduckgo.com/html/?q=$QUERY" | grep -o '<a class="result__url" href="[^"]*">[^<]*</a>' | sed -E 's/<a class="result__url" href="([^"]*)">([^<]*)<\/a>/\2 - \1/' | head -n 5
