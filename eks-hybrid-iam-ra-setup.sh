#!/usr/bin/env bash

exec >&2
set -eu -o pipefail

declare -r SECRETS_DIR="/.bottlerocket/rootfs/root/.aws"

DRY_RUN="false"
for opt in "$@"; do
    optarg="$(expr "${opt}" : '[^ =]*[= ]\(.*\)')"
    case "${opt}" in
        --certificate=*) NODE_CERT_DATA="${optarg}" ;;
        --key=*) NODE_KEY_DATA="${optarg}" ;;
        --dry-run=*) DRY_RUN="${optarg}" ;;
    esac
done

if [ "${DRY_RUN}" = "true" ]; then
    mkdir -p "${SECRETS_DIR}"
fi

if [ -z "${NODE_CERT_DATA}" ]; then
    echo "Unable to retrieve certificate data for IAM-RA"
    echo "Please provide certificate contents as --certificate=<Certificate>"
    exit 1
fi

if [ -z "${NODE_KEY_DATA}" ]; then
    echo "Unable to retrieve private key data for IAM-RA"
    echo "Please provide private key contents as --key=<Key>"
    exit 1
fi

if ! [ -d "${SECRETS_DIR}" ]; then
    echo "Error: Directory ${SECRETS_DIR} is missing"
    exit 1
fi

if ! [ "${DRY_RUN}" = "true" ]; then
    context=$(stat -c "%C" "${SECRETS_DIR}" 2>/dev/null || echo "")
    if [[ ! "$context" == *":secret_t:"* ]]; then
        echo "Error: Directory ${SECRETS_DIR} is not labeled with secret_t"
    fi
fi

cat << EOF > "${SECRETS_DIR}/node.crt"
${NODE_CERT_DATA}
EOF

cat << EOF > "${SECRETS_DIR}/node.key"
${NODE_KEY_DATA}
EOF

variant_id="$(apiclient get os.variant_id | jq -r '.os.variant_id')"
version_id="$(apiclient get os.version_id | jq -r '.os.version_id')"
apiclient set \
    "settings.kubernetes.node-labels.\"os.bottlerocket.aws/variant\""="${variant_id}" \
    "settings.kubernetes.node-labels.\"os.bottlerocket.aws/version\""="${version_id}"
