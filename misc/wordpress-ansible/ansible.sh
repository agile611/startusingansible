# Script to install Ansible on a Ubuntu system
apt-get update
# Install required packages
apt install software-properties-common -y   
# Add Ansible PPA and install Ansible
apt-add-repository ppa:ansible/ansible
apt-get install ansible net-tools -y
# Add vagrant user to sudoers
echo "vagrant ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/vagrant