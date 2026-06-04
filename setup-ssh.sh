#!/bin/bash
# setup-ssh.sh
# Distributes SSH keys between the Ansible control node and managed nodes

set -e

SSH_DIR="./ssh"
CONTROL_NODE="ansible"
MANAGED_NODES=("ansible" "database" "loadbalancer" "webserver")

echo "🔑 Setting up SSH keys..."

# Verify keys exist on host before doing anything
if [ ! -f "$SSH_DIR/id_rsa" ] || [ ! -f "$SSH_DIR/id_rsa.pub" ]; then
  echo "❌ Keys not found in $SSH_DIR — run: ssh-keygen -t rsa -b 2048 -f ssh/id_rsa -N \"\""
  exit 1
fi

PRIV_KEY=$(cat "$SSH_DIR/id_rsa")
PUB_KEY=$(cat "$SSH_DIR/id_rsa.pub")

# --- Control node: inject private + public key ---
echo "📋 Copying keys to control node: $CONTROL_NODE"
docker exec "$CONTROL_NODE" bash -c "
  mkdir -p /home/vagrant/.ssh &&
  chmod 700 /home/vagrant/.ssh &&
  printf '%s\n' '$PRIV_KEY' > /home/vagrant/.ssh/id_rsa &&
  printf '%s\n' '$PUB_KEY'  > /home/vagrant/.ssh/id_rsa.pub &&
  chmod 600 /home/vagrant/.ssh/id_rsa &&
  chmod 644 /home/vagrant/.ssh/id_rsa.pub &&
  chown -R vagrant:vagrant /home/vagrant/.ssh
"

# --- All nodes: inject public key into authorized_keys ---
for container in "${MANAGED_NODES[@]}"; do
  echo "🔓 Injecting public key into: $container"
  docker exec "$container" bash -c "
    mkdir -p /home/vagrant/.ssh &&
    chmod 700 /home/vagrant/.ssh &&
    echo '$PUB_KEY' >> /home/vagrant/.ssh/authorized_keys &&
    sort -u /home/vagrant/.ssh/authorized_keys -o /home/vagrant/.ssh/authorized_keys &&
    chmod 600 /home/vagrant/.ssh/authorized_keys &&
    chown -R vagrant:vagrant /home/vagrant/.ssh
  "
done

echo "✅ SSH setup complete."