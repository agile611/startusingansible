FROM jrei/systemd-debian:latest

LABEL maintainer='guillem@agile611.com'

ENV container=docker \
    DEBIAN_FRONTEND=noninteractive

# Install necessary packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    findutils \
    iproute2 \
    python3 \
    python3-apt \
    sudo \
    curl \
    vim \
    nano \
    git \
    dnsutils \
    iputils-ping \
    openssh-server \
    systemd \
    systemd-sysv \
    telnet \
    net-tools \
    netcat-openbsd \
    ansible \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Setup SSH for Ansible
RUN mkdir -p /var/run/sshd && \
    echo "vagrant:vagrant" | chpasswd && \
    echo "vagrant ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Enable SSH service
RUN systemctl enable ssh

VOLUME ["/sys/fs/cgroup"]

EXPOSE 22

ENTRYPOINT ["/lib/systemd/systemd"]