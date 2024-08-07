#!/usr/bin/env bash

set -xeuo pipefail

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
