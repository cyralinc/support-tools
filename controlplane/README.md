# Control Plane Support Tools

## ECS / Cloudwatch Log Collection

If you are running an on-prem control plane on ECS with logs going to CloudWatch a [3rd party tool](https://github.com/jorgebastida/awslogs) can be used for extracting the logs.

You can run this from AWS CloudShell or from any system with Python 3.

### Install

```shell
python3 -m pip install awslogs
```

### Usage

The simplest way to college logs would be in the following form, updating the <stack_name> for the name of your cloudformation stack (log group name is the same) and setting the start and end time. If you dont provide a Start/End it will only pull the last 5 minutes.

```shell
awslogs get <stack_name> --timestamp --no-group --start "11/16/2022 10:00" --end "11/16/2022 11:00" | gzip -c - > cyral_logs.gz
```

Additional information on AWS credentials options and time formats can be found on the [awscli readme](https://github.com/jorgebastida/awslogs)
