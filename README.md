[![Agile611](https://www.agile611.com/wp-content/uploads/2020/09/cropped-logo-header.png)](http://www.agile611.com/)

# Agile611 Ansible Training

This repository contains the code examples from the configuration management tools Ansible. It uses Vagrant to demonstrate these tools in practice.

## Requirements

For Ansible, it is necessary to install [Ansible](http://docs.ansible.com/ansible/intro_installation.html) on the host machine. This repo uses a Vagrant box based on Ubuntu and we will use APT to install ansible.

## Example code

Clone this repository with:

```shell
git clone https://www.github.com/agile611/startusingansible.git
```

## Initial configuration

* Start environment, we are going to need 4 ubuntu boxes (Ansible, Alfa, Bravo, Charlie)

```shell
vagrant up 
vagrant ssh ansible
```

* Starting workspace on ansible box

```shell
vagrant@ansible$ sudo apt-get update
vagrant@ansible$ sudo apt-get install ansible -y
```

* Check your ansible installation checking the response from this command:

```shell
vagrant@ansible$ ansible localhost -m setup
```

* Create a ssh key to connect to the webserver box just pressing enter to the requested questions:

```shell
vagrant@ansible$ ssh-keygen
vagrant@ansible$ cat /home/vagrant/.ssh/id_rsa.pub
```

* Copy /home/vagrant/.ssh/id_rsa.pub into the clipboard on webserver box and execute:

```shell
vagrant@alfa$ sudo -s
root@alfa# mkdir /root/.ssh
root@alfa# echo 'full contents of id_rsa.pub from ansible node' > /root/.ssh/authorized_keys
root@alfa# chmod 700 /root/.ssh
root@alfa# chmod 640 /root/.ssh/authorized_keys
```

* Check if you can connect to the webserver using the ssh key (not prompting a password). 

```shell
vagrant@ansible$ ssh root@192.168.0.2
```

If you can connect, the initial config is done. Repeat this for Bravo and Charlie Vms.

### IMPORTANT NOTE
Priority order from the config files:
* ANSIBLE_CONFIG (environment variable POSIX)
* ansible.cfg (current folder)
* ~/.ansible.cfg (user home from the executor)
* /etc/ansible/ansible.cfg (general file)

## Test the environment

* Setup Ansible Inventory on the ansible box, create the following folders:

```shell
vagrant@ansible$ mkdir example_ansible
vagrant@ansible$ mkdir example_ansible/hosts
vagrant@ansible$ nano example_ansible/hosts/all
```

And on the file `hosts/all` and the following lines:

```ini
[all:vars]
ansible_python_interpreter=/usr/bin/python3.12

[database]
192.168.11.20

[loadbalancer]
192.168.11.30

[webserver]
192.168.11.40
```

* Check if everything works executing the following command:

```shell
vagrant@ansible$ cd example_ansible
vagrant@ansible$ ansible -i hosts -u root -m ping all
```

* What happen?

The expected response is as follows:

```shell
192.168.0.2 | SUCCESS => {
    "changed": false, 
    "ping": "pong"
}
```

## Initial configuration and first yaml file

* Create the file `request.yml`

```yaml
---
- hosts: webserver

  tasks:
    - name: What system are you?
      command: uname -a
      register: info

    - name: print var
      debug: var=info

    - name: print field
      debug: var=info.stdout

    - name: What your name?
      command: hostname
      register: info

    - name: Give me your name
      debug: var=info.stdout
```

* Execute the following command to show what tasks are we going to execute:

```shell

vagrant@ansible$ ansible-playbook -i hosts/all -u root request.yml --list-hosts --list-tasks
```

* Execute the following command to perform the tasks described before:

```shell
vagrant@ansible$ ansible-playbook -i hosts/all -u root request.yml
```

### IMPORTANT NOTE

The user root is used here for testing purposes and to make the environment easier to implement. Note that it is also the user which has the ssh key installed. You can add the ssh key to the user you in order to execute Ansible commands.

### More examples (on examples folder)

* 000_initial_examples
* 001_apt
* 002_become
* 003_with_items
* 004_services
* 005_stack_restart
* 006_notify_handlers
* 007_files_copy
* 008_pip
* 009_files
* 010_templates
* 011_lineinfile
* 012_mysql_management
* 013_wait_for
* 014_stack_status
* 015_roles
* 016_tasks_handlers
* 017_files_templates
* 018_site_yml
* 019_facts
* 020_defaults
* 021_vars
* 022_with_dict
* 023_selective_removal
* 024_continued
* 025_vars_files_group_vars
* 026_vault

## Problems provisioning the box

If you have problems provisioning the box, you can download it directly from [here](https://app.vagrantup.com/bento/boxes/ubuntu-20.04/versions/202112.19.0/providers/virtualbox.box)

After that you need to know the path of the box and execute the following command:

```shell
    vagrant box add /The/Path/From/Your/Downloaded/box/bento-ubuntu-20-04.box --name bento/ubuntu-20.04
    vagrant init bento/ubuntu-20.04
```

The init command creates a VagrantFile with your initial configuration. On the same folder where this Vagrantfile is, please execute to following command:

```shell
    vagrant up
```

After that, please connect to the box using the following command:

```shell
    vagrant ssh
```

If you get a terminal from the box, your environment is ready.

## Common networking problems

If you have proxies or VPNs running on your machine, it is possible that Vagrant is not able to provision your environment.

Please check your connectivity before.

## Support

This tutorial is released into the public domain by [Agile611](http://www.agile611.com/) under Creative Commons Attribution-NonCommercial 4.0 International.

[![License: CC BY-NC 4.0](https://img.shields.io/badge/License-CC_BY--NC_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-nc/4.0/)


This README file was originally written by [Guillem Hernández Sola](https://www.linkedin.com/in/guillemhs/) and is likewise released into the public domain.

Please contact Agile611 for further details.

* [Agile611](http://www.agile611.com/)
* Laureà Miró 309
* 08950 Esplugues de Llobregat (Barcelona)
