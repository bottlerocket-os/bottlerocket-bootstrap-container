#!/usr/bin/env bash

set -xeuo pipefail

declare -r HOST_CERTS="/.bottlerocket/certs"

# Link host certs if present into container & run update-ca-trust
link_host_certs() {
  for cert in $(ls -1 "${HOST_CERTS}"); do
    ln -s "${HOST_CERTS}/${cert}" "/etc/pki/ca-trust/source/anchors/${cert}"
  done
  # Update the CA trust to pickup the new certificates
  update-ca-trust
}

[[ -d "${HOST_CERTS}" ]] && link_host_certs

# Full path to the base64-encoded user data
USER_DATA_PATH='/.bottlerocket/bootstrap-containers/current/user-data'

# If the user data file is there, not empty, and not a directory, make it executable
if [[ -s "${USER_DATA_PATH}" ]] && [[ ! -d "${USER_DATA_PATH}" ]]; then
    chmod +x "${USER_DATA_PATH}"

    # If the decoded script is there and executable, then execute it.
    if [ -x "${USER_DATA_PATH}" ]; then
        exec "${USER_DATA_PATH}"
    else
        echo "ERROR: User bootstrap script not found or not executable: ${USER_DATA_PATH}" >&2
        exit 1
    fi
else
    echo "ERROR: User data not found or is a directory: ${USER_DATA_PATH}" >&2
    exit 1
fi
