Vagrant.configure(2) do |config|

  config.vm.define "ansible" do |ansible|
    ansible.vm.box = "generic/debian12"
    ansible.vm.network "private_network", ip: "192.168.56.10"
    ansible.vm.hostname = "ansible"
    ansible.vm.synced_folder ".", "/home/vagrant/sync", type: "rsync"
    ansible.vm.provider "libvirt" do |vb|
      vb.memory = 512
      vb.cpus = 1
      vb.driver = "qemu"
      vb.machine_type = "pc"
      vb.graphics_type = "none"
      vb.video_type = "none"
    end
    ansible.vm.provision :shell, :path => "ansible.sh"
  end

  config.vm.define "database" do |database|
    database.vm.box = "generic/debian12"
    database.vm.network "private_network", ip: "192.168.56.20"
    database.vm.hostname = "database"
    database.vm.synced_folder ".", "/home/vagrant/sync", type: "rsync"
    database.vm.network "forwarded_port", guest: 80, host: 8081
    database.vm.network "forwarded_port", guest: 3306, host: 3306
    database.vm.provider "libvirt" do |vb|
      vb.memory = 512
      vb.cpus = 1
      vb.driver = "qemu"
      vb.machine_type = "pc"
      vb.graphics_type = "none"
      vb.video_type = "none"
    end
  end

  config.vm.define "loadbalancer" do |loadbalancer|
    loadbalancer.vm.box = "generic/debian12"
    loadbalancer.vm.network "private_network", ip: "192.168.56.30"
    loadbalancer.vm.hostname = "loadbalancer"
    loadbalancer.vm.synced_folder ".", "/home/vagrant/sync", type: "rsync"
    loadbalancer.vm.network "forwarded_port", guest: 80, host: 8080
    loadbalancer.vm.network "forwarded_port", guest: 3306, host: 33061
    loadbalancer.vm.provider "libvirt" do |vb|
      vb.memory = 512
      vb.cpus = 1
      vb.driver = "qemu"
      vb.machine_type = "pc"
      vb.graphics_type = "none"
      vb.video_type = "none"
    end
  end

  config.vm.define "webserver" do |webserver|
    webserver.vm.box = "generic/debian12"
    webserver.vm.network "private_network", ip: "192.168.56.40"
    webserver.vm.hostname = "webserver"
    webserver.vm.synced_folder ".", "/home/vagrant/sync", type: "rsync"
    webserver.vm.network "forwarded_port", guest: 80, host: 80
    webserver.vm.network "forwarded_port", guest: 3306, host: 33062
    webserver.vm.provider "libvirt" do |vb|
      vb.memory = 512
      vb.cpus = 1
      vb.driver = "qemu"
      vb.machine_type = "pc"
      vb.graphics_type = "none"
      vb.video_type = "none"
    end
  end

end