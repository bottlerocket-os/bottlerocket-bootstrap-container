# IMAGE_NAME is the full name of the container image being built.
IMAGE_NAME ?= $(notdir $(shell pwd -P))$(IMAGE_ARCH_SUFFIX):$(IMAGE_VERSION)$(addprefix -,$(SHORT_SHA))
# IMAGE_VERSION is the semver version that's tagged on the image.
IMAGE_VERSION = $(shell cat VERSION)
# SHORT_SHA is the revision that the container image was built with.
SHORT_SHA ?= $(shell git describe --abbrev=8 --always --dirty='-dev' --exclude '*' || echo "unknown")
# IMAGE_ARCH_SUFFIX is the runtime architecture designator for the container
# image, it is appended to the IMAGE_NAME unless the name is specified.
IMAGE_ARCH_SUFFIX ?= $(addprefix -,$(ARCH))
# DESTDIR is where the release artifacts will be written.
DESTDIR ?= .
# DISTFILE is the path to the dist target's output file - the container image
# tarball.
DISTFILE ?= $(subst /,,$(DESTDIR))/$(subst /,_,$(IMAGE_NAME)).tar.gz

UNAME_ARCH = $(shell uname -m)
ARCH ?= $(lastword $(subst :, ,$(filter $(UNAME_ARCH):%,x86_64:amd64 aarch64:arm64)))

# SSM_AGENT_VERSION is the SSM Agent's distributed RPM Version to install.
SSM_AGENT_VERSION ?= 3.3.4624.0

TEST_ACTIVATION_ID=abcdef12-3456-7890-abcd-ef1234567890
TEST_ACTIVATION_CODE=abcdef1234567890abcdef
TEST_NODE_CERT=test-certificate
TEST_NODE_KEY=test-key

.PHONY: all build dist check check-ssm-agent check-ssm-setup check-iam-ra-setup clean download-ssm-agent update-ssm-agent

# Run all build tasks for this container image.
all: build check

# Create a distribution container image tarball for release.
dist: all
	@mkdir -p $(dir $(DISTFILE))
	docker save $(IMAGE_NAME) | gzip > $(DISTFILE)

# Build the container image.
build:
	DOCKER_BUILDKIT=1 docker build $(DOCKER_BUILD_FLAGS) \
		--tag $(IMAGE_NAME) \
		--build-arg IMAGE_VERSION="$(IMAGE_VERSION)" \
		--build-arg SSM_AGENT_VERSION="$(SSM_AGENT_VERSION)" \
		-f Dockerfile . >&2

# Run checks against the bootstrap container image
check: check-ssm-agent check-ssm-setup check-iam-ra-setup

# Check that the SSM Agent is the expected version.
check-ssm-agent:
	@echo "Running SSM version check"
	@docker run --rm --entrypoint /usr/bin/bash \
		$(IMAGE_NAME) \
		-c 'amazon-ssm-agent -version | grep -Fw "$(SSM_AGENT_VERSION)"' >&2

# Check that the SSM setup script doesn't print sensitive input
check-ssm-setup:
	@echo "Running SSM setup check"
	@OUTPUT=$$(docker run --rm --entrypoint /usr/bin/bash \
		$(IMAGE_NAME) \
		-c "eks-hybrid-ssm-setup --region=us-west-2 --activation-id=${TEST_ACTIVATION_ID} --activation-code=${TEST_ACTIVATION_CODE} --enable-credentials-file=true 2>&1 || true"); \
	if echo "$$OUTPUT" | grep -q "${TEST_ACTIVATION_ID}"; then \
		echo "Test failed: hybrid activation ID found in output"; \
		exit 1; \
	elif echo "$$OUTPUT" | grep -q "${TEST_ACTIVATION_CODE}"; then \
		echo "Test failed: hybrid activation code found in output"; \
		exit 1; \
	else \
		echo "Test passed: No sensitive content in output"; \
	fi

# Check that the IAM-RA setup script doesn't print sensitive input
check-iam-ra-setup:
	@echo "Running IAM-RA setup check"
	@OUTPUT=$$(docker run --rm --entrypoint /usr/bin/bash \
		$(IMAGE_NAME) \
		-c "eks-hybrid-iam-ra-setup --certificate=${TEST_NODE_CERT} --key=${TEST_NODE_KEY} --dry-run=true 2>&1 || true"); \
	if echo "$$OUTPUT" | grep -q "${TEST_NODE_CERT}"; then \
		echo "Test failed: certificate content found in output"; \
		exit 1; \
	elif echo "$$OUTPUT" | grep -q "${TEST_NODE_KEY}"; then \
		echo "Test failed: private key content found in output"; \
		exit 1; \
	else \
		echo "Test passed: No sensitive content in output"; \
	fi

# Download SSM Agent version SSM_AGENT_VERSION for all architectures.
download-ssm-agent: amazon-ssm-agent-${SSM_AGENT_VERSION}.amd64.rpm amazon-ssm-agent-${SSM_AGENT_VERSION}.arm64.rpm

amazon-ssm-agent-${SSM_AGENT_VERSION}.amd64.rpm:
	curl -L "https://s3.eu-north-1.amazonaws.com/amazon-ssm-eu-north-1/${SSM_AGENT_VERSION}/linux_amd64/amazon-ssm-agent.rpm" \
		-o "amazon-ssm-agent-${SSM_AGENT_VERSION}.amd64.rpm"

amazon-ssm-agent-${SSM_AGENT_VERSION}.arm64.rpm:
	curl -L "https://s3.eu-north-1.amazonaws.com/amazon-ssm-eu-north-1/${SSM_AGENT_VERSION}/linux_arm64/amazon-ssm-agent.rpm" \
		-o "amazon-ssm-agent-${SSM_AGENT_VERSION}.arm64.rpm"

# Update the expected hashes of SSM Agent to those for SSM_AGENT_VERSION.
update-ssm-agent: download-ssm-agent
	sha512sum amazon-ssm-agent-${SSM_AGENT_VERSION}.*.rpm >hashes/ssm

clean:
	rm -f $(DISTFILE)
