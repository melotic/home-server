#!/bin/bash
set -eou pipefail
export TERM=xterm-256color

echo -e "🔎 Checking Netdata alarms...\n"

url="http://localhost:19999/api/v1/alarms"
response=$(curl -s -o - "$url")

if [[ -z "$response" ]]; then
    echo "Failed to fetch alarms"
    exit 1
fi

alarms=$(echo "$response" | jq -r '.alarms')
alarm_count=$(echo "$alarms" | jq 'length')

if [[ $alarm_count -gt 0 ]]; then
    echo -e "❌ $alarm_count alarms are firing!\n"
    echo "$alarms" | jq -r 'to_entries[] | "\(.key): \(.value.value)"'
    exit 1
fi

echo $response | jq -C

echo -e "\n$(tput setaf 2)✔ No alarms detected$(tput sgr0)"
exit 0
