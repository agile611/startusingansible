FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    openssh-server \
    python3 \
    python3-pip \
    sudo \
    curl \
    vim \
    nano \
    git \
    ansible \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Usuari vagrant amb sudo sense contrasenya
RUN useradd -m -s /bin/bash vagrant && \
    echo "vagrant:vagrant" | chpasswd && \
    echo "vagrant ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Configuració SSH
RUN mkdir -p /var/run/sshd && \
    mkdir -p /home/vagrant/.ssh && \
    chmod 700 /home/vagrant/.ssh

# Genera la clau SSH per a l'usuari vagrant
RUN ssh-keygen -t rsa -b 4096 -f /home/vagrant/.ssh/id_rsa -N "" && \
    cp /home/vagrant/.ssh/id_rsa.pub /home/vagrant/.ssh/authorized_keys && \
    chmod 600 /home/vagrant/.ssh/authorized_keys /home/vagrant/.ssh/id_rsa && \
    chown -R vagrant:vagrant /home/vagrant/.ssh

# Permet login SSH amb clau
RUN sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#AuthorizedKeysFile/AuthorizedKeysFile/' /etc/ssh/sshd_config && \
    sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D"]