# Kubernetes Automated Installer for Ubuntu/Debian

A hardened, fully automated Bash script for provisioning **Kubernetes control-plane and worker nodes** on Ubuntu or Debian-based systems.  
Tested and verified on **Debian 12**, with built-in support for **CRI-O**, **Calico networking**, and the **Contour ingress controller**.

---

## 🧩 Overview

This script automates the complete setup of a Kubernetes cluster — including kernel configuration, container runtime installation, system prerequisites, and optional control-plane initialization.

It supports both **control-plane** and **worker** node roles:
- When run on any node, it installs all dependencies and prepares the system.
- At the end, you’ll be prompted to select whether the node is a **Control-plane** or a **Worker**.
- If no input is provided within the timeout window, the script safely assumes a **Worker** role and exits.

---

## ⚙️ Features

- **Automatic Kubernetes installation** — dynamically detects and installs the latest stable release.
- **CRI-O container runtime** setup with secure key handling.
- **Calico CNI** network plugin installation for pod networking.
- **Contour ingress controller** deployment for load balancing.
- **Kernel and sysctl configuration** for Kubernetes networking.
- **Swap disablement and validation** for kubelet compatibility.
- **Idempotent and fault-tolerant** — safe to re-run without side effects.
- **Automatic repository key updates** — resilient against key rotations or version changes.

---

## 🧱 Requirements

- **Operating System:** Debian 12 or Ubuntu 22.04+ (root privileges required)
- **Internet Connectivity:** Required to fetch repositories, keys, and manifests.
- **Hardware:** Minimum 2 GB RAM and 2 vCPUs per node recommended.

> ⚠️ This script is **not intended for restricted or air-gapped environments** since it downloads packages and manifests from official sources at runtime.

---

## 🚀 Usage

1. Clone this repository:
   ```bash
   git clone https://github.com/sipos7274/kubernetes_install.git
   cd kubernetes_install/
   chmod +x kube.sh
   ./kube.sh
   
## 🧭 When Prompted

- Enter 2 for a Control-plane node
- → The script will initialize the Kubernetes cluster, configure Calico networking, and deploy the Contour ingress controller automatically.

- Enter 1 (or press Enter / wait for timeout) for a Worker node
- → The script will complete the preparation steps and then stop.

- After Control-plane initialization
- → Copy the kubeadm join command printed by the Control-plane setup and execute it on each Worker node to join the cluster.
