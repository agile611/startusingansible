Vagrant.configure("2") do |config|

  config.vm.boot_timeout = 900

  # ─── CONTROL ───────────────────────────────────────────
  config.vm.define "control" do |control|
    control.vm.box      = "bento/debian-13" # Using Debian
    control.vm.hostname = "control"
    control.vm.network "private_network", ip: "192.168.11.10"
    control.vm.synced_folder ".", "/vagrant", type: "rsync"
    control.vm.provider "virtualbox" do |vb| # Changed to VirtualBox
      vb.memory        = 512
      vb.cpus          = 1
    end
  end

  # ─── DATABASE ──────────────────────────────────────────
  config.vm.define "database" do |database|
    database.vm.box      = "bento/debian-13" # Using Debian
    database.vm.hostname = "database"
    database.vm.network "private_network", ip: "192.168.11.20"
    database.vm.synced_folder ".", "/vagrant", type: "rsync"

    database.vm.provider "virtualbox" do |vb| # Changed to VirtualBox
      vb.memory        = 512
      vb.cpus          = 1
    end
  end

  # ─── LOADBALANCER ──────────────────────────────────────
  config.vm.define "loadbalancer" do |loadbalancer|
    loadbalancer.vm.box      = "bento/debian-13" # Using Debian
    loadbalancer.vm.hostname = "loadbalancer"
    loadbalancer.vm.network "private_network", ip: "192.168.11.30"
    loadbalancer.vm.synced_folder ".", "/vagrant", type: "rsync"

    loadbalancer.vm.provider "virtualbox" do |vb| # Changed to VirtualBox
      vb.memory        = 512
      vb.cpus          = 1
    end
  end

  # ─── WEBSERVER ─────────────────────────────────────────
  config.vm.define "webserver" do |webserver|
    webserver.vm.box      = "bento/debian-13" # Using Debian
    webserver.vm.hostname = "webserver"
    webserver.vm.network "private_network", ip: "192.168.11.40"
    webserver.vm.synced_folder ".", "/vagrant", type: "rsync"

    webserver.vm.provider "virtualbox" do |vb| # Changed to VirtualBox
      vb.memory        = 512
      vb.cpus          = 1
    end
  end

  # ─── AWX ───────────────────────────────────────────────
  config.vm.define "awx" do |awx|
    awx.vm.box      = "bento/ubuntu-26.04" # Using Debian
    awx.vm.network "private_network", ip: "192.168.11.50"
    awx.vm.hostname = "awx"
    awx.vm.network "forwarded_port", guest: 32000, host: 32000
    awx.vm.provision :shell, :path => "setup-awx.sh"
    awx.vm.provider "virtualbox" do |vb| # Changed to VirtualBox
      vb.memory = 16384
      vb.cpus = 4
    end
  end

end