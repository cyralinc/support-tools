# Support-Tools
Scripts and tools to help support setups


# Sidecar Tools

## Sidecar Log Collection

Single command to collect sidecar logs

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/cyralinc/support-tools/main/sidecar/sidecar-log-collection.sh)"
```
This command will create a `cyral_support.tar.gz` file for submission.

This can be run via  [AWS CloudShell](console.aws.amazon.com/cloudshell)

## Environment Variables

This script can be run without a menu if the proper environment variables are set.

Set `COLLECTION_TYPE` to one of the following `ASG` `EC2` `Kubernetes` `SSH` (Case sensitive) to trigger automatic collection.
Below are the variable required for each type of collection.

### ASG Variables

|Variable|Description|
|---|---|
|ASG|Name of the ASG to collect from|
|REGION|Region ASG is in|
|SSH_USER|Username to use to ssh to instance. `ec2-user` is commonly used|

### EC2 Variables

|Variable|Description|
|---|---|
|INSTANCE_ID|EC2 instance ID to collect from|
|REGION|Region ASG is in|
|SSH_USER|Username to use to ssh to instance. `ec2-user` is commonly used|

### SSH Variables

|Variable|Description|
|---|---|
|SSH_ADDRESS|ip or dns name for instance to collect from|
|SSH_USER|Username to use to ssh to instance|
|SSH_KEY_PATH|The private key to use to ssh to the instance|

### Kubernetes Variables

|Variable|Description|
|---|---|
|NAMESPACE|(optional) Namespace to collect from, if not all namespaces are checked|
|SIDECAR_ID|(optional) Sidecar Id to identify pods to collect from|