#!/bin/bash

# Define colors for the script
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Define the directory where the script and variables.txt are located
SCRIPT_DIR=$(dirname "$0")

# Check if variables.txt exists and is not empty
if [[ -s "$SCRIPT_DIR/variables.txt" ]]; then
    printf "\n${GREEN}Found existing 'variables.txt'. Skipping setup questions and proceeding with Tailscale setup.${NC}\n"
    source "$SCRIPT_DIR/variables.txt"
    if [ -f "$SCRIPT_DIR/setup_tailscale.sh" ]; then
        chmod +x "$SCRIPT_DIR/setup_tailscale.sh"
        "$SCRIPT_DIR/setup_tailscale.sh"
    else
        printf "\n${RED}'setup_tailscale.sh' not found in the script directory.${NC}\n"
    fi
    exit 0
fi

# Prompt the user to confirm they want to run this script to install Tailscale, Caddy, and set up Cloudflare DNS Hostnames
printf "\n${YELLOW}Running this script on your Google Cloud VM will assist you in configuring Tailscale and Caddy.\n"
printf "It will also set up Cloudflare DNS Hostnames to serve sites only accessible within your tailnet.${NC}\n\n"
printf "Do you want to continue? (y/n): "
read -p "> " INSTALL_CHOICE

# Function to prompt the user for input and confirm responses before writing to variables.txt
function prompt_for_input {
    local prompt_message="$1"
    local variable_name="$2"
    local is_vpc_name="${3:-false}"

    while true; do
        printf "\n$prompt_message\n"
        read -p "> " value
        if [[ -z "$value" && "$is_vpc_name" == "true" ]]; then
            printf "${YELLOW}Left blank, using 'default'.${NC}\n"
            value="default"
        else
            printf "\n${GREEN}You entered: $value${NC}\n"
        fi
        
        printf "${YELLOW}Is this correct? (y/n): ${NC}"
        read -p "> " confirmation
        if [[ $confirmation =~ ^[Yy](es)?$ ]]; then
            echo "$variable_name=$value" >> "$SCRIPT_DIR/variables.txt"
            break
        else
            printf "\n${RED}Let's try that again.${NC}\n"
        fi
    done
}

# If the user chooses to install Tailscale, proceed with the setup
if [[ $INSTALL_CHOICE =~ ^[Yy](es)?$ ]]; then
    # Clear the file to start fresh or create it if it doesn't exist
    > "$SCRIPT_DIR/variables.txt"

    # Automatically Fetch VM information and write Project ID, Name, Zone and IP Address to variables.txt
    echo "Fetching VM information, please wait..."
    PROJECT_ID=$(gcloud config list --format 'value(core.project)')
    VM_INFO=$(gcloud compute instances list --format='csv[no-heading](name,zone,networkInterfaces[0].accessConfigs[0].natIP)' --filter="status=RUNNING")
    VM_LINES=$(echo "$VM_INFO" | wc -l)

    # If multiple VMs are detected, prompt the user to select one
    if [ "$VM_LINES" -gt 1 ]; then
        echo "Multiple VMs detected. Select one:"
        select OPTION in $VM_INFO; do
            IFS=',' read -ra ADDR <<< "$OPTION"
            VM_NAME=${ADDR[0]}
            ZONE=${ADDR[1]}
            OLD_IP_ADDRESS=${ADDR[2]}
            break
        done
    else
        IFS=',' read -ra ADDR <<< "$VM_INFO"
        VM_NAME=${ADDR[0]}
        ZONE=${ADDR[1]}
        OLD_IP_ADDRESS=${ADDR[2]}
        echo "Found 1 VM: Name=$VM_NAME, Zone=$ZONE, IP Address=$OLD_IP_ADDRESS"
    fi

    # Write the VM_NAME, ZONE, and PROJECT_ID to variables.txt
    echo "VM_NAME=$VM_NAME" >> "$SCRIPT_DIR/variables.txt"
    echo "ZONE=$ZONE" >> "$SCRIPT_DIR/variables.txt"
    echo "PROJECT_ID=$PROJECT_ID" >> "$SCRIPT_DIR/variables.txt"

    # Convert the zone to region
    REGION=$(echo $ZONE | sed 's/-[a-z]$//')
    # Fetch the VM's subnet and write it to variables.txt
    VM_SUBNET=$(gcloud compute networks subnets list --filter="region:($REGION)" --format="value(ipCidrRange)" | head -n 1)
    echo "VM_SUBNET=$VM_SUBNET" >> "$SCRIPT_DIR/variables.txt"

    # Prompt the user to enter the hostname and TCP port for the service running on the VM
    printf "\n${YELLOW}To begin, you'll be asked to specify a custom hostname and the corresponding TCP port for the service running on your VM.\n"
    printf "You will be able to set up one or multiple hostname and port pairs.${NC}\n"
    COUNTER=1
    while :; do
        # Prompt the user to enter the hostname they want to configure on Cloudflare for the service running on the VM
        prompt_for_input "Enter the hostname you want to create for the service running on your VM (e.g., example.com):" "HOSTNAME_$COUNTER"
        # Prompt the user to enter the TCP port for the service running on the VM this will be used to create a firewall rule on GCP and to configure Caddy
        prompt_for_input "Enter the local TCP port number for the service running on your VM:" "TCP_PORT_$COUNTER"
        
        # Prompt the user to add more hostnames if they have more than one
        printf "\n${YELLOW}Do you have additional hostnames to add? (y/n): ${NC}"
        read -p "> " ADD_MORE
        if [[ $ADD_MORE =~ ^[Nn](o)?$ ]]; then
            break
        fi
        ((COUNTER++))
    done

    # Prompt the user to enter the VPC name, SSH key username, Tailscale API Access Token, Cloudflare Global API Access Token and Cloudflare Email
    prompt_for_input "Enter your Google Cloud VPC name (leave blank for 'default'):" "YOUR_VPC" true
    prompt_for_input "Enter your SSH key username (the username you use to SSH into your VM, usually appears before the '@' in your SSH command):" "SSH_KEY_USERNAME"
    prompt_for_input "Enter your Tailscale API Access Token (get API here: https://login.tailscale.com/admin/authkeys):" "TAILSCALE_API_ACCESS_TOKEN"
    prompt_for_input "Enter your Cloudflare API Access Token (get Global API here: https://developers.cloudflare.com/fundamentals/api/get-started/create-token//):" "CLOUDFLARE_API_ACCESS_TOKEN"
    prompt_for_input "Enter your Cloudflare ZoneID (get ZoneID here: https://developers.cloudflare.com/fundamentals/setup/find-account-and-zone-ids/):" "CLOUDFLARE_ZONE_ID"
    prompt_for_input "Enter the email address you sign in to Cloudflare with:" "CLOUDFLARE_EMAIL"

    # Message indicating the transition to configuring the server and running setup_tailscale.sh
    printf "\n${GREEN}We've collected all the necessary information. Now proceeding to configure the server and run setup_tailscale.sh.${NC}\n"


    # If setup_tailscale.sh exists, make it executable and run it
    if [ -f "$SCRIPT_DIR/setup_tailscale.sh" ]; then
        chmod +x "$SCRIPT_DIR/setup_tailscale.sh"
        . "$SCRIPT_DIR/setup_tailscale.sh"
    else
        printf "\n${RED}'setup_tailscale.sh' not found in the current directory.${NC}\n"
    fi
else
    printf "\n${RED}Tailscale installation aborted.${NC}\n"
fi
