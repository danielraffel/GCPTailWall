# GCPTailWall README

Have you ever wanted to host a Virtual Machine on Google Cloud where your Cloudflare domain is only accessible via clients on your Tailscale network? This project aims to facilliate setting up your VM with Tailscale for private networking, installing and configuring Caddy as a reverse proxy, and configure new custom Cloudflare DNS hostnames. The configuration has been tested on Ubuntu 22.04.

## Use Case
You aim to run a VM on GCP accessible exclusively at your.domain.com, and want to restrict access to it so that it's only available when you are connected to your Tailscale network, regardless of your location, be it at home or elsewhere.

## Why Use This Script
The process of [setting up Tailscale on your VM](https://tailscale.com/kb/1147/cloud-gce) along with [UFW](https://tailscale.com/kb/1077/secure-server-ubuntu-18-04), installing and configuring [Caddy](https://caddyserver.com), managing DNS settings on Cloudflare, and adjusting your [GCP Firewall rules](https://cloud.google.com/firewall/docs/firewalls) involves numerous steps and is susceptible to mistakes. After navigating through this process myself, I decided to streamline and automate it to some extent, aiming to make it easier for others to implement.

## Prerequisites

- SSH access to a VM running Ubuntu 22.04 on Google Cloud Platform.
- The access scopes for the VM need to be configured to `Allow full access to all Cloud APIs`. As this is not the default configuration, you might have to stop the VM to modify the `Access scopes` settings to activate this feature, before you can restart the VM and run these scripts.
- GCP CLI installed on your VM (usually installed by default)
- Git installed on your VM (usually installed by default)
- [Tailscale account](https://tailscale.com)
- [Tailscale API Access Token](https://developers.cloudflare.com/fundamentals/api/get-started/keys/)
- [Cloudflare Account](https://www.cloudflare.com) with a hosted domain (you'll need to provide the email address you sign in with)
- [Cloudflare API Access Token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)
- [Cloudflare ZoneID](https://developers.cloudflare.com/fundamentals/setup/find-account-and-zone-ids/)

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

- **Tailscale Configuration:** Configures your VM with Tailscale for secure, private networking. You'll be prompted to copy a link to your browser to approve this.
- **UFW Configuration:** Locks down the VM with UFW (Uncomplicated Firewall), making it accessible only via the Tailscale network. Port 22 is left open for SSH access.
- **GCP Firewall Rules:** Opens necessary firewall rules on GCP to ensure Tailscale and specified services running on the hostnames can communicate.
- **Caddy Reverse Proxy:** Configures Caddy to proxy requests to your services based on the hostnames and ports you specify.
- **Cloudflare DNS Management:** Sets up DNS entries on Cloudflare for your services, using the hostnames you provide and directs to your TailscaleIP.

## Configuration Prompts

During the `setup.sh` execution, you'll be prompted to enter the following:

- Custom hostnames for your services and their corresponding TCP port. You can create one or multiple
- Your Google Cloud VPC name (default is used if left blank)
- Your SSH key username.
- Tailscale API Access Token (obtain from [Tailscale Admin](https://login.tailscale.com/admin/authkeys))
- Cloudflare API Access Token (obtain from [Cloudflare API Access Token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)) * Instructions below
- Cloudflare Zone ID (obtain from [ZoneID](https://developers.cloudflare.com/fundamentals/setup/find-account-and-zone-ids/)
- Email address used to sign in to Cloudflare

After `setup.sh` finishes, it automatically executes `setup_GCPTailWall.sh` with the configurations you provided.

## Why jq is Installed

`[jq](https://manpages.ubuntu.com/manpages/xenial/man1/jq.1.html)` is installed as part of the setup to process JSON data, which is necessary for interacting with Tailscale and Cloudflare APIs during the setup process.

## Important Notes
1. If you've not used certain Google Cloud APIs the Google CLI might ask you to enable them and retry again.
2. If you're getting permission errors such as "Request had insufficient authentication scopes" then you probably did not enable the Access Scopes. To fix this go to GCP Console > [Compute Engine](https://console.cloud.google.com/compute/) and then stop the VM you want to install this script on. Once stopped, select `edit` and scroll down to `Access scopes` and select `Allow full access to all Cloud APIs` then press `save` and restart the VM. You need to do this for the Google CLI to have the ability to perform lots of API calls on your behalf.
3. The file `example.variables.txt` includes all possible variables that `setup.sh` creates within `variables.txt`. If you prefer to manually create the file, you can then run `setup_tailscale.sh` with `sudo bash setup_tailscale.sh`.
4 If you're having a hard time Creating a Cloudflare API Token
* Log in to your Cloudflare dashboard.
* Navigate to My Profile > API Tokens.
* Click Create Token.
* Use the "Edit zone DNS" template as a starting point.
* Set permissions to Zone > DNS > Edit.
* Include all the zones you want Caddy to be able to issue certificates for, or select "Include all zones" if you prefer.
* Complete the token creation process.


