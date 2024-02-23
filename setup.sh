#!/bin/bash

# Define colors
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

printf "\n${YELLOW}Running this script on your Google Cloud VM will assist you in configuring Tailscale and Caddy.\n"
printf "It will also set up Cloudflare DNS Hostnames to serve sites only accessible within your tailnet.${NC}\n\n"
printf "Do you want to continue? (y/n): "
read -p "> " INSTALL_CHOICE

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

if [[ $INSTALL_CHOICE =~ ^[Yy](es)?$ ]]; then
    > "$SCRIPT_DIR/variables.txt" # Clear the file to start fresh or create it if it doesn't exist

    printf "\n${YELLOW}To begin, you'll be asked to specify a custom hostname and the corresponding TCP port for the service running on your VM.\n"
    printf "You will be able to set up one or multiple hostname and port pairs.${NC}\n"
    COUNTER=1
    while :; do
        prompt_for_input "Enter the hostname you want to create for the service running on your VM (e.g., example.com):" "HOSTNAME_$COUNTER"
        # Directly ask for TCP port here
        prompt_for_input "Enter the local TCP port number for the service running on your VM:" "TCP_PORT_$COUNTER"
        
        printf "\n${YELLOW}Do you have additional hostnames to add? (y/n): ${NC}"
        read -p "> " ADD_MORE
        if [[ $ADD_MORE =~ ^[Nn](o)?$ ]]; then
            break
        fi
        ((COUNTER++))
    done

    prompt_for_input "Enter your Google Cloud VPC name (leave blank for 'default'):" "YOUR_VPC" true
    prompt_for_input "Enter your SSH key username (the username you use to SSH into your VM, usually appears before the '@' in your SSH command):" "SSH_KEY_USERNAME"
    prompt_for_input "Enter your Tailscale API Access Token (get it here: https://login.tailscale.com/admin/authkeys):" "TAILSCALE_API_ACCESS_TOKEN"
    prompt_for_input "Enter your Cloudflare Global API Access Token (get it here: https://developers.cloudflare.com/fundamentals/api/get-started/keys/):" "CLOUDFLARE_API_ACCESS_TOKEN"

    if [ -f "$SCRIPT_DIR/setup_tailscale.sh" ]; then
        chmod +x "$SCRIPT_DIR/setup_tailscale.sh"
        . "$SCRIPT_DIR/setup_tailscale.sh"
    else
        printf "\n${RED}'setup_tailscale.sh' not found in the current directory.${NC}\n"
    fi
else
    printf "\n${RED}Tailscale installation aborted.${NC}\n"
fi