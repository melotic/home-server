#! /bin/bash
# Checks if the .env file has all the secrets set.
echo -e "🔐 Checking secrets...\n"

regex="[A-Z_-]{2,}"
stderr=$(docker compose config -q 2>&1 >/dev/null)
filtered=$(echo "$stderr" | grep -oP "$regex")
sorted=$(echo "$filtered" | sort | uniq)

while read -r line; do
    if [[ ${#line} -gt 0 ]]; then
        echo "The $(tput setaf 1)$line$(tput sgr0) secret is not set!"
    fi
done <<< "$sorted"

echo -en "\n"

[[ ${#stderr} -gt 0 ]] && echo "❌ some secrets are not set" && exit 1

echo "✅ All secrets are set"
exit 0