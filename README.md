# GCPTailWall README

Have you ever wanted to host a Virtual Machine on Google Cloud where your Cloudflare domain is only accessible via clients on your Tailscale network? This project aims to facilliate setting up your VM with Tailscale for private networking, installing and configuring Caddy as a reverse proxy, and configure new custom Cloudflare DNS hostnames. The configuration has been tested on Ubuntu 22.04.

## Prerequisites

- A VM running Ubuntu 22.04 on Google Cloud Platform
- GCP CLI installed on your VM (usually installed by default)
- Git installed on your VM
- Tailscale account
- [Tailscale API Access Token](https://developers.cloudflare.com/fundamentals/api/get-started/keys/)
- Cloudflare Account with a hosted domain
- [Cloudflare Global API Access Token](https://login.tailscale.com/admin/authkeys)

## Quick Start

1. **Clone the Repository**

   On your VM, clone this repository to get started:

   ```bash
   git clone https://github.com/danielraffel/GCPTailWall.git
   ```

2. **Change Directory**

   Change into the cloned directory:

   ```bash
   cd GCPTailWall
   ```

3. **Run Setup Script**

   Execute the setup script with sudo privileges:

   ```bash
   sudo bash setup.sh
   ```

   Note: Running `setup.sh` will create a `variables.txt` file. If you rerun the script and this file exists, it will automatically execute `setup_GCPTailWall.sh` with the previous configurations. Delete `variables.txt` if you wish to start fresh.

## What `setup_GCPTailWall.sh` Does

- **Tailscale Configuration:** Configures your VM with Tailscale for secure, private networking.
- **UFW Configuration:** Locks down the VM with UFW (Uncomplicated Firewall), making it accessible only via the Tailscale network. Port 22 is left open for SSH access.
- **GCP Firewall Rules:** Opens necessary firewall rules on GCP to ensure Tailscale and specified services running on the hostnames can communicate.
- **Caddy Reverse Proxy:** Uses Caddy to proxy requests to your services based on hostnames and ports you specify.
- **Cloudflare DNS Management:** Sets up DNS entries on Cloudflare for your services, using the hostnames you provide and directs to your TailscaleIP.

## Configuration Prompts

During the `setup.sh` execution, you'll be prompted to enter:

- Custom hostnames for your services and their corresponding TCP port. You can create one or multiple.
- Your Google Cloud VPC name (default is used if left blank).
- Your SSH key username (used for SSH into your VM).
- Tailscale API Access Token (obtain from [Tailscale Admin](https://login.tailscale.com/admin/authkeys)).
- Cloudflare Global API Access Token (obtain from [Cloudflare API Tokens](https://developers.cloudflare.com/fundamentals/api/get-started/keys/)).

After `setup.sh` finishes, it automatically executes `setup_GCPTailWall.sh` with the provided configurations.

## Why jq is Installed

`jq` is installed as part of the setup to process JSON data, which is necessary for interacting with Tailscale and Cloudflare APIs during the setup process.

## Important Notes

- This setup assumes you have GCP CLI installed on your VM. The script does not check for its presence.
