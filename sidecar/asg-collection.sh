#! /usr/bin/env sh

#############################################################
# By: Justin Rich Date: 6/29/2022                           #
# This script is designed to gather logs from Sidecars      #
# that are running as part of an ASG on AWS                 #
# Required Utilities                                        #
# AWS Cli, ssh, rsync, tar                                  #
#                                                           #
# Inputs                                                    #
# ASG = name of the ASG for the sidecar                     #
# SSHUSER = user with ssh access, ubuntu, ec2-user          #
# REGION = region of the ASG or the default region          #
#############################################################


if [ -z "$ASG" ]; then
    read -r -p "ASG Name: " ASG
fi

if [ -z "$SSHUSER" ]; then
    read -r -p "SSH Username (ec2-user): " SSHUSER
    if [ -z "$SSHUSER" ]; then
        SSHUSER="ec2-user"
    fi
fi


if [ -z $REGION ]; then
    currentregion=$(aws configure get region)
    if [ -n "$currentregion" ]; then
        read -r -p "Region (${currentregion}): " REGION
        if [ -z "$REGION" ]; then
            REGION="${currentregion}"
        fi
    else
        read -r -p "Region: " REGION
    fi
fi

printf "\nUsing the following configuration"
for v in ASG SSHUSER REGION; do
    val=$(eval "echo \"\$$v\"")
    if [ -n "$val" ]; then
        echo "$v: $val"
    else
        echo "$v not set!"
        exit 1
    fi
done
printf "\n"

# generate temp SSH key pair ./sshtempkey and ./sshtempkey.pub
if [ ! -f "${PWD}/sshtempkey" ]; then
    ssh-keygen -b 2048 -t rsa -f "${PWD}/sshtempkey" -q -N ""
fi

# collect ASG EC2 instances
instancedetails=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-name "$ASG" --output yaml)
instances=$(echo "${instancedetails}" | grep -oP "InstanceId: \K.+")
if [ -z "$instances" ]; then
    echo "Unable to find ASG Details! Check ASG name and Region"
    exit 1
fi

for iid in $instances; do

    echo "Processing ${iid}"
    echo "====================="
    iip=$(aws ec2 describe-instances --region "${REGION}" --instance-ids "${iid}" --query 'Reservations[*].Instances[*].PublicIpAddress' --output text)

    # Inject Temp key - only valid for 1 minute
    # https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ec2-instance-connect/index.html
    echo "Injecting Temp SSH Key"
    sec=$(date +"%s")
    rst=$(aws ec2-instance-connect send-ssh-public-key --region "${REGION}" --instance-id "${iid}" --instance-os-user "${SSHUSER}" --ssh-public-key "file://${PWD}/sshtempkey.pub")
    if echo "${rst}" | grep -q "true" ; then
        echo "Successfully injected key (valid for 1 min)"
    else
        echo "Unable to inject key! ${rst}"
        exit 1
    fi

    echo "SSH ${SSHUSER}@${iip}"
    output=$(ssh -q -i sshtempkey -o "StrictHostKeyChecking no" "${SSHUSER}@${iip}" << "EOF" 2>&1
mkdir -p /tmp/cyral
cd /tmp/cyral
rm -f cyrallogs.tar.gz 2>/dev/null
cids=$(sudo docker ps -q)
for cid in $cids; do
    cname=$(sudo docker inspect $cid -f "{{.Name}}")
    echo "Processing ${cname}"
    sudo docker inspect $cid > "${PWD}${cname}-inspect.txt"
    sudo docker logs $cid > "${PWD}${cname}-out.log" 2> "${PWD}${cname}-err.log"
done
tar --remove-files -czvf cyrallogs.tar.gz ./*
echo "Processed Successfully!"
EOF
)
    if [ $? -eq 255 ]; then
        echo "Error SSH connection error! Is the username correct?"
        exit 1
    fi
    echo "$output"
    if echo "${output}" | grep -q 'fully!$' ; then
        echo "====================="
        if [ $(($(date +"%s") - sec)) -ge 58 ]; then
            echo "Injecting SSH key again since the last one has timed out."
            rst=$(aws ec2-instance-connect send-ssh-public-key --region "${REGION}" --instance-id "${iid}" --instance-os-user "${SSHUSER}" --ssh-public-key "file://${PWD}/sshtempkey.pub")
            if echo "${rst}" | grep -q "true" ; then
                echo "Successfully injected key (valid for 1 min)"
            else
                echo "Unable to inject key! ${rst}"
                exit 1
            fi
        fi
        echo "downloading logs from ${iid}"
        scp -i sshtempkey -o "StrictHostKeyChecking no" "${SSHUSER}@${iip}:/tmp/cyral/cyrallogs.tar.gz" "./${iid}.tar.gz" 1>/dev/null
    else
        echo "Proccessing failed!"
    fi
    echo "====================="
done

tar --remove-files -czvf cyral_support.tar.gz ./i-*.tar.gz 1>/dev/null
echo "Support package cyral_support.tar.gz generated successfully"