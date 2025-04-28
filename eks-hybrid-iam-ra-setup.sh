#!/usr/bin/env bash

exec >&2
set -eu -o pipefail

declare -r HOST_ROOTFS="/.bottlerocket/rootfs"
declare -r SECRETS_DIR="${HOST_ROOTFS}/root/.aws"
declare -r EKS_HYBRID_AWS_DIR="/root/.aws/eks-hybrid"
declare -r EKS_HYBRID_SHARED_CREDENTIALS_FILE="${EKS_HYBRID_AWS_DIR}/credentials"
declare -r EKS_HYBRID_POD_IDENTITY_AWS_DIR="${HOST_ROOTFS}/var/eks-hybrid/.aws"
declare -r SIGNING_HELPER_SERVICE="aws-signing-helper-update.service"
declare -r SIGNING_HELPER_SERVICE_TEMPLATE_PATH="/usr/share/bootstrap/${SIGNING_HELPER_SERVICE}.in"
declare -r SYSTEMD_UNIT_DIR="${HOST_ROOTFS}/run/systemd/system"
declare -r SIGNING_HELPER_SERVICE_PATH="${SYSTEMD_UNIT_DIR}/${SIGNING_HELPER_SERVICE}"

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

get_aws-signing-helper-update_command() {
    local credential_process_from_config
    credential_process_from_config="$(AWS_CONFIG_FILE="$1" aws configure get profile.default.credential_process)"
    if [ -n "${credential_process_from_config}" ]; then
        echo "${credential_process_from_config/aws_signing_helper credential-process/aws_signing_helper update}"
    else
        echo "Error: No credential_process found in default profile" >&2
        return 1
    fi
}

cat << EOF > "${SECRETS_DIR}/node.crt"
${NODE_CERT_DATA}
EOF

cat << EOF > "${SECRETS_DIR}/node.key"
${NODE_KEY_DATA}
EOF

if [ "${DRY_RUN}" = "true" ]; then
  exit 0
fi

SIGNING_HELPER_UPDATE_COMMAND="$(get_aws-signing-helper-update_command ${SECRETS_DIR}/config)"
export EKS_HYBRID_SHARED_CREDENTIALS_FILE SIGNING_HELPER_UPDATE_COMMAND
# shellcheck disable=SC2016 # we want to replace the variables verbatim
envsubst '${EKS_HYBRID_SHARED_CREDENTIALS_FILE}:${SIGNING_HELPER_UPDATE_COMMAND}' \
    < "${SIGNING_HELPER_SERVICE_TEMPLATE_PATH}" \
    > "${SIGNING_HELPER_SERVICE_PATH}"
chroot "${HOST_ROOTFS}" systemctl enable "${SIGNING_HELPER_SERVICE}" --no-reload --quiet
mkdir -p "$(dirname "${EKS_HYBRID_POD_IDENTITY_AWS_DIR}")"
ln -sf "${EKS_HYBRID_AWS_DIR}" "${EKS_HYBRID_POD_IDENTITY_AWS_DIR}"

variant_id="$(apiclient get os.variant_id | jq -r '.os.variant_id')"
version_id="$(apiclient get os.version_id | jq -r '.os.version_id')"
apiclient set \
    "settings.kubernetes.node-labels.\"os.bottlerocket.aws/variant\""="${variant_id}" \
    "settings.kubernetes.node-labels.\"os.bottlerocket.aws/version\""="${version_id}"
