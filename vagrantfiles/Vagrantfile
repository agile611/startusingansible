# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|

  config.vm.boot_timeout = 900

  # ─── ANSIBLE ───────────────────────────────────────────
  config.vm.define "ansible" do |ansible|
    ansible.vm.box      = "bento/ubuntu-24.04"
    ansible.vm.hostname = "ansible"
    ansible.vm.network "private_network", ip: "192.168.11.10"
    ansible.vm.synced_folder ".", "/vagrant", type: "rsync"

    ansible.vm.provider :libvirt do |v|
      v.driver        = "qemu"
      v.memory        = 512
      v.cpus          = 1
      v.graphics_type = "spice"
      v.cpu_mode      = "custom"
      v.cpu_model     = "qemu64"
    end
  end

  # ─── DATABASE ──────────────────────────────────────────
  config.vm.define "database" do |database|
    database.vm.box      = "bento/ubuntu-24.04"
    database.vm.hostname = "database"
    database.vm.network "private_network", ip: "192.168.11.11"
    database.vm.synced_folder ".", "/vagrant", type: "rsync"

    database.vm.provider :libvirt do |v|
      v.driver        = "qemu"
      v.memory        = 512
      v.cpus          = 1
      v.graphics_type = "spice"
      v.cpu_mode      = "custom"
      v.cpu_model     = "qemu64"
    end
  end

  # ─── LOADBALANCER ──────────────────────────────────────
  config.vm.define "loadbalancer" do |loadbalancer|
    loadbalancer.vm.box      = "bento/ubuntu-24.04"
    loadbalancer.vm.hostname = "loadbalancer"
    loadbalancer.vm.network "private_network", ip: "192.168.11.12"
    loadbalancer.vm.synced_folder ".", "/vagrant", type: "rsync"

    loadbalancer.vm.provider :libvirt do |v|
      v.driver        = "qemu"
      v.memory        = 512
      v.cpus          = 1
      v.graphics_type = "spice"
      v.cpu_mode      = "custom"
      v.cpu_model     = "qemu64"
    end
  end

  # ─── WEBSERVER ─────────────────────────────────────────
  config.vm.define "webserver" do |webserver|
    webserver.vm.box      = "bento/ubuntu-24.04"
    webserver.vm.hostname = "webserver"
    webserver.vm.network "private_network", ip: "192.168.11.13"
    webserver.vm.synced_folder ".", "/vagrant", type: "rsync"

    webserver.vm.provider :libvirt do |v|
      v.driver        = "qemu"
      v.memory        = 512
      v.cpus          = 1
      v.graphics_type = "spice"
      v.cpu_mode      = "custom"
      v.cpu_model     = "qemu64"
    end
  end

end