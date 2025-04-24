FROM public.ecr.aws/amazonlinux/amazonlinux:2023 AS builder

ARG SSM_AGENT_VERSION
ENV SSM_AGENT_VERSION=$SSM_AGENT_VERSION

# Validation
RUN : "${SSM_AGENT_VERSION:?SSM Agent version required to build}"

# SSM Agent is downloaded from eu-north-1 as this region gets new releases of SSM Agent first.
COPY ./hashes/ssm ./hashes
COPY ./gpg-keys/amazon-ssm-agent.gpg ./amazon-ssm-agent.gpg
RUN \
    ARCH=$(uname -m | sed 's/aarch64/arm64/' | sed 's/x86_64/amd64/') && \
    curl -L "https://s3.eu-north-1.amazonaws.com/amazon-ssm-eu-north-1/${SSM_AGENT_VERSION}/linux_${ARCH}/amazon-ssm-agent.rpm" \
        -o "amazon-ssm-agent-${SSM_AGENT_VERSION}.${ARCH}.rpm" && \
    grep "amazon-ssm-agent-${SSM_AGENT_VERSION}.${ARCH}.rpm" hashes \
        | sha512sum --check - && \
    rpm --import amazon-ssm-agent.gpg && \
    rpm --checksig "amazon-ssm-agent-${SSM_AGENT_VERSION}.${ARCH}.rpm" && \
    dnf install -y "amazon-ssm-agent-${SSM_AGENT_VERSION}.${ARCH}.rpm"

FROM public.ecr.aws/amazonlinux/amazonlinux:2023

# IMAGE_VERSION is the assigned version of inputs for this image.
ARG IMAGE_VERSION
ENV IMAGE_VERSION=$IMAGE_VERSION

# Validation
RUN : "${IMAGE_VERSION:?IMAGE_VERSION is required to build}"

LABEL "org.opencontainers.image.version"="$IMAGE_VERSION"

# Install necessary packages
RUN dnf update -y && \
    dnf install -y \
        aws-cli \
        jq \
        util-linux \
        e2fsprogs \
        xfsprogs \
        lvm2 \
        mdadm \
        rsync \
        gettext && \
    dnf clean all

# Verify that all packages are installed
RUN \
    command -v aws && \
    command -v jq && \
    command -v lsblk && \
    command -v mkfs.ext4 && \
    command -v mkfs.xfs && \
    command -v lvm && \
    command -v mdadm && \
    command -v rsync && \
    command -v envsubst

# Copy the wrapper script and EKS Hybrid setup scripts into the container
COPY bootstrap-script.sh /usr/local/bin/bootstrap-script.sh
COPY eks-hybrid-ssm-setup.sh /usr/local/bin/eks-hybrid-ssm-setup
COPY eks-hybrid-iam-ra-setup.sh /usr/local/bin/eks-hybrid-iam-ra-setup
COPY aws-signing-helper-update.service.in /usr/share/bootstrap/aws-signing-helper-update.service.in

# Copy the SSM agent from the builder stage
COPY --from=builder /usr/bin/amazon-ssm-agent /usr/local/bin/amazon-ssm-agent

# Set the wrapper script as the entry point
ENTRYPOINT ["/usr/local/bin/bootstrap-script.sh"]
