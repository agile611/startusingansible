# Script to install Ansible on a Debian system
apt-get update
# Install required packages
apt install ansible net-tools -y
# Add vagrant user to sudoers
echo "vagrant ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/vagrant