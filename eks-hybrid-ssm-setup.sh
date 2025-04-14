#!/usr/bin/env bash

exec >&2
set -eu -o pipefail

HOST_ROOTFS="/.bottlerocket/rootfs"
SSM_AGENT_PERSISTENT_STATE_DIR="${HOST_ROOTFS}/local/host-containers/control/ssm"
SSM_AGENT_REGISTRATION="${SSM_AGENT_PERSISTENT_STATE_DIR}/registration"
mkdir -p "${SSM_AGENT_PERSISTENT_STATE_DIR}"
ENABLE_CREDENTIALS_FILE="false"
SSM_ACTIVATION_ID_REGEX="^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"

for opt in "$@"; do
    optarg="$(expr "${opt}" : '[^ =]*[= ]\(.*\)')"
    case "${opt}" in
        --region=*) AWS_REGION="${optarg}" ;;
        --activation-code=*) SSM_ACTIVATION_CODE="${optarg}" ;;
        --activation-id=*) SSM_ACTIVATION_ID="${optarg}" ;;
        --enable-credentials-file=*) ENABLE_CREDENTIALS_FILE="${optarg}" ;;
    esac
done

validate_activation_id() {
    if ! [[ "${SSM_ACTIVATION_ID}" =~ ${SSM_ACTIVATION_ID_REGEX} ]]; then
        echo "Error: Invalid activation ID format" >&2
        exit 1
    fi
}

register_hybrid_node() {
    amazon-ssm-agent \
        -register \
        -region "${AWS_REGION}" \
        -code "${SSM_ACTIVATION_CODE}" \
        -id "${SSM_ACTIVATION_ID}" \
        -disableSimilarityCheck
}

persist_ssm_state() {
    rsync -aq \
        /var/lib/amazon/ssm/ \
        "${SSM_AGENT_PERSISTENT_STATE_DIR}"
}

set_hostname_settings() {
    local ssm_node_id
    local cluster_name
    local variant_id
    local version_id
    ssm_node_id="$(jq -r '.ManagedInstanceID' "${SSM_AGENT_PERSISTENT_STATE_DIR}/registration")"
    cluster_name="$(apiclient get settings.kubernetes.cluster-name | jq -r ".settings.kubernetes.\"cluster-name\"")"
    variant_id="$(apiclient get os.variant_id | jq -r '.os.variant_id')"
    version_id="$(apiclient get os.version_id | jq -r '.os.version_id')"

    apiclient set \
        network.hostname="${ssm_node_id}" \
        kubernetes.hostname-override="${ssm_node_id}" \
        kubernetes.provider-id="eks-hybrid:///${AWS_REGION}/${cluster_name}/${ssm_node_id}" \
        "settings.kubernetes.node-labels.\"os.bottlerocket.aws/variant\""="${variant_id}" \
        "settings.kubernetes.node-labels.\"os.bottlerocket.aws/version\""="${version_id}"
}

symlink_aws_creds() {
    local control_aws_dir
    local control_aws_dir_relative_to_host
    local control_creds
    local host_creds
    local hybrid_nodes_pod_identity_aws_dir
    control_aws_dir="${HOST_ROOTFS}/run/host-containerd/io.containerd.runtime.v2.task/default/control/rootfs/root/.aws"
    control_aws_dir_relative_to_host="/run/host-containerd/io.containerd.runtime.v2.task/default/control/rootfs/root/.aws"
    control_creds="${control_aws_dir}/credentials"
    host_creds="${HOST_ROOTFS}/root/.aws/credentials"
    ln -srnf "${control_creds}" "${host_creds}"
    if [ "${ENABLE_CREDENTIALS_FILE}" = "true" ]; then
        hybrid_nodes_pod_identity_aws_dir="${HOST_ROOTFS}/var/eks-hybrid/.aws"
        mkdir -p "$(dirname "${hybrid_nodes_pod_identity_aws_dir}")"
        ln -sf "${control_aws_dir_relative_to_host}" "${hybrid_nodes_pod_identity_aws_dir}"
    fi
}

if [ ! -s "${SSM_AGENT_REGISTRATION}" ]; then
    validate_activation_id
    register_hybrid_node
    persist_ssm_state
    set_hostname_settings
fi

symlink_aws_creds
