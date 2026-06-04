#!/bin/bash
# entrypoint.sh

set -e

mkdir -p /home/vagrant/.ssh

if [ -f /home/vagrant/.ssh/host_keys/id_rsa.pub ]; then
    touch /home/vagrant/.ssh/authorized_keys
    grep -qxF "$(cat /home/vagrant/.ssh/host_keys/id_rsa.pub)" \
        /home/vagrant/.ssh/authorized_keys 2>/dev/null || \
    cat /home/vagrant/.ssh/host_keys/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys

    # Only set permissions if the file was actually created
    chown -R vagrant:vagrant /home/vagrant/.ssh
    chmod 700 /home/vagrant/.ssh
    chmod 600 /home/vagrant/.ssh/authorized_keys
fi

exec /lib/systemd/systemd