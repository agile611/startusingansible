Vagrant.configure(2) do |config|
  config.vm.define "docker" do |docker|
    docker.vm.box = "bento/debian-13.1"
    docker.vm.network "private_network", ip: "192.168.11.10"
    docker.vm.hostname = "docker"
    docker.vm.synced_folder ".", "/home/vagrant/sync", type: "rsync"
    docker.vm.provider "virtualbox" do |vb|
      vb.memory = 2048
      vb.cpus = 2
    end
    docker.vm.provision :shell, :path => "docker.sh"
  end
end