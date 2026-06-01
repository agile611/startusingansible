# Script to install Ansible on a Ubuntu system
apt-get update
# Add Ansible repository and install Ansible
apt-get install ansible net-tools -y
# Add vagrant user to sudoers
echo "vagrant ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/vagrant