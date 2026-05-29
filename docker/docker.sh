#!/bin/bash
set -eux

# Install Docker via get.docker.com
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

# Install docker-compose
curl -L "https://github.com/docker/compose/releases/download/v5.1.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Add vagrant user to docker group
usermod -aG docker vagrant