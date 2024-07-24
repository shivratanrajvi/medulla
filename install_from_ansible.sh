#!/bin/bash

# This script is called
# - either by the main installer to install Medulla in a docker container or in a VirtualBox VM (--nostandalone must be specified)
# - or as a standalone script to install Medulla on an existing server 
#
# The server must match the following pre-requisites:
# •	A machine running an up-to-date Debian 12 OS;
# •	The machine must have at least 8GB of RAM;
# •	The machine must have access to the Internet;
# •	The machine name must be defined and resolvable on the machine itself either via the hosts file or from the DNS.

. /etc/os-release
# Variables initialisation
TIMEZONE='Europe/Paris'

# Internal functions
colored_echo() {
    # Output colored lines to shell
    local COLOR=$1;
    if ! [[ $COLOR =~ '^[0-9]$' ]] ; then
        case $(echo $COLOR | tr '[:upper:]' '[:lower:]') in
            black) COLOR=0 ;;
            red) COLOR=1 ;;
            green) COLOR=2 ;;
            yellow) COLOR=3 ;;
            blue) COLOR=4 ;;
            magenta) COLOR=5 ;;
            cyan) COLOR=6 ;;
            white|*) COLOR=7 ;; # white or invalid color
        esac
    fi
    tput setaf $COLOR;
    echo "${@:2}";
    tput sgr0;
}

ask() {
    # Ask user a yes/no question
    local TEXT=$1
    local OPTION1=$2
    local OPTION2=$3
    local RESULT=N
    while [ ${RESULT} == "N" ]; do
        local PROMPT="$OPTION1/$OPTION2"
        # Ask the question - use /dev/tty in case stdin is redirected from somewhere else
        read -p "${TEXT} [${PROMPT}] " REPLY </dev/tty
        # Check if the reply is valid
        case "${REPLY}" in
            ${OPTION1^^}|${OPTION1,,})
                RESULT=Y
                echo ${OPTION1,,}
                ;;
            ${OPTION2^^}|${OPTION2,,})
                RESULT=Y
                echo ${OPTION2,,}
                ;;
        esac
    done
}

check_linux_distribution() {
    if [[ $ID == "centos" ]]; then
        LINUX_DISTRO="rhel"
    else
        LINUX_DISTRO=$ID
    fi

    DISTRO_VERSION=$VERSION_ID

    case ${LINUX_DISTRO} in
        "debian"|"mageia"|"rhel")
            ;;

        *)
            echo "We only support Debian, Mageia, and rhel"
            exit 1
            ;;
    esac
}

get_user_input() {
    #
    # Ask user for a string input
    #
    local TEXT=$1
    while [[ ${RESULT} == '' ]]; do
        read -p "${TEXT} " RESULT
    done
    echo ${RESULT}
}

vault_string() {
    local CLEAR_STRING=$1
    ansible-vault encrypt_string --vault-password-file ~/.vp "$CLEAR_STRING"
}

display_error_message() {
    local TEXT=$1
    local CMD=$2
    colored_echo red "### ${TEXT}. Exiting"
    if [[ ${CMD} != "" ]]; then
        colored_echo red "Failed command: ${CMD}"
    fi
    colored_echo red "If more control on the installation is needed, download the installer and run the installation in interactive mode."
    colored_echo red "Please refer to the \"Other options\" section in the provided documentation."
}

display_usage() {
    #
    # Display usage message
    #
    echo -e "\nUsage:\n$0 [--nostandalone]\n"
    echo -e "arguments:"
    echo -e "\t[--interactive]"
    echo -e "or:"
    echo -e "\t[--timezone=<Server's timezone> eg. Europe/Paris]"
    echo -e "\t[--medulla-root-pw=<Medulla root password>]"
    echo -e "\t[--public-ip=<Public IP if available>]"
    echo -e "\t[--interface=<Interface used to connect to the clients>]"
    echo -e "\t[--server-fqdn=<FQDN of server>]"
    exit 0
}

check_arguments() {
    #
    # Make sure the options passed are valid
    #
    ARGS="$@"
    for i in "$@"; do
        case $i in
            --nostandalone*)
                NOSTANDALONE=1
                shift
                ;;
            --interactive*)
                INTERACTIVE=1
                shift
                ;;
            --timezone*)
                TIMEZONE="${i#*=}"
                shift
                ;;
            --playbook-url*)
                PLAYBOOK_URL="${i#*=}"
                shift
                ;;
            --medulla-root-pw*)
                ROOT_PASSWORD="${i#*=}"
                shift
                ;;
            --public-ip*)
                PUBLIC_IP="${i#*=}"
                shift
                ;;
            --interface*)
                INTERFACE="${i#*=}"
                shift
                ;;
            --server-fqdn*)
                SERVER_FQDN="${i#*=}"
                shift
                ;;
            *)
                # unknown option
                display_usage
                ;;
        esac
    done
}

display_wizard() {
    #
    # Ask questions to user for customising the installation
    #
    local ENTER_TIMEZONE=$(ask "The default time zone is ${TIMEZONE}. Do you want to change it?" y n)
    if [[ ${ENTER_TIMEZONE} == "y" ]]; then
        TIMEZONE=$(get_user_input "Define the new time zone:")
    fi
    ROOT_PASSWORD=$(get_user_input "Enter the password you wish to use for Medulla admin account:")
    local ENTER_IP=$(ask "Does this server has a public IP?" y n)
    if [[ ${ENTER_IP} == "y" ]]; then
        PUBLIC_IP=$(get_user_input "Enter the server's public IP:")
    fi
    local ENTER_INTERFACE=$(ask "The detected interface is ${INTERFACE}. Do you want to change it?" y n)
    if [[ ${ENTER_INTERFACE} == "y" ]]; then
        INTERFACE=$(get_user_input "Enter the new interface:")
    fi
    local ENTER_FQDN=$(ask "The detected FQDN is ${SERVER_FQDN}. Do you wish to change it?" y n)
    if [[ ${ENTER_FQDN} == "y" ]]; then
        SERVER_FQDN=$(get_user_input "Enter the server's FQDN:")
    fi
}

display_summary() {
    #
    # Display parameters that will be used for installing Medulla
    #
    colored_echo blue "Medulla will be installed with the following parameters:"
    colored_echo blue "- SERVER_FQDN: ${SERVER_FQDN}"
    colored_echo blue "- TIMEZONE: ${TIMEZONE}"
    colored_echo blue "- ROOT_PASSWORD: ${ROOT_PASSWORD}"
    colored_echo blue "- PLAYBOOK_URL: ${PLAYBOOK_URL}"
    colored_echo blue "- PUBLIC_IP: ${PUBLIC_IP}"
    colored_echo blue "- INTERFACE: ${INTERFACE}"
    sleep 10
}


# ======================================================================
check_internet_connection() {
    #
    # Make sure the machine is connected to the Internet
    #
    colored_echo blue "Checking internet connection..."
    wget -q --spider http://google.com &> /dev/null
    if [ $? -ne 0 ]; then
        display_error_message "The machine is not connected to the Internet"
        exit 1
    fi
    colored_echo green "Checking internet connection... DONE"
}

update_debian() {
    #
    # Update debian packages
    #
    colored_echo blue "Updating Debian..."
    local CMD="apt update"
    eval ${CMD}
    if [ $? -ne 0 ]; then
        display_error_message "The machine's OS could not be updated" "${CMD}"
        exit 1
    fi
    local CMD="DEBIAN_FRONTEND=noninteractive apt -yq upgrade"
    eval ${CMD}
    if [ $? -ne 0 ]; then
        display_error_message "The machine's OS could not be updated" "${CMD}"
        exit 1
    fi
    colored_echo green "Updating Debian... DONE"
}

update_rhel() {
    #
    # Update rhel packages
    #
    colored_echo blue "Updating RHEL..."
    local CMD="dnf update -y"
    eval ${CMD}
    if [ $? -ne 0 ]; then
        display_error_message "The machine's OS could not be updated" "${CMD}"
        exit 1
    fi
    colored_echo green "Updating Debian... DONE"
}

update_mageia() {
    #
    # Update mageia packages
    #
    colored_echo blue "Updating Mageia..."
    local CMD="urpmi --auto-update --auto"
    eval ${CMD}
    if [ $? -ne 0 ]; then
        display_error_message "The machine's OS could not be updated" "${CMD}"
        exit 1
    fi
    colored_echo green "Updating Debian... DONE"
}

install_script_dependencies() {
    # 
    # Install dependencies needed (apg) to run this script
    #
    colored_echo blue "Installing dependencies required to run this script..."
    if [[ $LINUX_DISTRO == "debian" ]];then
        local CMD="apt -yq install apg jq curl &> /dev/null"
    elif [[ $LINUX_DISTRO == "rhel" ]];then
        local CMD="dnf -y install apg jq curl &> /dev/null"
    elif [[ $LINUX_DISTRO == "mageia" ]];then
        local CMD="urpmi --auto install apg jq curl &> /dev/null"
    fi
    eval ${CMD}
    if [ $? -ne 0 ]; then
        display_error_message "The dependencies could not be installed" "${CMD}"
        exit 1
    fi
    colored_echo green "Installing dependencies required to run this script... DONE"
}

define_minimum_vars() {
    #
    # Define minimum variables used by the script
    #
    colored_echo blue "Creating root password..."
    ROOT_PASSWORD=$(apg -a 1 -M NCL -n 1 -x 12 -m 12)
    colored_echo green "Creating root password... DONE"
    colored_echo blue "Finding out values for INTERFACE and PUBLIC_IP..."
    local IP_ADDRESSES=$(hostname -I)
    local STATIC_INTERFACES=()
    for IP in ${IP_ADDRESSES}; do
        if [[ $IP =~ ^10\.|^172\.(1[6-9]|2[0-9]|3[01])\.|^192\.168\.|^169\.254\.|^127\. ]]; then
            STATIC_INTERFACES+=($(ip -o addr | grep ${IP} | grep -v -w dynamic | awk '{print $2}'))
        else
            PUBLIC_IP=${IP}
        fi
    done
    if [ ${#STATIC_INTERFACES[@]} -eq 1 ]; then
        INTERFACE=${STATIC_INTERFACES}
    elif [ ${#STATIC_INTERFACES[@]} -gt 1 ]; then
        display_error_message "The server has more than one interface with a static IP address: ${STATIC_INTERFACES[@]}. The installer cannot figure out which one to use"
        exit 1
    else
        display_error_message "No interface with a static IP address was found. Medulla needs a static interface for connecting to its clients"
        exit 1
    fi
    colored_echo green "Finding out values for INTERFACE and PUBLIC_IP... DONE"
    colored_echo blue "Finding out server's FQDN..."
    SERVER_FQDN=$(hostname -f)
    colored_echo green "Finding out server's FQDN... DONE"
    colored_echo blue "Defining working directory..."
    WORKDIR=$(mktemp -d -p /tmp/)
    colored_echo green "Defining working directory... DONE"
    colored_echo blue "Finding out latest PLAYBOOK_URL value..."
    PLAYBOOK_URL=$(curl -s https://api.github.com/repos/medulla-tech/integration/releases/latest | jq '.tarball_url')
    colored_echo green "Finding out latest PLAYBOOK_URL value... DONE"
}

check_machine_resolution() {
    #
    # Make sure the machine name is resolvable on the machine itself
    #
    colored_echo blue "Checking if the machine is resolvable..."
    if [[ -z "$(hostname -d)" ]]; then
        display_error_message "The machine's domain name is not defined. Consider setting it using hostnamectl hostname <fqdn_of_server> and adding it to /etc/hosts file"
        exit 1
    fi
    LOCAL_FQDN=$(hostname -f)
    if [[ -z "$(grep ${LOCAL_FQDN} /etc/hosts)" ]]; then
        display_error_message "The machine's name ${LOCAL_FQDN} is not in /etc/hosts. Consider defining it using echo ${LOCAL_FQDN} >> /etc/hosts"
        exit 1
    fi
    ping -c 1 ${SERVER_FQDN} &> /dev/null
    if [ $? -ne 0 ]; then
        display_error_message "The name ${SERVER_FQDN} is not resolvable. Make sure your DNS is configured properly (/etc/resolv.conf) and the local hosts file (/etc/hosts) is correct"
        exit 1
    fi  

    colored_echo green "Checking if the machine is resolvable... DONE"
}

check_dhcp_status() {
    #
    # Make sure the machine's interface used is not configured by DHCP
    #
    colored_echo blue "Checking if the interface is not configured by DHCP..."
    DHCP=$(ip -o addr | grep ${INTERFACE} | grep -w dynamic | wc -l)
    if [[ ${DHCP} -ne 0 ]]; then
        display_error_message "The interface ${INTERFACE} is configured by DHCP. Medulla needs a static interface for connecting to its clients"
        exit 1
    fi
    colored_echo green "Checking if the interface is not configured by DHCP... DONE"
}

define_timezone() {
    # 
    # Define default timezone
    # 
    colored_echo blue "Defining default timezone..."
    local CMD="timedatectl set-timezone ${TIMEZONE}"
    eval ${CMD}
    if [ $? -ne 0 ]; then
        display_error_message "The timezone could not be defined" "${CMD}"
        exit 1
    fi
    colored_echo green "Defining default timezone... DONE"
}

install_ansible() {
    #
    # Install Ansible
    #
    colored_echo blue "Installing Ansible and dependencies..."
    if [[ $LINUX_DISTRO == "debian" ]];then
        local CMD="apt -yq install ansible &> /dev/null"
    elif [[ $LINUX_DISTRO == "rhel" ]];then
        local CMD="dnf -y install ansible &> /dev/null"
    elif [[ $LINUX_DISTRO == "mageia" ]];then
        local CMD="urpmi --auto install ansible &> /dev/null"
    fi

    eval ${CMD}
    if [ $? -ne 0 ]; then
        display_error_message "Ansible could not be installed" "${CMD}"
        exit 1
    fi
    local CMD="ansible-galaxy collection install community.general"
    eval ${CMD}
    if [ $? -ne 0 ]; then
        display_error_message "Ansible community.general collection could not be installed" "${CMD}"
        exit 1
    fi

    if [[ $LINUX_DISTRO == "debian" ]];then
        local CMD="apt -yq install python3-passlib python3-bcrypt python3-pymysql xmlstarlet python3-lxml python3-selinux python3-pyldap python3-openssl &> /dev/null"
    elif [[ $LINUX_DISTRO == "rhel" ]];then
        local CMD="dnf -y install python3-passlib python3-bcrypt python3-pymysql xmlstarlet python3-lxml python3-selinux python3-pyldap python3-openssl &> /dev/null"
    elif [[ $LINUX_DISTRO == "mageia" ]];then
        local CMD="urpmi --auto install python3-passlib python3-bcrypt python3-pymysql xmlstarlet python3-lxml python3-selinux python3-pyldap python3-openssl &> /dev/null"
    fi

    eval ${CMD}
    if [ $? -ne 0 ]; then
        display_error_message "Ansible could not be installed" "${CMD}"
        exit 1
    fi
    colored_echo green "Installing Ansible and dependencies... DONE"
}

download_playbook() {
    #
    # Download ansible playbook
    #
    colored_echo blue "Downloading playbook..."
    local CMD="wget -c ${PLAYBOOK_URL} -O - | tar xz -C ${WORKDIR} --strip-components=1"
    eval ${CMD}
    if [ $? -ne 0 ]; then
        display_error_message "Playbook could not be downloaded" "${CMD}"
        exit 1
    fi
    colored_echo green "Downloading playbook... DONE"
}

create_vaultpass() {
    #
    # Create vault password file
    #
    colored_echo blue "Creating vault password file..."
    local CMD="apg -a 1 -M NCL -n 1 -x 12 -m 12 > ~/.vp"
    eval ${CMD}
    if [ $? -ne 0 ]; then
        display_error_message "Vault password file could not be generated" "${CMD}"
        exit 1
    fi
    colored_echo green "Creating vault password file... DONE"
}

generate_sshkeys() {
    #
    # Generate SSH keys and setup local authentication
    #
    colored_echo blue "Generating SSH keys..."
    ssh-keygen -f ~/.ssh/id_rsa -N '' -b 2048 -t rsa -q <<< n &>/dev/null
    cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys 
    ssh-keyscan -t rsa $(hostname) >> ~/.ssh/known_hosts
    colored_echo green "Generating SSH keys... DONE"
}

generate_ansible_hosts() {
    #
    # Create annsible_hosts file
    #
    colored_echo blue "Generating Ansible hosts file..."

    AES_KEY=$(apg -a 1 -M NCL -n 1 -x 32 -m 32)
    DRIVERS_PASSWORD=$(apg -a 1 -M NCL -n 1 -x 12 -m 12)
    GLPI_DBPASSWD=$(apg -a 1 -M NCL -n 1 -x 12 -m 12)
    ITSMNG_DBPASSWD=${GLPI_DBPASSWD}
    MASTER_TOKEN=$(apg -a 1 -M NCL -n 1 -x 32 -m 32)
    XMPP_MASTER_PASSWORD=$(apg -a 1 -M NCL -n 1 -x 12 -m 12)
    DBPASSWORD=$(apg -a 1 -M NCL -n 1 -x 12 -m 12)
    ITSM_DBPASSWD=${GLPI_DBPASSWD}
    GUACDBPASSWD=$(apg -a 1 -M NCL -n 1 -x 12 -m 12)
    GUACAMOLE_ROOT_PASSWORD=$(apg -a 1 -M NCL -n 1 -x 40 -m 40)
    ROOT_PASSWORD_VAULTED=$(vault_string ${ROOT_PASSWORD})
    AES_KEY_VAULTED=$(vault_string ${AES_KEY})
    DRIVERS_PASSWORD_VAULTED=$(vault_string ${DRIVERS_PASSWORD})
    GLPI_DBPASSWD_VAULTED=$(vault_string ${GLPI_DBPASSWD})
    ITSMNG_DBPASSWD_VAULTED=$(vault_string ${ITSMNG_DBPASSWD})
    MASTER_TOKEN_VAULTED=$(vault_string ${MASTER_TOKEN})
    XMPP_MASTER_PASSWORD_VAULTED=$(vault_string ${XMPP_MASTER_PASSWORD})
    DBPASSWORD_VAULTED=$(vault_string ${DBPASSWORD})
    ITSM_DBPASSWD_VAULTED=$(vault_string ${ITSM_DBPASSWD})
    GUACDBPASSWD_VAULTED=$(vault_string ${GUACDBPASSWD})
    GUACAMOLE_ROOT_PASSWORD_VAULTED=$(vault_string ${GUACAMOLE_ROOT_PASSWORD})
cat > ${WORKDIR}/ansible/ansible_hosts << EOF
medulla:
  hosts:
    ${LOCAL_FQDN}:
      PUBLIC_IP: ${PUBLIC_IP}
      SERVER_FQDN: ${SERVER_FQDN}
      INTERFACE: ${INTERFACE}
  vars:
    ROOT_PASSWORD: ${ROOT_PASSWORD_VAULTED}

mmc:
  hosts:
    ${LOCAL_FQDN}:
  vars:
    AES_KEY: ${AES_KEY_VAULTED}
    DRIVERS_PASSWORD: ${DRIVERS_PASSWORD_VAULTED}
    GLPI_DBPASSWD: ${GLPI_DBPASSWD_VAULTED}
    ITSMNG_DBPASSWD: ${ITSMNG_DBPASSWD_VAULTED}
    MASTER_TOKEN: ${MASTER_TOKEN_VAULTED}
    XMPP_DOMAIN: pulse
    ENTITY: Public

all:
  vars:
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
    ansible_python_interpreter: /usr/bin/python3
    ansible_user: root
    PULSE4REPO_URL: https://apt.siveo.net/stable.sources
    XMPP_MASTER_PASSWORD: ${XMPP_MASTER_PASSWORD_VAULTED}
    DBPASSWORD: ${DBPASSWORD_VAULTED}
    ITSM_DBPASSWD: ${ITSM_DBPASSWD_VAULTED}
    GUACDBPASSWD: ${GUACDBPASSWD_VAULTED}
    GUACAMOLE_ROOT_PASSWORD: ${GUACAMOLE_ROOT_PASSWORD_VAULTED}

EOF
    if [ $? -ne 0 ]; then
        display_error_message "ansible_hosts file could not be generated"
        exit 1
    fi
    if [[ ${PUBLIC_IP} == '' ]]; then
        sed -i '/PUBLIC_IP/d' ${WORKDIR}/ansible/ansible_hosts
        if [ $? -ne 0 ]; then
            display_error_message "ansible_hosts file could not be generated"
            exit 1
        fi
    fi
    colored_echo green "Generating Ansible hosts file... DONE"
}

display_final_message() {
    #
    # Display success message explaining how to access Medulla
    #
    colored_echo green "### Medulla installed successfully"
    colored_echo green "# "
    colored_echo green "# To access Medulla, point your browser to http://${SERVER_FQDN}"
    colored_echo green "# and log on using root / ${ROOT_PASSWORD}"
    colored_echo green "# "
    if [[ ${PUBLIC_IP} == '' ]]; then
        colored_echo green "# Please note that clients outside the LAN will not be able to connect"
        colored_echo green "# as no public IP address is defined"
    fi
    colored_echo green "# "
    colored_echo green "# The client agent can be downloaded from"
    colored_echo green "# http://${SERVER_FQDN}/downloads/win/Medulla-Agent-windows-FULL-latest.exe"
    colored_echo green "# "
    colored_echo green "# Step 1:"
    colored_echo green "# Download the agent from the URL above and install it on your Windows clients"
    colored_echo green "# "
    colored_echo green "# Step 2:"
    colored_echo green "# Once the install is complete, the Windows machines need to be restarted"
    colored_echo green "# "
    colored_echo green "# Step 3:"
    colored_echo green "# Once restarted the Windows machines will connect to Medulla to complete their"
    colored_echo green "# setup then go online on Medulla console in the Computers page. This phase can"
    colored_echo green "# take up to 20 minutes depending on the bandwidth between the client machine"
    colored_echo green "# and Medulla server."
    colored_echo green "# Once a machine is online and inventoried, it can be managed by Medulla."
    colored_echo green "# "
    colored_echo green "###"
}

install_medulla() {
    # 
    # Run ansible command for installing Medulla
    #
    pushd ${WORKDIR}/ansible
    local CMD="ansible-playbook playbook_cleanup.yml --vault-password-file ~/.vp -i ansible_hosts --limit=medulla"
    local CMD="ansible-playbook playbook_pulsemain.yml --vault-password-file ~/.vp -i ansible_hosts --limit=medulla"
    eval ${CMD}
    if [ $? -ne 0 ]; then
        display_error_message "Error installing Medulla" "${CMD}"
        exit 1
    else
        display_final_message
    fi
    popd
}

cleanup_previous_setup() {
    # 
    # Cleanup previous install if ~/.vp is found
    # 
    if [ -f ~/.vp ]; then
        pushd ${WORKDIR}/ansible
        ansible-playbook playbook_cleanup.yml --vault-password-file ~/.vp -i ansible_hosts --limit=medulla
    fi
}

# ======================================================================
# ======================================================================
# And finally we run the functions
check_linux_distribution
check_internet_connection
if [[ $LINUX_DISTRO == "debian" ]];then
    update_debian
elif [[ $LINUX_DISTRO == "rhel" ]]; then
    update_rhel
elif [[ $LINUX_DISTRO == "mageia" ]]; then
    update_mageia
fi
install_script_dependencies
define_minimum_vars
check_arguments "$@"
if [[ ${INTERACTIVE} == 1 ]]; then
    display_wizard
fi
display_summary
check_machine_resolution
check_dhcp_status
define_timezone
install_ansible
if [[ ${NOSTANDALONE} == 1 ]]; then
    WORKDIR=.
else
    download_playbook
fi
cleanup_previous_setup
create_vaultpass
generate_sshkeys
generate_ansible_hosts
install_medulla
