This script intended to install kubernetes control-plane and worker-plane as well on ubuntu or debian systems.
I tested this script on Debian 12. You need to reach the internet to succesfully run this script so it's not fit for restricted network environment.

You need to run this script on every system that involved in the cluster (control and worker plane as well)
The script gonna install everything for you, after it's done gonna ask what kind of machine you runned the script worker or control plane.
If it's control plane the script is gonna initiate the cluster for you, but if it's a worker plane the script gonna stop, and if you're not gonna input anything the script assume that was a worker plane and gonna quit.

This script include installation of Calico networking and Contour ingress controller as well, and works with CRI-O Container Runtime Interface.
