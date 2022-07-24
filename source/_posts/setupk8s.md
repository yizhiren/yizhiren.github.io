---
title: 树莓派搭建k8s集群
tags:
  - kubernetes
categories:
  - 架构
date: 2022-01-25 17:34:46
updated: 2022-01-25 17:34:46
---

# 树莓派搭建k8s集群



## 简介

我们有很多时候需要搭建一个k8s集群，可能为了开发，可能为了测试，可能为了学习。在选择机器上可以有几个选择，一个是使用几台PC，一个是开几个虚拟机，一个是使用几个轻量的开发板。这里我主要以学习为目的，并且选择使用轻量开发板的方式，并且以最常用的树莓派作为代表，来搭建一个k8s集群。

由于主要以学习考试为主，这里暂时不考虑搭建单机集群的方式，因为没法接触到涉及多个节点的操作场景。

同时也不考虑k3s，我知道k3s是专为轻量设备而设计的，功能跟k8s基本是一样的，但是k3s和k8s只是功能基本相同，但是在使用和配置上，都有很多不同，并且使用的是完全分开的文档。k8s在使用上经常需要查在线文档的，即便对k3s的文档很熟悉了，在使用k8s的时候还是会存在查不到k8s文档的情况。因此学习k8s的时候，用k3s做练习是不合适的。

至于选择树莓派作为载体是个人选择，你可以选择使用pc或者选择使用虚拟机。如果你选择使用pc或者虚拟机，那么下面的章节中，【刷写系统】和【配置系统】会有差异，仅供参考。再之后的步骤则都是通用的。


最终我们将完成以下集群的搭建：

![cluster-device](/linkimage/setupk8s/cluster-device.png)

一个路由器，3个树莓派，树莓派通过wifi连接路由器，3个树莓派中一个master node,两个worker node。


<!-- more -->

## 刷写系统
系统我们使用树莓派专用的ubuntu系统，我的理由是k8s官方文档中插入的系统命令都是debian系的apt指令，外加ubuntu官方提供了树莓派的版本。所以可以看出ubuntu对k8s和对树莓派都是友好的。还有很多系统可以选择，更多选择可以阅读[这个页面](https://thenewstack.io/a-guide-to-linux-operating-systems-for-kubernetes/)详细了解  。但是后面的步骤我都是按照ubuntu来做的，其他系统的话需要自己做一些探索了。
首先把sd卡通过读卡器插到电脑上，然后到[烧录工具下载页面](https://ubuntu.com/tutorials/how-to-install-ubuntu-on-your-raspberry-pi#2-prepare-the-sd-card) 下载树莓派专用的烧录的软件，安装后，打开软件。
![cluster-device](/linkimage/setupk8s/pi-imager.png)
在【选择系统】的选择中，依次选择[Other general-purpose OS]，[ubuntu]，[Ubuntu Server 21.10 (RPi 3/4/400)]，在【sd卡】的选择中选中你的sd卡。然后点烧录就可以了。
如果你有自己的刷写软件，可以先下载[系统镜像](https://ubuntu.com/download/raspberry-pi/thank-you?version=21.10&architecture=server-arm64+raspi) ,随后通过你自己的刷写软件写到sd卡中就可以了。比如我的linux mint，只需要右键下载的镜像，选择”使用 磁盘映像写入器 打开“就可以打开磁盘工具的恢复磁盘映像功能来写入镜像,如下图。

![cluster-device](/linkimage/setupk8s/mint-open-writer.png)

![cluster-device](/linkimage/setupk8s/mint-write-image.png)

## 配置系统
这一步一个是要完成登录密码和ip地址和wifi密码的配置，以便我们能通过ssh连接上去。另一个是配置hostname，便于区别不同的设备。

在配置前，我们需要先设计一下我们3个树莓派的ip地址和hostname。
假设局域网的网段是192.168.3.0/24, 那么我们可以指定3个空闲的ip，比如192.168.3.151,192.168.3.152,192.168.3.153。然后hostname可以指定为master1，worker1，worker2。所以3个机器分别为:

| 机器信息 | hostname | ip |
| ------ | ------ | ------ |
| master node | server1 | 192.168.3.151 |
| worker node1 | server2 | 192.168.3.152 |
| worker node2 | server3 | 192.168.3.153 |

然后我们以master node为例来配置hostname和ip。
在sd卡刚刷写完后，sd卡实际上是被分成两个区的，其中有一个system-boot分区，是可编辑的。
我们把刷写完的sd卡重新插到电脑上，然后挂载system-boot分区。
linux mint上我们可以通过”磁盘“工具直接通过界面操作来挂载分区，如图：

![cluster-device](/linkimage/setupk8s/mint-mount-sd-ui.png)

也可以通过命令行，先fdisk -l查看设备信息，然后通过mount挂载就可以了，如图：

![cluster-device](/linkimage/setupk8s/mint-mount-sd-commandline.png)

如上图所以，挂载完后我们能看到分区下有一个network-config文件，这个文件是用来配置系统首次启动时候的网络的。初始内容如下：

![cluster-device](/linkimage/setupk8s/rpi-netplan-init.png)

我们根据我们网络和ip，改成如下：

![cluster-device](/linkimage/setupk8s/rpi-netplan-overwrite.png)

wifi名字/wifi密码根据实际的填写。我使用了dhcp的方式连接wifi，按照[官方文档](https://ubuntu.com/tutorials/how-to-install-ubuntu-on-your-raspberry-pi#3-wifi-or-ethernet)应该是可以直接配成静态ip的，但是我每次配成静态之后设备都无法连到wifi中，不知道原因，所以就先配成dhcp的。

改完配置文件，sd卡插到树莓派上去启动设备，这个时候我们登录到我们的路由器管理界面观察设备列表，找出hostname为ubuntu的设备，或者通过设备启动前和启动后的差别来找出设备的初始ip，然后我们通过ssh登录设备，初始用户名和密码都是ubuntu。登录后我们完成相应的配置：

```shell
ssh ubuntu@192.168.3.157  # 路由器管理界面找出来的设备初始ip
# 登录后自动强制让你设置新密码，改完后重新ssh上去

ssh ubuntu@192.168.3.157

cat <<EOF | sudo tee /etc/hostname
server1
EOF

cp /etc/netplan/50-cloud-init.yaml ./  # backup
sudo vi /etc/netplan/50-cloud-init.yaml 
# 把其中wifi下的配置改成如下
    wifis:
        wlan0:
            access-points:
                "xxxxx":
                    password: "yyyyy"
            optional: true
            gateway4: 192.168.3.1
            nameservers:
                addresses: [192.168.3.1, 8.8.8.8]
            addresses: [192.168.3.151/24]

sudo reboot # 重启生效
ssh ubuntu@192.168.3.151 # 用新的ip连上去
```



## 初始化系统准备安装

这一步我们需要做的是为安装k8s做准备，这一步我们可以脚本化了，不需要那么多手动的操作了。

```shell
ssh ubuntu@192.168.3.151 # ssh上去
wget http://yizhi.ren/linkimage/setupk8s/step1.sh
sh step1.sh arm64  # 支持arm64|amd64两个值
# 输入sudo密码如果需要，确认[OK]如果需要
# 等待一杯茶的功夫，并确认中间没有报错, 如果脚本结束的很快，就要仔细确认是不是出错了
# 脚本会准备好全部需要的组件/库/配置，其中CNI使用的是containerd， kubernets的各种库和组件的版本是v1.22.1
# CNI和kubernets版本没有抽成参数，要修改的话得改改脚本
# 最后输入y重启
```

我们通过上面一系列同样的步骤，把其他两个设备也准备好。



## kubeadm安装master node

其实使用kubeadm建立k8s的master节点本身只是一行指令，但是其中涉及很多参数，还涉及国内拉不到谷歌镜像的问题，这个脚本化就是通过配置需要的参数，然后把组装参数和镜像拉取的事给自动化。

```shell
ssh ubuntu@192.168.3.151 # ssh上去
wget http://yizhi.ren/linkimage/setupk8s/step2.sh
vi step2.sh # 按需要配置以下几个参数
#HOST1=192.168.3.151    # master node ip
#HOST2=192.168.3.152    # worker node ip
#HOST3=192.168.3.153    # worker node ip
#DOMAIN=jinqidiguo.com  # 这个是给集群设置的域名，脚本会使用hosts来映射域名到HOST1的ip
#POD_CIDR=10.244.0.0/16 # pod的ip池
#SERVICE_CIDR=10.20.0.0/16  # service的ip池

bash step2.sh SETUPMASTER
# 不要用sh，有部分语法sh不支持
# 脚本已经解决了国内拉不到谷歌镜像的问题，使用的国内镜像
# 等待完成，如果顺利你将会看到下面的控制台输出

# Your Kubernetes control-plane has initialized successfully!
# ......
# kubeadm join jinqidiguo.com:6443 --token br1b75.ierg26dgogbb9mhl \
# 	--discovery-token-ca-cert-hash sha256:a4a94687aa61547f58f423d8722f824addb24f8a2158291dea3d26f0d92b72aa 
# ...

# 你需要记录下这两行kubeadm join指令，别的可以不关注。记下token和discovery-token-ca-cert-hash两个值
# br1b75.ierg26dgogbb9mhl 和 sha256:a4a94687aa61547f58f423d8722f824addb24f8a2158291dea3d26f0d92b72aa 备用

# 如果失败可以bash step2.sh RESET，然后修复后重试

```
到这，master节点就建设完成了，这时候你可以使用kubectl来操作集群了，当然现在集群只有一个节点。

```shell
~$ kubectl get node
NAME      STATUS     ROLES                  AGE   VERSION
server1   NotReady   control-plane,master   35m   v1.22.1
```

接下来需要安装CNI插件，由于CNI插件大家的安装倾向可能是很不一样的，所以没有做到脚本里。

这里以weave为例(其他CNI插件请自己踩坑)，执行下面的命令来安装即可，注意env.IPALLOC_RANGE参数要跟step1.sh中配置的POD_CIDR值一致：

```shell
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')&env.IPALLOC_RANGE=10.244.0.0/16"

```

等待CNI启动成功后，node的状态会变成Ready：

```shell
~$ kubectl get node
NAME      STATUS   ROLES                  AGE   VERSION
server1   Ready    control-plane,master   65m   v1.22.1
```




## kubeadm安装worker node

```shell
ssh ubuntu@192.168.3.152 # ssh上去
wget http://yizhi.ren/linkimage/setupk8s/step2.sh
vi step2.sh # 按需要配置以下几个参数
#HOST1=192.168.3.151    # master node ip
#HOST2=192.168.3.152    # worker node ip
#HOST3=192.168.3.153    # worker node ip
#DOMAIN=jinqidiguo.com  # 这个是给集群设置的域名，脚本会使用hosts来映射域名到HOST1的ip
#POD_CIDR=10.244.0.0/16 # pod的ip池
#SERVICE_CIDR=10.20.0.0/16  # service的ip池

sh step2.sh JOINWORKER br1b75.ierg26dgogbb9mhl sha256:a4a94687aa61547f58f423d8722f824addb24f8a2158291dea3d26f0d92b72aa
# 其中br1b75.ierg26dgogbb9mhl和sha256:a4a94687aa61547f58f423d8722f824addb24f8a2158291dea3d26f0d92b72aa来自上面master节点记录下来的两行信息


# 等待完成，看到这个信息就表示成功了
This node has joined the cluster:
* Certificate signing request was sent to apiserver and a response was received.
* The Kubelet was informed of the new secure connection details.

Run 'kubectl get nodes' on the control-plane to see this node join the cluster.

# 这时到master节点执行kubectl get node就能看到worker节点了, STATUS状态可能还NotReady, 多等一会
```

```bash
~$ kubectl get node
NAME      STATUS     ROLES                  AGE     VERSION
server1   Ready      control-plane,master   6d22h   v1.22.1
server2   Ready      <none>                 2m3s    v1.22.1
```




## 参考

[a-guide-to-linux-operating-systems-for-kubernetes](https://thenewstack.io/a-guide-to-linux-operating-systems-for-kubernetes/)
[Netplan configuration examples](https://netplan.io/examples/)
[How to install Ubuntu Server on your Raspberry Pi](https://ubuntu.com/tutorials/how-to-install-ubuntu-on-your-raspberry-pi)
[Changing Configuration Options](https://www.weave.works/docs/net/latest/kubernetes/kube-addon/#-changing-configuration-options)

