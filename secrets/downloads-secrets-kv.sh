#!/bin/bash
set -eou pipefail


if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <key_vault_name>"
    exit 1
fi

echo -e "🔐 Downloading secrets from Azure Key Vault...\n"

secrets=$(az keyvault secret list --vault-name "$1")
enabled_secret_ids=$(echo "${secrets}" | jq '.[] | select(.attributes.enabled == true) | .id')

rm -f .env

while IFS= read -r secret_id; do
    secret_id=$(echo "${secret_id}" | tr -d '"')
    secret_name=$(basename "${secret_id}")
    secret_name_upper=$(echo "${secret_name}" | tr '[:lower:]' '[:upper:]')
    # Replace dashes with underscores
    secret_name_upper=$(echo "${secret_name_upper}" | tr '-' '_')

    echo "Downloading $(tput setaf 4)${secret_name}$(tput sgr0)"

    # the keyvault has quotes in it, i.e. \"secret\". This removes them.
    secret_value=$(az keyvault secret show --id "${secret_id}" | jq '.value' | tr -d '"')

    echo "${secret_name_upper}=${secret_value}" >> .env
done <<< "${enabled_secret_ids}"

echo -e "\n$(tput setaf 2)✔ Secrets downloaded successfully!$(tput sgr0)"