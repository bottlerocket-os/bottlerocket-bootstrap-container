# Bottlerocket Control Container

This is the bootstrap container for the [Bottlerocket](https://github.com/bottlerocket-os/bottlerocket) operating system. This container 
image allows the user to provide their own script to run bootstrap commands to setup their own configuration during runtime. 

## Using the Container Image

For more information on settings, please refer to the [Bottlerocket Documentation](https://bottlerocket.dev/) in order to configure your files. 
To use the container image, create a TOML file with the following configurations. 

### Sample TOML configuration

```toml
[settings.bootstrap-containers.myscript]
source="<URI to ECR Repository for this Bootstrap Container>"
mode="once"
user-data="user-base64-encoded-bootstrap-script"
```

Afterwards, create the Bottlerocket instance using the TOML file. 
The settings that you changed within the user's bootstrap script should be seen within the bottlerocket instance. 

### Example Walkthrough

This example assumes that you have access to AWS services and the necessary permissions to create and manage EC2 instances.

Given a user data similar to the below:

```sh
#!/usr/bin/env sh
set -euo pipefail

# Create the directory
mkdir -p /var/lib/my_directory

# Set API client configurations
apiclient set --json '{"settings": {"oci-defaults": {"resource-limits": {"max-open-files": {"soft-limit": 4294967296, "hard-limit": 8589934592}}}}}'

# Load kernel module
if command -v modprobe > /dev/null 2>&1; then
  modprobe dummy
fi

echo "User-data script executed."
```

The user-data script needs to be base64 encoded. Encode the script in base64.

Next, create a TOML file with the necessary settings to use the bootstrap container. 
Replace <URI to ECR Repository for this Bootstrap Container> with the actual URI of the ECR repository.

For example, the TOML file should look like the below if you base64 the given user-data:

```toml
[settings.bootstrap-containers.bear]
source = "<URI to ECR Repository for this Bootstrap Container>"
mode = "once"
user-data = "IyEvdXNyL2Jpbi9lbnYgc2gKc2V0IC1ldW8gcGlwZWZhaWwKCiMgQ3JlYXRlIHRoZSBkaXJlY3RvcnkKbWtkaXIgLXAgL3Zhci9saWIvbXlfZGlyZWN0b3J5CgojIFNldCBBUEkgY2xpZW50IGNvbmZpZ3VyYXRpb25zCmFwaWNsaWVudCBzZXQgLS1qc29uICd7InNldHRpbmdzIjogeyJvY2ktZGVmYXVsdHMiOiB7InJlc291cmNlLWxpbWl0cyI6IHsibWF4LW9wZW4tZmlsZXMiOiB7InNvZnQtbGltaXQiOiA0Mjk0OTY3Mjk2LCAiaGFyZC1saW1pdCI6IDg1ODk5MzQ1OTJ9fX19fScKCiMgTG9hZCBrZXJuZWwgbW9kdWxlCmlmIGNvbW1hbmQgLXYgbW9kcHJvYmUgPiAvZGV2L251bGwgMj4mMTsgdGhlbgogIG1vZHByb2JlIGR1bW15CmZpCgplY2hvICJVc2VyLWRhdGEgc2NyaXB0IGV4ZWN1dGVkLiIK"
```

Afterwards, you can run the Bottlerocket instance using the TOML file and the user-data configurations will be applied. 
Once the instance is up and running, you can verify that the bootstrap process completed successfully. 
You can check the logs of the bootstrap container using the apiclient tool from the admin container.
