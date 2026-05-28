# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|

  config.vm.boot_timeout = 900

  ['ansible', 'database', 'loadbalancer', 'webserver'].each do |name|
    config.vm.define name do |node|
      node.vm.box      = "bento/ubuntu-24.04"
      node.vm.hostname = name
      node.vm.synced_folder ".", "/vagrant", type: "rsync"

      node.vm.provider :libvirt do |v|
        v.driver        = "qemu"
        v.memory        = 512
        v.cpus          = 1
        v.graphics_type = "spice"
      end
    end
  end

end