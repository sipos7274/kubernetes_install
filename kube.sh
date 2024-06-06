#!/bin/bash

if [ `id -u` -ne 0 ]
  then echo "Please run this script as root"
  exit
fi

# --------------------------------------------------------------------------------------------------------------------------------------------------------------------
#	Install required packages
# --------------------------------------------------------------------------------------------------------------------------------------------------------------------

apt update
apt install apt-transport-https gnupg2 bash-completion ca-certificates curl git wget gpg software-properties-common -y

# Hostname res:

echo "127.0.0.1" $(hostname) >> /etc/hosts
echo $(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}') $(hostname) >> /etc/hosts

# --------------------------------------------------------------------------------------------------------------------------------------------------------------------
#	Kubernetes installation
# --------------------------------------------------------------------------------------------------------------------------------------------------------------------

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet

# --------------------------------------------------------------------------------------------------------------------------------------------------------------------
#	Kubernetes setup configuration
# --------------------------------------------------------------------------------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------
# Disable swap
#-------------------------------------------------------------------------

swapoff -a
sed -i '/swap/s/^/#/' /etc/fstab
systemctl daemon-reload
mount -a

#-------------------------------------------------------------------------
# Enable the required Kernel modules
#-------------------------------------------------------------------------

tee /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system

#-------------------------------------------------------------------------
# Configure CRI
#-------------------------------------------------------------------------

curl -fsSL https://pkgs.k8s.io/addons:/cri-o:/prerelease:/main/deb/Release.key| gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://pkgs.k8s.io/addons:/cri-o:/prerelease:/main/deb/ /"| tee /etc/apt/sources.list.d/cri-o.list
apt update
apt install cri-o
systemctl enable --now crio

#-------------------------------------------------------------------------
# For control plane
#-------------------------------------------------------------------------

# Set the timeout value (30 seconds)
TIMEOUT=30

# Ask the user a question
read -t $TIMEOUT -p "That was a Worker node (1) or a Control-plane (2)? (Worker node/Control-Plane): " ANS

# Check if the user answered within the timeout period
if [ $? -eq 126 ]; then
  echo "That means it was a worker node. Successfully Done. Exiting."
  exit 1
fi

# Check the user's answer
case "$ANS" in
  "1") exit 0 ;;
  "2")
  
	kubeadm init
	sleep 2
	mkdir -p $HOME/.kube && cp -rpfi /etc/kubernetes/admin.conf $HOME/.kube/config && chown $(id -u):$(id -g) $HOME/.kube/config
	wget https://raw.githubusercontent.com/projectcalico/calico/master/manifests/calico.yaml && kubectl apply -f calico.yaml
 	kubectl apply -f https://projectcontour.io/quickstart/contour.yaml
	sleep 2
	kubeadm token create --print-join-command
	echo "Successfully Done"
	
     ;;
   *) echo "That means it was a worker node. Successfully Done. Exiting." && exit 1 ;;
esac

# --------------------------------------------------------------------------------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------
# Additional command helps
#-------------------------------------------------------------------------

# Create kube environment
# mkdir -p $HOME/.kube && cp -rpfi /etc/kubernetes/admin.conf $HOME/.kube/config && chown $(id -u):$(id -g) $HOME/.kube/config

# Install Calico networking
# wget https://raw.githubusercontent.com/projectcalico/calico/master/manifests/calico.yaml && kubectl apply -f calico.yaml

# Print join command to the cluster
# kubeadm token create --print-join-command

# Rename nodes
# kubectl label node worker1 node-role.kubernetes.io/worker=worker

# Install Contour ingress controller
# kubectl apply -f https://projectcontour.io/quickstart/contour.yaml
