#!/bin/bash
set -eou pipefail
[[ -n ${DEBUG:-} ]] && set -x

#Global vars
WORK_DIR=$(cd $(dirname $0) && pwd)
HARBOR_DIR="$WORK_DIR/harbor"
HARBOR_CONFIGURATION_FILE="harbor.yml"
HARBOR_REGISTRY_URL="registry.longtruong-lab.online"
USER_EMAIL="longth2162000@gmail.com"

function command_exist {
    command -v "$@" > /dev/null 2>&1
}

bash_c="bash -c"
user=$(whoami)
function do_install {
    if [[ $user != root ]]; then
        if command_exist sudo; then
            bash_c="sudo -E bash -c"
        elif command_exist su; then
            bash_c="su $user -c"
        else
            cat <<-EOF
            [Error]: This job requires root privilege.
            However, neither "sudo" or "su" available to perform this job.
EOF
        exit 1
        fi
    fi

    # Install certbot
    if ! command_exist certbot; then
    	$bash_c "apt-get update -qq > /dev/null 2>&1"
    	$bash_c "apt-get install -y -qq certbot > /dev/null 2>&1"
    	if [[ $? -eq 0 ]]; then
        	echo "Installing certbot...: OK"
    	else
        	echo "Installing certbot...: FAILED"
    	fi
    fi

    # Install harbor
    cd $WORK_DIR
    $bash_c "curl -fsSL https://api.github.com/repos/goharbor/harbor/releases/latest | grep browser_download_url | cut -d '\"' -f 4 | grep '.tgz$' | wget -i - > /dev/null 2>&1"
    $bash_c "tar xvzf harbor-offline-installer*.tgz > /dev/null 2>&1"
    if [[ $? -eq 0 ]]; then
        echo "Installing harbor...: OK"
    else
        echo "Installing harbor...: FAILED"
    fi

    # Install Docker
    if ! command_exist docker; then
    	$bash_c "apt-get install -y -qq apt-transport-https ca-certificates curl gnupg lsb-release > /dev/null 2>&1"
    	$bash_c "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"
    	$bash_c "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null 2>&1"
    	$bash_c "apt-get update -qq > /dev/null 2>&1"
    	$bash_c "apt-get install -y -qq docker-ce docker-ce-cli containerd.io > /dev/null 2>&1"
    	if [[ $? -eq 0 ]]; then
        	echo "Installing Docker...: OK"
    	else
        	echo "Installing Docker...: FAILED"
    	fi
    fi	
    
    #Install Docker-compose
    if ! command_exist docker-compose; then
    	$bash_c "apt-get install -y -qq docker-compose > /dev/null 2>&1"
    	if [[ $? -eq 0 ]]; then
        	echo "Installing docker-compose...: OK"
    	else
        	echo "Installing docker-compose...: FAILED"
    	fi
    fi
}

function configure_and_run_harbor {
    # Get certificates by certbot
    AUTHENTICATION_FILE="certificate.log"
    if [[ ! -f $WORK_DIR/$AUTHENTICATION_FILE ]]; then
    	$bash_c "certbot certonly --standalone -d $HARBOR_REGISTRY_URL --preferred-challenges http --agree-tos -m $USER_EMAIL --keep-until-expiring > $AUTHENTICATION_FILE 2>&1"
    fi
    
    fullchain=$(cat $AUTHENTICATION_FILE | grep -i "fullchain.pem" | tr -d [:blank:] | cut -d ':' -f2)
    encrypted_fullchain=$(echo $fullchain | sed 's/\//\\\//g')
    privkey=$(cat $AUTHENTICATION_FILE | grep -i "privkey.pem" | tr -d [:blank:] | cut -d ':' -f2)
    encrypted_privkey=$(echo $privkey | sed 's/\//\\\//g')

    cd $HARBOR_DIR
    cp harbor.yml.tmpl $HARBOR_CONFIGURATION_FILE

    # Substitute value of yaml file
    $bash_c "sed -ri \"s/^(\s*)(hostname\s*:\s*(.+)\s*$)/\1hostname: $HARBOR_REGISTRY_URL/\" $HARBOR_CONFIGURATION_FILE"
    $bash_c "sed -ri \"s/^(\s*)(certificate\s*:\s*(.+)\s*$)/\1certificate: $encrypted_fullchain/\" $HARBOR_CONFIGURATION_FILE"
    $bash_c "sed -ri \"s/^(\s*)(private_key\s*:\s*(.+)\s*$)/\1private_key: $encrypted_privkey/\" $HARBOR_CONFIGURATION_FILE"

    $bash_c "bash prepare"
    wait
    $bash_c "bash install.sh"
    wait
}

do_install
configure_and_run_harbor
