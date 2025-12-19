#!/usr/bin/env bash
# --------------------------------------------------------------------------
#  Hardened Kubernetes + CRI-O setup for RHEL-based systems
# --------------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

# === ROOT CHECK =============================================================
if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: run this script as root." >&2
  exit 1
fi

# === CONFIGURATION ==========================================================
K8S_BASE_URL="https://pkgs.k8s.io/core:/stable:/"
CRIO_BASE_URL="https://pkgs.k8s.io/addons:/cri-o:/prerelease:/main/rpm/"
CALICO_MANIFEST="https://raw.githubusercontent.com/projectcalico/calico/master/manifests/calico.yaml"
CONTOUR_MANIFEST="https://projectcontour.io/quickstart/contour.yaml"

FALLBACK_K8S_VERSION="v1.30"
TIMEOUT=30

# === LOGGING ================================================================
log()   { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || error "Missing required command: $1"
}

# === REQUIREMENTS ===========================================================
for cmd in curl awk tee systemctl ip modprobe dnf; do
  require "$cmd"
done

log "Updating system and installing prerequisites..."
dnf -y install \
  curl wget bash-completion ca-certificates \
  gnupg2 jq tar \
  device-mapper-persistent-data \
  lvm2 iproute-tc

# === HOSTS SETUP ============================================================
log "Updating /etc/hosts..."
IP_ADDR=$(ip route get 8.8.8.8 | awk '/src/ {print $7; exit}')
grep -q "$(hostname)" /etc/hosts || echo "127.0.0.1 $(hostname)" >> /etc/hosts
grep -q "$IP_ADDR" /etc/hosts || echo "$IP_ADDR $(hostname)" >> /etc/hosts

# === DISABLE SWAP ===========================================================
log "Disabling swap..."
swapoff -a || true
sed -i '/swap/d' /etc/fstab

# === KERNEL MODULES =========================================================
log "Loading kernel modules..."
cat >/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# === SYSCTL SETTINGS ========================================================
log "Applying sysctl parameters..."
cat >/etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                = 1
EOF

sysctl --system

# === FIREWALL ===============================================================
log "Configuring firewall..."
systemctl enable --now firewalld
firewall-cmd --add-masquerade --permanent
firewall-cmd --add-port=6443/tcp
firewall-cmd --add-port=6443/tcp --permanent
firewall-cmd --add-port=10250/tcp
firewall-cmd --add-port=10250/tcp --permanent
firewall-cmd --reload

# === SELINUX ================================================================
log "Ensuring SELinux compatibility..."
setenforce 1 || true

# === REMOVE DOCKER ==========================================================
log "Removing Docker if present..."
dnf -y remove docker docker-client docker-client-latest \
  docker-common docker-latest docker-latest-logrotate \
  docker-logrotate docker-engine containerd runc || true

# === DETECT KUBERNETES VERSION ==============================================
log "Detecting latest Kubernetes version..."
LATEST_K8S_VERSION=$(curl -fsSL "$K8S_BASE_URL" | \
  grep -Eo 'v[0-9]+\.[0-9]+' | sort -V | tail -n1 || echo "$FALLBACK_K8S_VERSION")
log "Using Kubernetes version: $LATEST_K8S_VERSION"

# === KUBERNETES REPO ========================================================
log "Configuring Kubernetes repository..."
cat >/etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=${K8S_BASE_URL}${LATEST_K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=${K8S_BASE_URL}${LATEST_K8S_VERSION}/rpm/repodata/repomd.xml.key
EOF

dnf clean all
dnf makecache

dnf -y install kubelet kubeadm kubectl
systemctl enable --now kubelet

# === CRI-O REPO =============================================================
log "Configuring CRI-O repository..."
cat >/etc/yum.repos.d/crio.repo <<EOF
[cri-o]
name=CRI-O
baseurl=${CRIO_BASE_URL}
enabled=1
gpgcheck=1
gpgkey=${CRIO_BASE_URL}repodata/repomd.xml.key
EOF

dnf clean all
dnf makecache

dnf -y install cri-o cri-tools
systemctl enable --now crio

# === ROLE SELECTION =========================================================
log "Select node role..."
read -t "$TIMEOUT" -p "Worker (1) or Control-plane (2)? Default Worker in ${TIMEOUT}s: " ROLE || true

if [[ -z "${ROLE:-}" || "$ROLE" == "1" ]]; then
  log "Worker node configured."
  exit 0
fi

# === CONTROL PLANE ==========================================================
log "Initializing Control-plane..."
kubeadm init --pod-network-cidr=192.168.0.0/16 --cri-socket=unix:///var/run/crio/crio.sock

mkdir -p "$HOME/.kube"
cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
chown "$(id -u)":"$(id -g)" "$HOME/.kube/config"

log "Deploying Calico..."
kubectl apply -f "$CALICO_MANIFEST"

log "Deploying Contour..."
kubectl apply -f "$CONTOUR_MANIFEST"

log "Cluster join command:"
kubeadm token create --print-join-command

log "Control-plane setup complete."
