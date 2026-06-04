FROM jrei/systemd-debian:latest

LABEL maintainer='guillem@agile611.com'

ENV container=docker \
    DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# ---------------------------------------------------------------------------
# Install necessary packages
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    vim \
    ansible \
    locales \
    sudo \
    python3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ---------------------------------------------------------------------------
# Generate locale
# Write /etc/default/locale directly — never use update-locale inside Docker
# ---------------------------------------------------------------------------
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen \
    && printf 'LANG=en_US.UTF-8\nLANGUAGE=en_US:en\nLC_ALL=en_US.UTF-8\n' > /etc/default/locale

# ---------------------------------------------------------------------------
# Create the vagrant user with correct home ownership
# ---------------------------------------------------------------------------
RUN useradd -m -s /bin/bash vagrant && \
    echo "vagrant:vagrant" | chpasswd && \
    chown -R vagrant:vagrant /home/vagrant

# ---------------------------------------------------------------------------
# Grant vagrant passwordless sudo via drop-in file
# ---------------------------------------------------------------------------
RUN echo "vagrant ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vagrant \
    && chmod 0440 /etc/sudoers.d/vagrant

# ---------------------------------------------------------------------------
# Configure SSH
# ---------------------------------------------------------------------------
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config && \
    sed -i '/^session required pam_nologin.so/d' /etc/pam.d/sshd

# ---------------------------------------------------------------------------
# Enable SSH service
# ---------------------------------------------------------------------------
RUN systemctl enable ssh

EXPOSE 22

VOLUME ["/sys/fs/cgroup"]

# ---------------------------------------------------------------------------
# FIX 1 — SSH key authentication (2026-06-03)
#
# Problem:  The control node's public key was not being copied to
#           ~vagrant/.ssh/authorized_keys inside the remote container,
#           making SSH key-based authentication impossible.
#
# Solution: Replace the direct systemd entrypoint with a custom startup
#           script (entrypoint.sh) that, on every container start, copies
#           the public key mounted from the host into authorized_keys.
#
# Related files:
#   - entrypoint.sh        (created — see below)
#   - docker-compose.yml   (volume already present):
#       volumes:
#         - ./ssh:/home/vagrant/.ssh/host_keys
#
# The volume provides the public key; entrypoint.sh moves it to the
# location SSH actually reads: ~/.ssh/authorized_keys.
#
# Before:
#   ENTRYPOINT ["/lib/systemd/systemd"]
#
# After (current):
# ---------------------------------------------------------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ---------------------------------------------------------------------------
# FIX 2 — SSH connection stability (2026-06-03)
#
# Problem:  Playbook runs caused SSH connection drops when multiple
#           consecutive sessions were opened against the same host,
#           likely due to limited container resources.
#
# Solution: Tune ansible.cfg to reuse SSH sessions, extend timeouts,
#           enable pipelining, and allow retries. Key parameters added:
#
#   [defaults]
#     timeout = 30               # Longer connection timeout
#
#   [ssh_connection]
#     ControlMaster=auto         # Reuse existing SSH connections
#     ControlPersist=60s         # Keep master socket alive 60 s
#     ServerAliveInterval=30     # Keepalive probe every 30 s
#     ServerAliveCountMax=3      # Tolerate 3 missed probes before drop
#     pipelining = True          # Fewer SSH round-trips per task
#     retries = 5                # Retry on transient failures
#     control_path = %(directory)s/%%h-%%r
# ---------------------------------------------------------------------------

ENTRYPOINT ["/entrypoint.sh"]