##
## setup k8s cluster need two steps on each host:
##     step1 [reboot] step2
## step1 will install all necessary dependency
## step2 will start k8s cluster
##

## this is first step
## usage: ./k8s_step1.sh amd64|arm64

set -x
echo "[arch=$1]"

# add source
sudo apt update
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=$1 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# install containerd
sudo rm -f /etc/containerd/config.toml
sudo apt update
sudo apt install -y containerd  #containerd.io maybe

# init containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# set containerd Cgroup
# sed -i 's/systemd_cgroup = false/systemd_cgroup = true/g' /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

# add kubelet source
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg  https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# install dep
sudo apt update
sudo apt install -y kubectl=1.22.1-00
sudo apt install -y kubelet=1.22.1-00
sudo apt install -y kubeadm=1.22.1-00
sudo apt install -y socat
sudo apt install -y conntrack

# install kernel module
sudo apt install -y linux-modules-extra-raspi 
# or
# https://launchpad.net/ubuntu/+source/linux-raspi/
# wget https://launchpad.net/ubuntu/+archive/primary/+files/linux-modules-extra-5.13.0-1008-raspi_5.13.0-1008.9_arm64.deb
# dpkg -i linux-modules-extra-5.13.0-1008-raspi_5.13.0-1008.9_arm64.deb
modprobe veth
modprobe vxlan

# config kernel module
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system

echo "fs.inotify.max_user_instances=8192" | sudo tee -a /etc/sysctl.conf
echo "fs.inotify.max_user_watches=65535" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

cat <<EOF | sudo tee /etc/modules-load.d/crio.conf
overlay
br_netfilter
EOF

cat <<EOF | sudo tee /etc/modules
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
veth
vxlan
EOF

sudo sed -ri 's/.*swap.*/#&/' /etc/fstab

while true
do
    read -r -p "R U sure to reboot now ? [Y/N]"  input

    case $input in
        [yY][eE][sS] | [yY])
            echo "[reboot now]"
            sudo reboot
            exit 0
            ;;
        [nN][oO] | [nN])
            echo "[You can reboot later manually]"
            exit 0
            ;;
        *)
            echo "Invalid input"
            ;;
    esac
done