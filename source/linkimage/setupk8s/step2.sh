##
## setup k8s cluster need two steps on each host:
##     step1 [reboot] step2
## step1 will install all necessary dependency
## step2 will start k8s cluster
##

##  this is the second step
##  [NOTICE] HOST1 is the first setup host, HOST2 and HOST3 are the host setup later.
## usage: bash ./k8s_step2.sh JOINWORKER TOKEN CA_HASH
## usage: bash ./k8s_step2.sh JOINMASTER TOKEN CA_HASH  CERT_KEY
## usage: bash ./k8s_step2.sh RESET
## eg:
##   bash ./k8s_step2.sh SETUPMASTER
##   bash ./k8s_step2.sh JOINWORKER 0txofw.2drqz5j5ubl5lfl9 sha256:457d0787f9035814e69fc53d7a4671de5177f03aedf406bc74010f03c1cc939f
##   bash ./k8s_step2.sh JOINMASTER 0txofw.2drqz5j5ubl5lfl9 sha256:457d0787f9035814e69fc53d7a4671de5177f03aedf406bc74010f03c1cc939f eba1b678a656fdbe524530a1ed6d4f7567f078902e490d649f98a28d8e0e719c 

# set -x

HOST1=192.168.3.151
HOST2=192.168.3.152
HOST3=192.168.3.153
DOMAIN=jinqidiguo.com
POD_CIDR=10.244.0.0/16
SERVICE_CIDR=10.20.0.0/16

if [ $1 = "SETUPMASTER" ]; then
    echo "[setup master host...]"

    if [ `grep -c "$DOMAIN" /etc/hosts` -eq '0' ]; then
      # add host mapping
      echo "$HOST1 k8s1" | sudo tee -a /etc/hosts
      echo "$HOST2 k8s2" | sudo tee -a /etc/hosts
      echo "$HOST3 k8s3" | sudo tee -a /etc/hosts
      echo "$HOST1 $DOMAIN" | sudo tee -a /etc/hosts
    fi

    PAUSE_VERSION=`kubeadm config images list | grep pause | cut -d ':' -f 2`
    sudo ctr --namespace k8s.io image pull registry.aliyuncs.com/google_containers/pause:$PAUSE_VERSION
    sudo ctr --namespace k8s.io image tag registry.aliyuncs.com/google_containers/pause:$PAUSE_VERSION k8s.gcr.io/pause:$PAUSE_VERSION

    sudo kubeadm init \
            --apiserver-advertise-address $HOST1 \
            --apiserver-bind-port 6443 \
            --cert-dir /etc/kubernetes/pki \
            --control-plane-endpoint $DOMAIN \
            --pod-network-cidr $POD_CIDR \
            --service-cidr $SERVICE_CIDR \
            --service-dns-domain cluster.local \
            --cri-socket /run/containerd/containerd.sock \
            --image-repository registry.cn-hangzhou.aliyuncs.com/google_containers \
            --upload-certs \
            --v 9

    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config


    echo "[if install weave:]"
    echo "kubectl apply -f \"https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')&env.IPALLOC_RANGE=$POD_CIDR\""


fi

if [ $1 = "JOINWORKER" ]; then
    echo "[setup worker host...]"
    
    if [ `grep -c "$DOMAIN" /etc/hosts` -eq '0' ]; then
      # add host mapping
      echo "$HOST1 k8s1" | sudo tee -a /etc/hosts
      echo "$HOST2 k8s2" | sudo tee -a /etc/hosts
      echo "$HOST3 k8s3" | sudo tee -a /etc/hosts
      echo "$HOST1 $DOMAIN" | sudo tee -a /etc/hosts
    fi

    PAUSE_VERSION=`kubeadm config images list | grep pause | cut -d ':' -f 2`
    sudo ctr --namespace k8s.io image pull registry.aliyuncs.com/google_containers/pause:$PAUSE_VERSION
    sudo ctr --namespace k8s.io image tag registry.aliyuncs.com/google_containers/pause:$PAUSE_VERSION k8s.gcr.io/pause:$PAUSE_VERSION
    
    # not pass image-repository and cri-socket is still ok
    sudo kubeadm join $DOMAIN:6443   \
            --token $2 \
            --discovery-token-ca-cert-hash $3
fi

if [ $1 = "JOINMASTER" ]; then
    echo "[setup other master host...]"
    
    if [ `grep -c "$DOMAIN" /etc/hosts` -eq '0' ]; then
      # add host mapping
      echo "$HOST1 k8s1" | sudo tee -a /etc/hosts
      echo "$HOST2 k8s2" | sudo tee -a /etc/hosts
      echo "$HOST3 k8s3" | sudo tee -a /etc/hosts
      echo "$HOST1 $DOMAIN" | sudo tee -a /etc/hosts
    fi

    PAUSE_VERSION=`kubeadm config images list | grep pause | cut -d ':' -f 2`
    sudo ctr --namespace k8s.io image pull registry.aliyuncs.com/google_containers/pause:$PAUSE_VERSION
    sudo ctr --namespace k8s.io image tag registry.aliyuncs.com/google_containers/pause:$PAUSE_VERSION k8s.gcr.io/pause:$PAUSE_VERSION    
    
    # not pass image-repository and cri-socket is still ok
    sudo kubeadm join $DOMAIN:6443   \
            --token $2 \
            --discovery-token-ca-cert-hash $3 \
            --control-plane --certificate-key $4
   
fi

if [ $1 = "RESET" ]; then
  sudo kubeadm reset
  sudo rm -rf /etc/cni/net.d
  sudo rm -rf $HOME/.kube/config
fi