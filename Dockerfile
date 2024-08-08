FROM public.ecr.aws/amazonlinux/amazonlinux:2023

# Install necessary packages
RUN yum update -y 
    
RUN yum install -y \
    aws-cli \
    jq \
    util-linux \
    e2fsprogs \
    xfsprogs \
    lvm2 \
    mdadm && \
    yum clean all

# Verify that all packages are installed
RUN \
    command -v aws && \
    command -v jq && \
    command -v lsblk && \
    command -v mkfs.ext4 && \
    command -v mkfs.xfs && \
    command -v lvm && \
    command -v mdadm

# Copy the wrapper script into the container
COPY bootstrap-script.sh /usr/local/bin/bootstrap-script.sh

# Set the wrapper script as the entry point
ENTRYPOINT ["/usr/local/bin/bootstrap-script.sh"]
