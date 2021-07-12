#!/bin/bash

# Jenkins
echo "================== START - Setting Up Jenkins ================== "
sudo apt install openjdk-8-jdk -y
wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io.key | sudo apt-key add -
sh -c 'echo deb https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list'
sudo apt-get update && sudo apt-get install jenkins -y
sudo service jenkins restart
sudo service jenkins status
echo "================== END - Setting Up Jenkins ================== "

# Docker
echo "================== START - Setting Up Docker ================== "
sudo apt-get install apt-transport-https ca-certificates curl software-properties-common -y
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-key fingerprint 0EBFCD88
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
sudo apt-get install docker-ce -y
echo "================== END - Setting Up Docker ================== "

# Azure CLI
# Reference: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt
# Use: Option 1: Install with one command
echo "================== START - Setting Up Azure CLI ================== "
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
echo "================== END - Setting Up Azure CLI ================== "

# Kubectl
echo "================== START - Setting Up Kubectl ================== "
# shellcheck disable=SC2164
cd /tmp/
sudo curl -kLO https://storage.googleapis.com/kubernetes-release/release/v1.8.0/bin/linux/amd64/kubectl
sudo chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl
echo "================== END - Setting Up Kubectl ================== "

# Configure access
echo -e "\n Waiting for System to  stabilize before making config changes......";sleep 240
echo "================== START - Setting Up access config ================== "
sudo usermod -aG docker jenkins
sudo usermod -aG docker charyulu
sudo touch /var/lib/jenkins/jenkins.install.InstallUtil.lastExecVersion
sudo service jenkins restart
sudo cp ~/.kube/config /var/lib/jenkins/.kube/
sudo chmod 777 /var/lib/jenkins/
sudo chmod 777 /var/lib/jenkins/config
echo "================== END - Setting Up access config ================== "
