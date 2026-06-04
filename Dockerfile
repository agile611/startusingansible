FROM jrei/systemd-debian:latest

LABEL maintainer='guillem@agile611.com'

ENV container=docker \
    DEBIAN_FRONTEND=noninteractive

# Install necessary packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    vim \
    ansible \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create the vagrant user
RUN useradd -m -s /bin/bash vagrant && \
    echo "vagrant:vagrant" | chpasswd && \
    echo "vagrant ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Configure SSH
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config && \
    sed -i '/^session required pam_nologin.so/d' /etc/pam.d/sshd

# Enable SSH service
RUN systemctl enable ssh

# Expose SSH port
EXPOSE 22

# Start systemd
VOLUME ["/sys/fs/cgroup"]

ENTRYPOINT ["/lib/systemd/systemd"]