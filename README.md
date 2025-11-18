[![Agile611](https://www.agile611.com/wp-content/uploads/2020/09/cropped-logo-header.png)](http://www.agile611.com/)

# Agile611 Ansible Training

This repository contains the code examples from the configuration management tools Ansible. It uses Vagrant to demonstrate these tools in practice.


## Requirements
- **git**: Necessary to clone the code.
- **Vagrant**: This repository uses a Vagrant box based on Ubuntu, and APT will be used to install Ansible.
- **Virtualbox**: It is the engine for virtualize the environment.

## Example Code

Clone the repository:

```bash
git clone https://www.github.com/agile611/startusingansible.git
```

### Initial Configuration

Start the environment, requiring four Ubuntu boxes (Ansible, Loadbalancer, Database, Webserver):

```bash
vagrant up
vagrant ssh ansible
```
Create an SSH key to connect the VMs without password:

```bash
ssh-keygen
cat /home/vagrant/.ssh/id_rsa.pub
```

Copy the public key to the VMs and set up the authorized keys:

```bash
vagrant@ansible$ ssh-copy-id vagrant@192.168.11.20
vagrant@ansible$ ssh-copy-id vagrant@192.168.11.30
vagrant@ansible$ ssh-copy-id vagrant@192.168.11.40
```

Verify SSH connection:

```bash
ssh vagrant@192.168.11.20
```

If any password is asked, the user is vagrant and the password is vagrant.

### Important Note

The configuration file priority order is as follows:

1. **ANSIBLE_CONFIG** (environment variable)
2. **ansible.cfg** (current folder)
3. **~/.ansible.cfg** (user home)
4. **/etc/ansible/ansible.cfg** (general file)

## Test the Environment

Set up Ansible Inventory on the Ansible box:

```bash
mkdir example_ansible
mkdir example_ansible/hosts
nano example_ansible/hosts/all
```

Add the following lines to `hosts/all`:

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

Check if everything works:

```bash
cd example_ansible
ansible -i hosts -u root -m ping all
```

### Initial Configuration and First YAML File

Create the file `request.yml`:

```yaml
---
- hosts: webserver
  tasks:
    - name: What system are you?
      command: uname -a
      register: info
    - name: print var
      debug:
        var: info
    - name: print field
      debug:
        var: info.stdout
    - name: What your name?
      command: hostname
      register: info
    - name: Give me your name
      debug:
        var: info.stdout
```

Execute the playbook:

```bash
ansible-playbook -i hosts/all -u root request.yml --list-hosts --list-tasks
ansible-playbook -i hosts/all -u root request.yml
```

### Additional Examples

Various examples are available in the `examples` folder, covering different aspects of Ansible usage.

## Troubleshooting

If you encounter issues provisioning the box, you can download it directly and add it to Vagrant.

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
