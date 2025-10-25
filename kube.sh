#!/usr/bin/env bash
# --------------------------------------------------------------------------
#     Bulletproof setup for Kubernetes + CRI-O with Calico and Contour
# --------------------------------------------------------------------------

set -euo pipefail

# Fail if not root
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: this script must be run as root. Use 'sudo' or run as root." >&2
  exit 1
fi

IFS=$'\n\t'

# === CONFIGURATION ==========================================================
KEYRING_DIR="/etc/apt/keyrings"
mkdir -p "$KEYRING_DIR"

K8S_BASE_URL="https://pkgs.k8s.io/core:/stable:/"
CRIO_URL="https://pkgs.k8s.io/addons:/cri-o:/prerelease:/main/deb/"
CALICO_MANIFEST="https://raw.githubusercontent.com/projectcalico/calico/master/manifests/calico.yaml"
CONTOUR_MANIFEST="https://projectcontour.io/quickstart/contour.yaml"

FALLBACK_K8S_VERSION="v1.30"
TIMEOUT=30

# === UTILITY FUNCTIONS ======================================================
log() { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || error "Missing required command: $1"
}

# === ROOT CHECK =============================================================
if [[ $EUID -ne 0 ]]; then
  error "Please run this script as root."
fi

# === REQUIREMENTS ===========================================================
for cmd in curl gpg tee awk systemctl ip modprobe; do
  require "$cmd"
done

log "Updating base system and installing prerequisites..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -qq
apt-get install -y -qq apt-transport-https gnupg2 bash-completion ca-certificates curl git wget gpg software-properties-common

# === HOSTS SETUP ============================================================
log "Updating /etc/hosts..."
{
  grep -q "$(hostname)" /etc/hosts || echo "127.0.0.1 $(hostname)"
  IP_ADDR=$(ip route get 8.8.8.8 | awk '/src/ {print $7; exit}')
  grep -q "$IP_ADDR" /etc/hosts || echo "$IP_ADDR $(hostname)"
} >> /etc/hosts

# === DETECT LATEST KUBERNETES VERSION =======================================
log "Detecting latest Kubernetes stable version..."
LATEST_K8S_VERSION=$(curl -fsSL "$K8S_BASE_URL" 2>/dev/null | grep -Eo 'v[0-9]+\.[0-9]+' | sort -V | tail -n1 || echo "$FALLBACK_K8S_VERSION")
log "Using Kubernetes version: $LATEST_K8S_VERSION"

# === KUBERNETES REPOSITORY SETUP ============================================
log "Configuring Kubernetes APT repository..."
K8S_KEY_URL="${K8S_BASE_URL}${LATEST_K8S_VERSION}/deb/Release.key"
curl -fsSL "$K8S_KEY_URL" | gpg --dearmor -o "${KEYRING_DIR}/kubernetes-apt-keyring.gpg"
echo "deb [signed-by=${KEYRING_DIR}/kubernetes-apt-keyring.gpg] ${K8S_BASE_URL}${LATEST_K8S_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

apt-get update -y -qq
log "Installing kubelet, kubeadm, kubectl..."
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet

# === KUBERNETES SYSTEM PREP ================================================
log "Disabling swap..."
swapoff -a || true
sed -i.bak '/swap/s/^/#/' /etc/fstab || true
systemctl daemon-reexec
systemctl daemon-reload
mount -a

log "Loading kernel modules..."
cat >/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

log "Configuring sysctl parameters for Kubernetes..."
cat >/etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system >/dev/null

# === CRI-O SETUP ============================================================
log "Setting up CRI-O repository..."
CRIO_KEY="${KEYRING_DIR}/cri-o-apt-keyring.gpg"
curl -fsSL "${CRIO_URL}Release.key" | gpg --dearmor -o "$CRIO_KEY"
echo "deb [signed-by=$CRIO_KEY] $CRIO_URL /" | tee /etc/apt/sources.list.d/cri-o.list >/dev/null
apt-get update -y -qq
log "Installing CRI-O..."
apt-get install -y cri-o
systemctl enable --now crio

# === ROLE SELECTION =========================================================
log "Determining node role (Control-plane or Worker)..."
read -t "$TIMEOUT" -p "Is this a Worker node (1) or Control-plane (2)? Default is Worker after ${TIMEOUT}s: " ROLE || true

if [[ -z "${ROLE:-}" || "$ROLE" == "1" ]]; then
  log "Configured as Worker node. Setup complete."
  exit 0
fi

if [[ "$ROLE" == "2" ]]; then
  log "Initializing Control-plane..."
  kubeadm init --pod-network-cidr=192.168.0.0/16

  mkdir -p "$HOME/.kube"
  cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
  chown "$(id -u)":"$(id -g)" "$HOME/.kube/config"

  log "Applying Calico networking..."
  wget -q "$CALICO_MANIFEST" -O calico.yaml
  kubectl apply -f calico.yaml

  log "Deploying Contour ingress controller..."
  kubectl apply -f "$CONTOUR_MANIFEST"

  sleep 2
  log "Cluster join command:"
  kubeadm token create --print-join-command
  log "Control-plane setup complete."
else
  warn "Invalid input. Defaulting to Worker node. Setup complete."
fi

#-------------------------------------------------------------------------
# Additional command helps
#-------------------------------------------------------------------------

# echo "192.168.126.100 control" >> /etc/hosts && echo "127.0.0.1 control" >> /etc/hosts
# mkdir -p $HOME/.kube && cp -rpfi /etc/kubernetes/admin.conf $HOME/.kube/config && chown $(id -u):$(id -g) $HOME/.kube/config
# kubeadm init --apiserver-advertise-address=192.168.126.100 --pod-network-cidr=10.10.0.0/16 --cri-socket=unix://var/run/crio/crio.sock
# wget https://raw.githubusercontent.com/projectcalico/calico/master/manifests/calico.yaml && kubectl apply -f calico.yaml
# kubeadm token create --print-join-command
