#!/bin/bash
# entrypoint.sh
#
# Custom startup script introduced to fix SSH key authentication.
#
# On container start it copies the public key mounted from the host
# (via the docker-compose volume ./ssh:/home/vagrant/.ssh/host_keys)
# into the correct location that sshd reads: ~/.ssh/authorized_keys.
# It then hands off to systemd as usual.

set -e

mkdir -p /home/vagrant/.ssh

if [ -f /home/vagrant/.ssh/host_keys/id_rsa.pub ]; then
    touch /home/vagrant/.ssh/authorized_keys
    # Append only if the key is not already present (idempotent)
    grep -qxF "$(cat /home/vagrant/.ssh/host_keys/id_rsa.pub)" \
        /home/vagrant/.ssh/authorized_keys 2>/dev/null || \
    cat /home/vagrant/.ssh/host_keys/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys
fi

# Enforce correct ownership and permissions required by sshd
chown -R vagrant:vagrant /home/vagrant/.ssh
chmod 700 /home/vagrant/.ssh
chmod 600 /home/vagrant/.ssh/authorized_keys

# Hand off to systemd — same behaviour as the original ENTRYPOINT
exec /lib/systemd/systemd