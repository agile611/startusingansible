#!/bin/bash
# setup-ssh.sh
# Distributes SSH keys between the Ansible control node and managed nodes

set -e

SSH_DIR="./ssh"
CONTROL_NODE="ansible"
MANAGED_NODES=("database" "loadbalancer" "webserver")

echo "🔑 Setting up SSH keys..."

# --- Control node ---
echo "📋 Copying private key to control node: $CONTROL_NODE"
docker exec "$CONTROL_NODE" bash -c "
  mkdir -p /home/vagrant/.ssh &&
  chmod 700 /home/vagrant/.ssh &&
  cp /home/vagrant/.ssh/host_keys/id_rsa /home/vagrant/.ssh/id_rsa &&
  cp /home/vagrant/.ssh/host_keys/id_rsa.pub /home/vagrant/.ssh/id_rsa.pub &&
  chmod 600 /home/vagrant/.ssh/id_rsa &&
  chown -R vagrant:vagrant /home/vagrant/.ssh
"

# --- Managed nodes ---
PUB_KEY=$(cat "$SSH_DIR/id_rsa.pub")

for container in "${MANAGED_NODES[@]}"; do
  echo "🔓 Injecting public key into: $container"
  docker exec "$container" bash -c "
    mkdir -p /home/vagrant/.ssh &&
    chmod 700 /home/vagrant/.ssh &&
    echo '$PUB_KEY' >> /home/vagrant/.ssh/authorized_keys &&
    chmod 600 /home/vagrant/.ssh/authorized_keys &&
    chown -R vagrant:vagrant /home/vagrant/.ssh
  "
done

echo "✅ SSH setup complete."