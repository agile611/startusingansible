FROM jrei/systemd-debian:latest

LABEL maintainer='guillem@agile611.com'

ENV container=docker \
    DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Install necessary packages + generate locale
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    vim \
    ansible \
    locales \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Generate locale and write config directly (update-locale fails in Docker build context)
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen \
    && echo "LANG=en_US.UTF-8\nLANGUAGE=en_US:en\nLC_ALL=en_US.UTF-8" > /etc/default/locale

# Create the vagrant user with correct home ownership
RUN useradd -m -s /bin/bash vagrant && \
    echo "vagrant:vagrant" | chpasswd && \
    echo "vagrant ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    chown -R vagrant:vagrant /home/vagrant

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