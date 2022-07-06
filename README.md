# Support-Tools
Scripts and tools to help support setups


# Sidecar Tools

## Sidecar ASG Log Collection

The simple form would be to run the following command

```
ASG=the-asg-name SSHUSER=ec2-user REGION=us-west-2 ./asg-collecction.sh
```

REGION is options and will use your default region if not provided.

The SSHUSER will depend on the AMI used but will typically be `ec2-user` or `ubuntu`