#!/bin/bash

# Change directory to the script's location
cd "$(dirname "$0")"

# Load variables from variables.txt
source variables.txt

# Enable IP Forwarding for the VM
echo "Enabling IP Forwarding on the VM..."
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

gcloud compute instances add-metadata $(hostname) --metadata enable-ip-forwarding=true --zone="$ZONE" --project="$PROJECT_ID"

# Install Tailscale
echo "Adding Tailscale’s package signing key and repository..."
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list

echo "Installing Tailscale..."
sudo apt-get update && sudo apt-get install tailscale -y

# Install Caddy
echo "Installing Caddy..."
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo tee /etc/apt/trusted.gpg.d/caddy-stable.asc
echo "deb https://dl.cloudsmith.io/public/caddy/stable/deb/debian buster main" | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt-get update && sudo apt-get install caddy -y

# Modify Caddyfile
echo "Modifying /etc/caddy/Caddyfile with reverse proxy settings..."
sudo cp /dev/null /etc/caddy/Caddyfile # Clear existing Caddyfile contents before appending
{
    while read -r line; do
        if [[ "$line" =~ ^HOSTNAME_([0-9]+)=(.*)$ ]]; then
            hostname=${BASH_REMATCH[2]}
            varname="TCP_PORT_${BASH_REMATCH[1]}"
            port=${!varname}
            echo "$hostname {
    reverse_proxy localhost:$port
}"
        fi
    done < variables.txt
} | sudo tee -a /etc/caddy/Caddyfile

# Reload Caddy to apply the new configuration
echo "Reloading Caddy to apply configuration changes..."
sudo systemctl reload caddy

# Install jq
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

# Add GCE DNS for your tailnet
echo "Adding GCE DNS for your tailnet..."
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

# Setup firewall rules on GCP for hostnames
echo "Setting up firewall rules on GCP for each TCP port..."
for i in $(seq 1 $(grep -c 'HOSTNAME_' variables.txt)); do
    HOST_VAR="HOSTNAME_$i"
    PORT_VAR="TCP_PORT_$i"
    gcloud compute firewall-rules create "${!HOST_VAR}" --direction=INGRESS --priority=1000 \
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
for i in $(seq 1 $(grep -c 'HOSTNAME_' variables.txt)); do
    HOST_VAR="HOSTNAME_$i"
    # Use Cloudflare API to create DNS record
    curl --request POST \
      --url https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records \
      --header "Content-Type: application/json" \
      --header "X-Auth-Email: $CLOUDFLARE_EMAIL" \
      --header "X-Auth-Key: $CLOUDFLARE_GLOBAL_API_KEY" \
      --data "{\"type\":\"A\",\"name\":\"${!HOST_VAR}\",\"content\":\"$TAILSCALE_IP\",\"ttl\":3600,\"proxied\":false}"
done

echo "Tailscale setup and configuration complete."
