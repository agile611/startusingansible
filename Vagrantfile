# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|

  # Timeout generós per QEMU sense KVM (TCG)
  config.vm.boot_timeout = 900

  # Desactiva la sincronització de carpetes per defecte
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # ─── ANSIBLE ───────────────────────────────────────────
  config.vm.define "ansible" do |ansible|
    ansible.vm.box      = "generic/debian12"
    ansible.vm.hostname = "ansible"

    ansible.vm.provider "libvirt" do |libvirt|
      libvirt.driver       = "qemu"
      libvirt.cpu_mode     = "custom"
      libvirt.cpu_model    = "qemu64"
      libvirt.memory       = 512
      libvirt.cpus         = 1
      libvirt.graphics_type = "none"
      libvirt.video_type    = "none"
      libvirt.management_network_name    = "vagrant-libvirt"
      libvirt.management_network_address = "192.168.121.0/24"
    end
  end

  # ─── DATABASE ──────────────────────────────────────────
  config.vm.define "database" do |database|
    database.vm.box      = "generic/debian12"
    database.vm.hostname = "database"

    database.vm.provider "libvirt" do |libvirt|
      libvirt.driver       = "qemu"
      libvirt.cpu_mode     = "custom"
      libvirt.cpu_model    = "qemu64"
      libvirt.memory       = 512
      libvirt.cpus         = 1
      libvirt.graphics_type = "none"
      libvirt.video_type    = "none"
      libvirt.management_network_name    = "vagrant-libvirt"
      libvirt.management_network_address = "192.168.121.0/24"
    end
  end

  # ─── LOADBALANCER ──────────────────────────────────────
  config.vm.define "loadbalancer" do |loadbalancer|
    loadbalancer.vm.box      = "generic/debian12"
    loadbalancer.vm.hostname = "loadbalancer"

    loadbalancer.vm.provider "libvirt" do |libvirt|
      libvirt.driver       = "qemu"
      libvirt.cpu_mode     = "custom"
      libvirt.cpu_model    = "qemu64"
      libvirt.memory       = 512
      libvirt.cpus         = 1
      libvirt.graphics_type = "none"
      libvirt.video_type    = "none"
      libvirt.management_network_name    = "vagrant-libvirt"
      libvirt.management_network_address = "192.168.121.0/24"
    end
  end

  # ─── WEBSERVER ─────────────────────────────────────────
  config.vm.define "webserver" do |webserver|
    webserver.vm.box      = "generic/debian12"
    webserver.vm.hostname = "webserver"

    webserver.vm.provider "libvirt" do |libvirt|
      libvirt.driver       = "qemu"
      libvirt.cpu_mode     = "custom"
      libvirt.cpu_model    = "qemu64"
      libvirt.memory       = 512
      libvirt.cpus         = 1
      libvirt.graphics_type = "none"
      libvirt.video_type    = "none"
      libvirt.management_network_name    = "vagrant-libvirt"
      libvirt.management_network_address = "192.168.121.0/24"
    end
  end

end