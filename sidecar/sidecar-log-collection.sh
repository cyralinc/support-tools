#!/usr/bin/env bash

SSH_KEY_FILE="${PWD}/sshtempkey"
SEC=0
menuOptions=(ASG EC2 Kubernetes SSH Quit)
COLLECTED_FILES=()

mainMenu() {
    if ! printf '%s\0' "${menuOptions[@]}" | grep -zqxFe "$COLLECTION_TYPE"; then
        echo "Cyral Log Collection"
        echo "===================="
        i=1
        for item in "${menuOptions[@]}"; do
            echo "$i) $item"
            ((i++))
        done
        while true; do
            read -r -n1 -p "Select log collection method: " opt
            echo ""
            if [[ $opt -ge 1 && $opt -le "${#menuOptions[@]}" ]]; then
            break
            else
                echo "Invalid Option!"
            fi
        done
        eval "${menuOptions[((--opt))]}"
    else
       eval "${COLLECTION_TYPE}"
    fi
}

# Menu Options
ASG() {
    validateAws
    if [ -z "$ASG" ]; then
        read -r -p "ASG Name: " ASG
    fi
    getRegion
    getSSHUser

    showConfig ASG SSH_USER REGION

    instancedetails=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-name "$ASG" --output yaml)
    instances=$(echo "${instancedetails}" | grep -oP "InstanceId: \K.+")
    if [ -z "$instances" ]; then
        echo "ERROR: Unable to find ASG Details! Check ASG name and Region"
        exit 1
    fi
    getTempSSHKey
    for iid in $instances; do
        collectFromEC2 "$iid"
    done
    collectResults
}

EC2(){
    validateAws
    if [ -z "$INSTANCE_ID" ]; then
        read -r -p "EC2 Instance ID: " INSTANCE_ID
    fi
    getRegion
    getSSHUser

    showConfig INSTANCE_ID SSH_USER REGION

    if ! aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" 1>/dev/null; then
        echo "ERROR: Unable to find instance $INSTANCE_ID" 
        exit 1
    fi

    getTempSSHKey
    collectFromEC2 "$INSTANCE_ID"
    collectResults
}

Kubernetes() {
    validateK8s

    if [ -z "$COLLECTION_TYPE" ]; then
        read -r -p "Namespace (blank for all): " NAMESPACE
    fi
    if [ -z "$COLLECTION_TYPE" ]; then
        read -r -p "Sidecar ID (blank for all): " SIDECAR_ID
    fi
    collectFromK8s
    collectResults
}

SSH(){
    if [ -z "$SSH_ADDRESS" ]; then
        read -r -p "System Address: " SSH_ADDRESS
    fi
    getSSHUser
    if [ -z "$SSH_KEY_PATH" ]; then
        defaultKey=$(find ~/.ssh -type f \( -name 'id_*' -and ! -name '*.pub' \) | head -1)
        if [ -n "$defafultKey" ]; then
            read -r -p "SSH Key Path (${defaultKey}): " SSH_KEY_PATH
            if [ -z "$SSH_KEY_PATH" ]; then
                SSH_KEY_PATH="${defaultKey}"
            fi
        else
            read -r -p "SSH Key Path: " SSH_KEY_PATH
        fi
    fi
    SSH_KEY_FILE="$SSH_KEY_PATH"
    collectFromSSH "$SSH_ADDRESS"
    collectResults

}


Quit(){
    echo "Thanks!"
    exit 0
}

# Helper Functions

validateAws(){
    if [ -z "$(command -v aws)" ]; then
        echo "Error: Unable to find aws cli, exiting"
        exit 1
    fi
}

validateK8s(){
        if [ -z "$(command -v kubectl)" ]; then
        echo "Error: Unable to find kubectl, exiting"
        exit 1
    fi
}

showConfig(){
    printf "\nUsing the following configuration\n"
    for v in "$@"; do
        val=$(eval "echo \"\$$v\"")
        if [ -n "$val" ]; then
            echo "$v: $val"
        else
            echo "$v not set!"
            exit 1
        fi
    done
}

getRegion(){
    if [ -z "$REGION" ]; then
        currentregion=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')
        if [ -n "$currentregion" ]; then
            read -r -p "Region (${currentregion}): " REGION
            if [ -z "$REGION" ]; then
                REGION="${currentregion}"
            fi
        else
            read -r -p "Region: " REGION
        fi
    fi
}

getSSHUser(){
    if [ -z "$SSH_USER" ]; then
        read -r -p "SSH Username (ec2-user): " SSH_USER
        if [ -z "$SSH_USER" ]; then
            SSH_USER="ec2-user"
        fi
    fi
}

getTempSSHKey() {
    if [ ! -f "$SSH_KEY_FILE" ]; then
        ssh-keygen -b 2048 -t rsa -f "$SSH_KEY_FILE" -q -N ""
    fi

}

# Collection Functions

collectResults(){
    # get all zips and add them in to the support bundle
    echo "Bundling Logs"
    tar --remove-files -czvf cyral_support.tar.gz "${COLLECTED_FILES[@]}" 1>/dev/null
    echo "Support package cyral_support.tar.gz generated successfully"
}

collectFromK8s(){
    k8sCommand='kubectl get pod -o=custom-columns=":.metadata.namespace,:.metadata.name" --no-headers'
    filter="-l app.kubernetes.io/component=sidecar"
    if [ -n "$NAMESPACE" ]; then
        k8sCommand+=" --namespace=$NAMESPACE"
    else
        k8sCommand+=" --all-namespaces"
    fi
    if [ -n "$SIDECAR_ID" ]; then
        filter+=",app.kubernetes.io/instance=${SIDECAR_ID}"
    fi
    k8sCommand+=" ${filter}"
    pods=$(eval "$k8sCommand")
    if [ -n "$pods" ]; then
        while read -r p; do
            IFS=" " read -r ns pod <<< "$p"
            podLogs=()
            echo "Collecting from pod $pod"
            for c in $(kubectl get pod "$pod" --namespace "$ns" -o=jsonpath="{.spec.containers[*].name}"); do
                kubectl logs --namespace "$ns" "$pod" -c "$c" >> "$c.log"
                podLogs+=("$c.log")
            done
            podFile="./$pod.tar.gz"
            COLLECTED_FILES+=("$podFile")
            tar --remove-files -czvf "$podFile" "${podLogs[@]}" 1>/dev/null
        done <<< "$pods"
    else
        echo "Unable to find any pods!"
        exit 1
    fi
}
collectFromEC2(){
    iid=$1
    echo "Processing ${iid}"
    echo "====================="
    iip=$(aws ec2 describe-instances --region "${REGION}" --instance-ids "${iid}" --query 'Reservations[*].Instances[*].PublicIpAddress' --output text || \
        aws ec2 describe-instances --region "${REGION}" --instance-ids "${iid}" --query 'Reservations[*].Instances[*].PrivateIpAddress' --output text || \
        echo "Unable to obtain IP for instance $iid" && \
        exit 5
    )

    # Inject Temp key - only valid for 1 minute
    # https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ec2-instance-connect/index.html
    echo "Injecting Temp SSH Key"
    SEC=$(date +"%s")
    rst=$(aws ec2-instance-connect send-ssh-public-key --region "${REGION}" --instance-id "${iid}" --instance-os-user "${SSH_USER}" --ssh-public-key "file://${SSH_KEY_FILE}.pub")
    if echo "${rst}" | grep -q "true" ; then
        echo "Successfully injected key (valid for 1 min)"
    else
        echo "Unable to inject key! ${rst}"
        exit 1
    fi
    collectFromSSH "$iip" "$iid"

}

collectFromSSH(){
    iip=$1
    iid=$2
    echo "SSH ${SSH_USER}@${iip}"
    output=$(ssh -q -i "$SSH_KEY_FILE" -o "StrictHostKeyChecking no" "${SSH_USER}@${iip}" << "EOF" 2>&1
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
        if [ -n "$iid" ] && [ $(($(date +"%s") - SEC)) -ge 58 ]; then
            echo "Injecting SSH key again since the last one has timed out."
            rst=$(aws ec2-instance-connect send-ssh-public-key --region "${REGION}" --instance-id "${iid}" --instance-os-user "${SSH_USER}" --ssh-public-key "file://${SSH_KEY_FILE}.pub")
            if echo "${rst}" | grep -q "true" ; then
                echo "Successfully injected key (valid for 1 min)"
            else
                echo "Unable to inject key! ${rst}"
                exit 1
            fi
        fi
        systemId="${iid:-$iip}"
        fileName="${systemId}.tar.gz"
        COLLECTED_FILES+=("$fileName")
        echo "downloading logs from ${systemId} to $fileName"
        scp -i "$SSH_KEY_FILE" -o "StrictHostKeyChecking no" "${SSH_USER}@${iip}:/tmp/cyral/cyrallogs.tar.gz" "$fileName" 1>/dev/null
    else
        echo "Proccessing failed!"
    fi
    echo "====================="
}

mainMenu
