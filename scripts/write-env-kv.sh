#!/bin/bash
# this is a mess need to rewrite in rust :)

usage() {
    echo "Usage: $0 [-d|--dry-run] <key_vault_url> <path_to_env_file>"
    exit 1
}

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    usage
fi

dry_run=false

if [ "$1" == "-d" ] || [ "$1" == "--dry-run" ]; then
    if [ "$#" -ne 3 ]; then
        usage
    fi
    dry_run=true
    key_vault_url="$2"
    env_file_path="$3"
else
    key_vault_url="$1"
    env_file_path="$2"
fi

env_secret_names=""
while IFS= read -r line; do
    if [[ "${line}" == \#* ]] || [[ -z "${line// }" ]]; then
        continue
    fi
    secret_name=$(echo "${line}" | cut -d'=' -f1)
    env_secret_names="${env_secret_names} ${secret_name}"
done < "${env_file_path}"

secrets=$(az keyvault secret list --vault-name "${key_vault_url}")
enabled_secret_ids=$(echo "${secrets}" | jq '.[] | select(.attributes.enabled == true) | .id')

while IFS= read -r secret_id; do
    secret_id=$(echo "${secret_id}" | tr -d '"')
    secret_name=$(basename "${secret_id}")

    if [[ "${env_secret_names}" =~ (^|[[:space:]])"${secret_name}"($|[[:space:]]) ]]; then
        secret_value=$(grep -F "${secret_name}=" "${env_file_path}" | cut -d'=' -f2-)
        if [ "${dry_run}" = true ]; then
            echo "Would update secret: ${secret_name} with value: ${secret_value}"
        else
            az keyvault secret set --vault-name "${key_vault_url}" --name "${secret_name}" --value "${secret_value}"
            echo "Updated secret: ${secret_name}"
        fi
    else
        if [ "${dry_run}" = true ]; then
            echo "Would delete secret: ${secret_name}"
        else
            az keyvault secret delete --vault-name "${key_vault_url}" --name "${secret_name}"
            echo "Deleted secret: ${secret_name}"
        fi
    fi
done <<< "${enabled_secret_ids}"

while IFS= read -r line; do
    if [[ "${line}" == \#* ]] || [[ -z "${line// }" ]]; then
        continue
    fi
    IFS="=" read -ra secret_parts <<< "${line}"
    secret_name="${secret_parts[0]}"
    secret_value="${secret_parts[1]}"
    secret_name=$(echo "${secret_name}" | tr '_' '-')
    if ! grep -q "${secret_name}" <<< "${enabled_secret_ids}"; then
        if [ "${dry_run}" = true ]; then
            echo "Would create secret: ${secret_name} with value: ${secret_value}"
        else
            az keyvault secret set --vault-name "${key_vault_url}" --name "${secret_name}" --value "${secret_value}"
            echo "Created secret: ${secret_name}"
        fi
    fi
done < "${env_file_path}"

if [ "${dry_run}" = true ]; then
    echo "Dry run completed. No changes were made to the Azure Key Vault."
else
    echo "All secrets from the .env file were synced to the Azure Key Vault. Secrets not in the .env file were deleted."
fi
