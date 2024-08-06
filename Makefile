IMAGE_NAME = bottlerocket-bootstrap-container:latest

.PHONY: all build clean

# Run all build tasks for this container image
all: build_amd64 build_arm64

# Build the container image for the amd64 architecture
build_amd64:
	docker build --tag $(IMAGE_NAME)-amd64 -f Dockerfile .

# Build the container image for the arm64 architecture
build_arm64:
	docker build --tag $(IMAGE_NAME)-arm64 -f Dockerfile .

# Clean up the build artifacts (if there are any to clean)
clean:
	rm -f $(IMAGE_NAME)
