FROM debian:trixie-slim

LABEL maintainer='guillem@agile611.com'

ENV container=docker \
    DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# ---------------------------------------------------------------------------
# Install systemd + necessary packages
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd \
    systemd-sysv \
    dbus \
    openssh-server \
    vim \
    ansible \
    locales \
    sudo \
    python3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ---------------------------------------------------------------------------
# Clean up systemd units that don't work inside containers
# ---------------------------------------------------------------------------
RUN find /etc/systemd/system \
         /lib/systemd/system \
         -path '*.wants/*' \
         \( -name '*getty*' \
            -o -name '*plymouth*' \
            -o -name '*udev*' \
            -o -name '*systemd-remount*' \
            -o -name '*systemd-firstboot*' \
            -o -name '*systemd-machine-id-commit*' \
         \) \
         -delete || true

RUN systemctl mask \
    dev-hugepages.mount \
    sys-fs-fuse-connections.mount \
    systemd-remount-fs.service \
    systemd-firstboot.service \
    systemd-machine-id-commit.service || true

# ---------------------------------------------------------------------------
# Generate locale
# ---------------------------------------------------------------------------
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen \
    && printf 'LANG=en_US.UTF-8\nLANGUAGE=en_US:en\nLC_ALL=en_US.UTF-8\n' > /etc/default/locale

# ---------------------------------------------------------------------------
# Create the vagrant user
# ---------------------------------------------------------------------------
RUN useradd -m -s /bin/bash vagrant && \
    echo "vagrant:vagrant" | chpasswd && \
    chown -R vagrant:vagrant /home/vagrant

# ---------------------------------------------------------------------------
# Grant vagrant passwordless sudo
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

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]