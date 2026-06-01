FROM debian:trixie

LABEL maintainer='guillem@agile611.com'

ENV container=docker \
    DEBIAN_FRONTEND=noninteractive

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

# Neteja units innecessàries per a Docker
RUN find /etc/systemd/system \
        /lib/systemd/system \
        -path '*.wants/*' \
        -not -name '*journald*' \
        -not -name '*systemd-tmpfiles*' \
        -not -name '*systemd-user-sessions*' \
        -print0 | xargs -0 rm -vf

# Desactiva serveis incompatibles amb Docker
RUN systemctl mask \
    getty.target \
    console-getty.service \
    systemd-logind.service \
    systemd-remount-fs.service \
    systemd-ask-password-wall.path

# Redueix el soroll de journald
RUN echo "ReadKMsg=no" >> /etc/systemd/journald.conf

# Usuari vagrant amb sudo sense contrasenya
RUN useradd -m -s /bin/bash vagrant && \
    echo "vagrant:vagrant" | chpasswd && \
    echo "vagrant ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Configuració SSH
RUN mkdir -p /var/run/sshd && \
    mkdir -p /home/vagrant/.ssh && \
    chmod 700 /home/vagrant/.ssh

# Genera clau SSH per a l'usuari vagrant
RUN ssh-keygen -t rsa -b 4096 -f /home/vagrant/.ssh/id_rsa -N "" && \
    cp /home/vagrant/.ssh/id_rsa.pub /home/vagrant/.ssh/authorized_keys && \
    chmod 600 /home/vagrant/.ssh/authorized_keys /home/vagrant/.ssh/id_rsa && \
    chown -R vagrant:vagrant /home/vagrant/.ssh

# Configuració sshd_config
RUN sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#AuthorizedKeysFile/AuthorizedKeysFile/' /etc/ssh/sshd_config && \
    sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Habilita SSH com a servei de systemd
RUN systemctl enable ssh

VOLUME ["/sys/fs/cgroup"]

EXPOSE 22

ENTRYPOINT ["/lib/systemd/systemd"]