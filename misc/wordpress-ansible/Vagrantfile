Vagrant.configure(2) do |config|
    # Máquina de control para el agente Ansible
    config.vm.define "ansible" do |control|
      control.vm.box = "bento/ubuntu-24.04" # Imagen base Ubuntu 24.04
      control.vm.network "private_network", ip: "192.168.11.11" # IP privada
      control.vm.hostname = "ansible" # Nombre de host
      control.vm.synced_folder ".", "/home/vagrant/sync", type: "rsync" # Carpeta sincronizada
      control.vm.provider "virtualbox" do |vb|
        vb.memory = 512 # Memoria RAM asignada
        vb.cpus = 1     # Número de CPUs asignadas
      end
      control.vm.provision :shell, :path => "ansible.sh" # Script de aprovisionamiento
    end

    # Máquina para la base de datos
    config.vm.define "database" do |database|
      database.vm.box = "bento/ubuntu-24.04"
      database.vm.network "private_network", ip: "192.168.11.20"
      database.vm.hostname = "database"
      database.vm.synced_folder ".", "/home/vagrant/sync", type: "rsync"
      database.vm.network "forwarded_port", guest: 80, host: 8081 # Redirección del puerto 80
      database.vm.network "forwarded_port", guest: 3306, host: 3306 # Redirección del puerto MySQL
      database.vm.provider "virtualbox" do |vb|
        vb.memory = 512
        vb.cpus = 1
      end
    end

    # Máquina para el balanceador de carga
    config.vm.define "loadbalancer" do |loadbalancer|
      loadbalancer.vm.box = "bento/ubuntu-24.04"
      loadbalancer.vm.network "private_network", ip: "192.168.11.30"
      loadbalancer.vm.hostname = "loadbalancer"
      loadbalancer.vm.synced_folder ".", "/home/vagrant/sync", type: "rsync"
      loadbalancer.vm.network "forwarded_port", guest: 80, host: 8080 # Redirección del puerto 80
      loadbalancer.vm.network "forwarded_port", guest: 3306, host: 33061 # Redirección del puerto MySQL alternativo
      loadbalancer.vm.provider "virtualbox" do |vb|
        vb.memory = 512
        vb.cpus = 1
      end
    end

    # Máquina para el servidor web
    config.vm.define "webserver" do |webserver|
      webserver.vm.box = "bento/ubuntu-24.04"
      webserver.vm.network "private_network", ip: "192.168.11.40"
      webserver.vm.hostname = "webserver"
      webserver.vm.synced_folder ".", "/home/vagrant/sync", type: "rsync"
      webserver.vm.network "forwarded_port", guest: 80, host: 80 # Redirección del puerto 80
      webserver.vm.network "forwarded_port", guest: 3306, host: 33062 # Redirección del puerto MySQL alternativo
      webserver.vm.provider "virtualbox" do |vb|
        vb.memory = 512
        vb.cpus = 1
      end
    end
  end