#!/bin/bash
# Uncomment the next line for some help debugging
# set -x

# Set path to the directory containing the script
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Change directory to the script's location
cd "$(dirname "$0")"

# Load variables from variables.txt
source "${SCRIPT_DIR}/variables.txt"

# Enable IP Forwarding for the VM
echo "Enabling IP Forwarding on the VM..."
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

# Enable IP Forwarding for the VM in GCP
gcloud compute instances add-metadata $(hostname) --metadata enable-ip-forwarding=true --zone="$ZONE" --project="$PROJECT_ID"

# Install Tailscale
echo "Adding Tailscale’s package signing key and repository..."
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list

echo "Installing Tailscale..."
sudo apt-get update && sudo apt-get install tailscale -y

# Download the custom Caddy binary
echo "Downloading the custom Caddy binary..."
sudo curl -o caddy_linux_amd64_custom "https://caddyserver.com/api/download?os=linux&arch=amd64&p=github.com%2Fcaddy-dns%2Fcloudflare&idempotency=90496132318341"

# Check if Caddy service is running and stop it if it is active
if systemctl is-active --quiet caddy; then
    echo "Caddy is running. Stopping Caddy service..."
    sudo systemctl stop caddy
fi

# Move the Caddy binary and ensure it is executable
echo "Moving the custom Caddy binary and setting it as executable..."
sudo mv caddy_linux_amd64_custom /usr/bin/caddy
sudo chmod +x /usr/bin/caddy

# Display Caddy version to verify the move
caddy version

# Reload systemd daemon to recognize any changes to the service file
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

# Enable Caddy service to start at boot
echo "Enabling Caddy service to start at boot..."
sudo systemctl enable caddy

# Start Caddy service
echo "Starting Caddy service..."
sudo systemctl start caddy

# Verify the Caddy service status
echo "Verifying the Caddy service status..."
if systemctl is-active --quiet caddy; then
    echo "Caddy is running successfully."
else
    echo "Caddy service failed to start. Please check logs for errors: journalctl -u caddy"
    # Optionally, output the last few lines of the Caddy log for immediate troubleshooting
    journalctl -u caddy -n 20
fi

# Initialize variable
CLOUDFLARE_API_ACCESS_TOKEN=""

# Load Cloudflare API token from variables.txt
while IFS='=' read -r key value; do
    if [[ "$key" == "CLOUDFLARE_API_ACCESS_TOKEN" ]]; then
        CLOUDFLARE_API_ACCESS_TOKEN="$value"
    fi
done < "${SCRIPT_DIR}/variables.txt"

# Check if the token was found
if [ -z "$CLOUDFLARE_API_ACCESS_TOKEN" ]; then
    echo "CLOUDFLARE_API_ACCESS_TOKEN not found in variables.txt"
    exit 1
fi

# Use systemctl edit to create an override file for Caddy
echo -e "[Service]\nEnvironment=\"CLOUDFLARE_API_ACCESS_TOKEN=$CLOUDFLARE_API_ACCESS_TOKEN\"" | sudo SYSTEMD_EDITOR="tee" systemctl edit caddy

# Reload systemd to apply changes and restart Caddy service
sudo systemctl daemon-reload
sudo systemctl restart caddy

echo "Caddy service has been updated and restarted with the new Cloudflare API Access Token."

# Modify Caddyfile with reverse proxy settings and Cloudflare DNS challenge
echo "Modifying /etc/caddy/Caddyfile with reverse proxy settings and Cloudflare DNS challenge..."
sudo cp /dev/null /etc/caddy/Caddyfile # Clear existing Caddyfile contents before appending

# Loop through variables.txt to configure each site
{
    while IFS= read -r line; do
        if [[ "$line" =~ ^HOSTNAME_([0-9]+)=(.*)$ ]]; then
            hostname=${BASH_REMATCH[2]}
            varname="TCP_PORT_${BASH_REMATCH[1]}"
            port=${!varname}
            # Append site configuration with reverse proxy and TLS using Cloudflare DNS challenge
            echo "# Configuring $hostname to proxy to port $port"
            echo "$hostname {
    reverse_proxy localhost:$port
    tls {
        dns cloudflare {env.CLOUDFLARE_API_ACCESS_TOKEN}
    }
}"
        fi
    done < "${SCRIPT_DIR}/variables.txt"
} | sudo tee -a /etc/caddy/Caddyfile

# Reload Caddy to apply the new configuration
echo "Reloading Caddy to apply configuration changes..."
sudo caddy fmt --overwrite /etc/caddy/Caddyfile
sudo systemctl reload caddy

# Install jq to parse JSON responses
echo "Installing jq..."
sudo apt-get install jq -y

# Connect the machine to the Tailscale network
echo "Connecting the machine to the Tailscale network..."
sudo tailscale up

# Configure Tailscale to auto-update
echo "Configuring Tailscale to auto-update..."
sudo tailscale set --auto-update

# Fetch the VM's Tailscale IP
TAILSCALE_IP=$(tailscale ip -4)
echo "Tailscale IP: $TAILSCALE_IP"

# Advertise routes
echo "Advertising routes..."
sudo tailscale up --accept-dns=false --advertise-routes="$VM_SUBNET" --accept-routes --operator="$SSH_KEY_USERNAME"

# Add Google Compute Engine DNS for your tailnet
echo "Adding Google Compute Engine DNS for your tailnet..."
gcloud dns policies create inbound-dns --project="$PROJECT_ID" \
  --description="Expose DNS endpoints per subnet" \
  --networks="$YOUR_VPC" \
  --enable-inbound-forwarding

# Verify that your tailnet recognizes the DNS resolver for your tailnet subnet
IP_GCLOUD_COMPUTE_ADDRESSES_LIST=$(gcloud compute addresses list \
  --project="$PROJECT_ID" \
  --filter='purpose="DNS_RESOLVER"' \
  --format='csv(address, region, subnetwork)' \
  | grep "$VM_SUBNET" | cut -d',' -f1)

# Check Tailscale DNS
DNS_RESPONSE=$(curl -s "https://api.tailscale.com/api/v2/tailnet/-/dns/nameservers?fields=all" \
  -u "$TAILSCALE_API_ACCESS_TOKEN:")

if echo "$DNS_RESPONSE" | jq -e '.dns[] | select(startswith("100."))' >/dev/null; then
    echo "The DNS resolver IP address from gcloud is in the 100.64.0.0/10 subnet. Skipping setting it as DNS resolver."
else
    echo "Setting the IP address from gcloud as a DNS resolver for the tailnet."
    curl -X POST "https://api.tailscale.com/api/v2/tailnet/-/dns/nameservers" \
      -u "$TAILSCALE_API_ACCESS_TOKEN:" \
      --data-binary "{\"dns\": [\"$IP_GCLOUD_COMPUTE_ADDRESSES_LIST\"]}"
fi

# Setup firewall rules on GCP for Tailscale
echo "Setting up firewall rules for Tailscale IPv4 and IPv6..."
gcloud compute firewall-rules create tailscaleipv4 --direction=INGRESS --priority=1000 \
  --network="$YOUR_VPC" --action=ALLOW --rules=udp:41641 --source-ranges=0.0.0.0/0 --project="$PROJECT_ID"

gcloud compute firewall-rules create tailscaleipv6 --direction=INGRESS --priority=1000 \
  --network="$YOUR_VPC" --action=ALLOW --rules=udp:41641 --source-ranges=::/0 --project="$PROJECT_ID"

# Setup firewall rules on GCP for each TCP port
echo "Setting up firewall rules on GCP for each TCP port..."
for i in $(seq 1 $(grep -c 'HOSTNAME_' variables.txt)); do
    HOST_VAR="HOSTNAME_$i"
    PORT_VAR="TCP_PORT_$i"
    # Convert hostname to comply with GCP naming conventions: lowercase and replace dots with hyphens
    GCP_SAFE_NAME=$(echo "${!HOST_VAR}" | tr '.' '-' | tr '[:upper:]' '[:lower:]')
    gcloud compute firewall-rules create "$GCP_SAFE_NAME" --direction=INGRESS --priority=1000 \
      --network="$YOUR_VPC" --action=ALLOW --rules=tcp:"${!PORT_VAR}" --source-ranges=0.0.0.0/0 --project="$PROJECT_ID"
done

# Enable UFW and configure rules to block non tailscale traffic but support SSH access to the VM to avoid getting locked out 
echo "Configuring UFW..."
sudo ufw enable
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp

# Check UFW status and restart UFW and SSH service
sudo ufw status verbose
sudo ufw reload
sudo service ssh restart

# Create DNS records on Cloudflare for each hostname
echo "Creating DNS records on Cloudflare for each hostname..."
# Loop through each line in variables.txt to find HOSTNAME_X variables
while IFS='=' read -r key value; do
    if [[ "$key" =~ ^HOSTNAME_([0-9]+)$ ]]; then
        hostname="$value"
        index="${BASH_REMATCH[1]}"
        port_varname="TCP_PORT_$index"
        port="${!port_varname}"

        echo "Creating DNS record for $hostname with IP $TAILSCALE_IP and port $port..."

        # Use Cloudflare API to create DNS record
        curl --request POST \
          --url https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records \
          --header "Authorization: Bearer $CLOUDFLARE_API_ACCESS_TOKEN" \
          --header "Content-Type: application/json" \
          --data "{\"type\":\"A\",\"name\":\"$hostname\",\"content\":\"$TAILSCALE_IP\",\"ttl\":3600,\"proxied\":false}"
    fi
done < "${SCRIPT_DIR}/variables.txt"

echo "Tailscale setup and configuration complete."
