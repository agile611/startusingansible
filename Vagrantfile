Vagrant.configure(2) do |config|
  # Màquina de control per a l'agent Ansible
  config.vm.define "ansible" do |ansible|
    ansible.vm.box = "bento/debian-13.1"
    ansible.vm.network "private_network", ip: "192.168.56.10"
    ansible.vm.hostname = "ansible"
    ansible.vm.synced_folder ".", "/home/vagrant/sync", type: "rsync"
    ansible.vm.provider "libvirt" do |vb|
      vb.memory = 512
      vb.cpus = 1
    end
    ansible.vm.provision :shell, :path => "ansible.sh"
  end

  # Màquina per a la base de dades
  config.vm.define "database" do |database|
    database.vm.box = "bento/debian-13.1"
    database.vm.network "private_network", ip: "192.168.56.20"
    database.vm.hostname = "database"
    database.vm.synced_folder ".", "/home/vagrant/sync", type: "rsync"
    database.vm.network "forwarded_port", guest: 80, host: 8081
    database.vm.network "forwarded_port", guest: 3306, host: 3306
    database.vm.provider "libvirt" do |vb|
      vb.memory = 512
      vb.cpus = 1
    end
  end

  # Màquina per al balancejador de càrrega
  config.vm.define "loadbalancer" do |loadbalancer|
    loadbalancer.vm.box = "bento/debian-13.1"
    loadbalancer.vm.network "private_network", ip: "192.168.56.30"
    loadbalancer.vm.hostname = "loadbalancer"
    loadbalancer.vm.synced_folder ".", "/home/vagrant/sync", type: "rsync"
    loadbalancer.vm.network "forwarded_port", guest: 80, host: 8080
    loadbalancer.vm.network "forwarded_port", guest: 3306, host: 33061
    loadbalancer.vm.provider "libvirt" do |vb|
      vb.memory = 512
      vb.cpus = 1
    end
  end

  # Màquina per al servidor web
  config.vm.define "webserver" do |webserver|
    webserver.vm.box = "bento/debian-13.1"
    webserver.vm.network "private_network", ip: "192.168.56.40"
    webserver.vm.hostname = "webserver"
    webserver.vm.synced_folder ".", "/home/vagrant/sync", type: "rsync"
    webserver.vm.network "forwarded_port", guest: 80, host: 80
    webserver.vm.network "forwarded_port", guest: 3306, host: 33062
    webserver.vm.provider "libvirt" do |vb|
      vb.memory = 512
      vb.cpus = 1
    end
  end
end