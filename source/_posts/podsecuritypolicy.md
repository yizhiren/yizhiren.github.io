---
title: k8s中的PodSecurityPolicy
tags:
  - kubernetes
categories:
  - 架构
date: 2022-02-07 17:34:46
updated: 2022-02-07 17:34:46
---


# 简介
k8s中内置了一种安全策略，能够用来约束pod的行为，他叫PodSecurityPolicy，位于apiserver中，默认被关闭。psp定义了哪些是能做的，他的作用范围大都是在securityContext这个结构中，其他也有，比如可以定义哪些volume是支持的，定义哪些端口是允许的。他通过限制这些结构来达到约束pod的目的。

但是psp是一个即将被废弃的功能，如果你看到文章的时候k8s的版本已经出到了v1.25了那么你可以不用看这部分了，根据官方文档，psp会在v1.25被彻底拿掉。至于psp的继任者[Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)我会在后续补上，当前我本地安装的k8s版本还不能使用，要v1.22才能使用。

```
https://kubernetes.io/docs/concepts/policy/pod-security-policy/

PodSecurityPolicy is deprecated as of Kubernetes v1.21, and will be removed in v1.25. It has been replaced by Pod Security Admission. 
```


我们来了解一下这个功能，并演示以下如何开启并使用他。

<!-- more -->

以下的操作是基于自己搭建的k8s集群，搭建集群的步骤参考[树莓派搭建k8s集群](https://yizhi.ren/2022/01/25/setupk8s/)。



# psp为什么废弃


```
https://kubernetes.io/blog/2021/04/06/podsecuritypolicy-deprecation-past-present-and-future/#why-is-podsecuritypolicy-going-away

The way PSPs are applied to Pods has proven confusing to nearly everyone that has attempted to use them. It is easy to accidentally grant broader permissions than intended, and difficult to inspect which PSP(s) apply in a given situation. The “changing Pod defaults” feature can be handy, but is only supported for certain Pod settings and it’s not obvious when they will or will not apply to your Pod. Without a “dry run” or audit mode, it’s impractical to retrofit PSP to existing clusters safely, and it’s impossible for PSP to ever be enabled by default.

psp的授权有两个比较大的问题，一个是除非被明确授予权限，否则默认是没有权限，啥都不能干，这就导致不能随意开启，初始时开启了就没法操作了，而到了线上再开启就很容易影响pod，导致有些pod没有了权限，所以只能初始不开启，然后配置好了，然后开启，然后部署到线上。
另一个问题是psp的授权还依赖RBAC，而RBAC是很间接的，要找到某个service account，再找到相关的role，role中再定义对应的psp，psp中再详细的定义约束，同时如果能找到多个这样role，那么整个路线是这样的：
create pod->user/sa->rolebinding1->role1->psp1->psp rules
                   ->rolebinding2->role2->psp2->psp rules
这里我们可以看到找到pod对应的psp，这个路径是又长又冗余的，而pod最终只能选择一个psp，要么psp1要么psp2这就给找到psp规则带来了更大的复杂性。

所以官方文档中提到的3点，第一点说容易意外的分配过广的权限，这本质是第二个问题的复杂性带来的；
第二点说默认值配置好用，但是对于是否会应用到你的pod这点并不明显，这本质也是第二个问题的复杂性带来的；
第三点说psp没法安全的在现有集群开启并且默认不能开启，这本质是第一个问题带来的。

```

# 如何使用psp

psp用法需要(admission-control enable psp)+(clusterrole/role)+(clusterrolebinding/rolebinding).

也就是psp需要开关进行使能，同时psp是基于RBAC绑定到user/sa的。

```shell
我们定义3个psp，一个是没权限，一个是部分受约束的权限，一个是全开的权限；然后创建对应的3个clusterrole；然后把受约束的clusterrole绑定给用户组system:authenticated和system:serviceaccounts，同时把全开的权限给kubelet用户；没权限的psp这里不去使用。

~$ vi previleges-psp.yaml
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: no-privilege
spec:
  privileged: false
  seLinux:
    rule: RunAsAny
  supplementalGroups:
    rule: RunAsAny
  runAsUser:
    rule: RunAsAny
  fsGroup:
    rule: RunAsAny
  volumes:
  - '*'

---
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: restrict-privileged
spec:
  privileged: false
  # Required to prevent escalations to root.
  allowPrivilegeEscalation: false
  requiredDropCapabilities:
    - ALL
  # Allow core volume types.
  volumes:
    - 'configMap'
    - 'emptyDir'
    - 'projected'
    - 'secret'
    - 'downwardAPI'
    # Assume that ephemeral CSI drivers & persistentVolumes set up by the cluster admin are safe to use.
    - 'csi'
    - 'persistentVolumeClaim'
    - 'ephemeral'
  hostNetwork: false
  hostIPC: false
  hostPID: false
  runAsUser:
    # Require the container to run without root privileges.
    rule: 'MustRunAsNonRoot'
  seLinux:
    # This policy assumes the nodes are using AppArmor rather than SELinux.
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'MustRunAs'
    ranges:
      # Forbid adding the root group.
      - min: 1
        max: 65535
  fsGroup:
    rule: 'MustRunAs'
    ranges:
      # Forbid adding the root group.
      - min: 1
        max: 65535
  readOnlyRootFilesystem: false

---
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: privileged
spec:
  privileged: true
  allowPrivilegeEscalation: true
  allowedCapabilities:
  - '*'
  volumes:
  - '*'
  hostNetwork: true
  hostPorts:
  - min: 0
    max: 65535
  hostIPC: true
  hostPID: true
  runAsUser:
    rule: 'RunAsAny'
  seLinux:
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
  allowedHostPaths:
  - pathPrefix: "/"

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: no-previlege-psp-clusterrole
rules:
- apiGroups: ['policy']
  resources: ['podsecuritypolicies']
  verbs:     ['use']
  resourceNames:
  - no-privilege
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: restrict-previleged-psp-clusterrole
rules:
- apiGroups: ['policy']
  resources: ['podsecuritypolicies']
  verbs:     ['use']
  resourceNames:
  - restrict-privileged
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: previleged-psp-clusterrole
rules:
- apiGroups: ['policy']
  resources: ['podsecuritypolicies']
  verbs:     ['use']
  resourceNames:
  - privileged
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: previleged-psp-binding
roleRef:
  kind: ClusterRole
  name: previleged-psp-clusterrole
  apiGroup: rbac.authorization.k8s.io
subjects:
# Authorize all kubelet:
# https://github.com/kubernetes/kubernetes/blob/a1513161b3056d4c5ef711ab1c5314e97e90811a/cluster/gce/addons/podsecuritypolicies/node-binding.yaml
- kind: Group
  apiGroup: rbac.authorization.k8s.io
  name: system:nodes
- kind: User
  apiGroup: rbac.authorization.k8s.io
  # Legacy node ID
  name: kubelet

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: restrict-previleged-psp-binding
roleRef:
  kind: ClusterRole
  name: restrict-previleged-psp-clusterrole
  apiGroup: rbac.authorization.k8s.io
subjects:
# Authorize all service accounts:
- kind: Group
  apiGroup: rbac.authorization.k8s.io
  name: system:serviceaccounts
# all authenticated users:
- kind: Group
  apiGroup: rbac.authorization.k8s.io
  name: system:authenticated





# 然后apply
~$ kl apply -f previleges-psp.yaml 
Warning: policy/v1beta1 PodSecurityPolicy is deprecated in v1.21+, unavailable in v1.25+
podsecuritypolicy.policy/no-privilege created
podsecuritypolicy.policy/restrict-privileged created
podsecuritypolicy.policy/privileged created
clusterrole.rbac.authorization.k8s.io/no-previlege-psp-clusterrole created
clusterrole.rbac.authorization.k8s.io/restrict-previleged-psp-clusterrole created
clusterrole.rbac.authorization.k8s.io/previleged-psp-clusterrole created
clusterrolebinding.rbac.authorization.k8s.io/previleged-psp-binding created
clusterrolebinding.rbac.authorization.k8s.io/restrict-previleged-psp-binding created
```

接着我们编辑kube-apiserver.yaml来开启psp功能。

```
ubuntu@server1:/etc/kubernetes/manifests$ sudo vi kube-apiserver.yaml
...
- --enable-admission-plugins=NodeRestriction,PodSecurityPolicy
...

# enable-admission-plugins后面添加PodSecurityPolicy
```

之后我们来尝试创建pod，然后查看pod被psp应用了没有。

在[create pod](https://yizhi.ren/2022/02/06/dangerousprivileges/#create-pod)中我们创建过这样一个sa：

```
~$ alias kl=kubectl

# user createpod
~$ kl create sa createpod
serviceaccount/createpod created
~$ kl create role createpodrole --verb=list,create --resource=pod
role.rbac.authorization.k8s.io/createpodrole created
~$ kl create rolebinding createpod --serviceaccount=default:createpod --role=createpodrole
rolebinding.rbac.authorization.k8s.io/createpod created
~$ kl get secret | grep createpod
createpod-token-dl28b       kubernetes.io/service-account-token   3      66s
~$ TOKEN=$(kl get secret createpod-token-dl28b -o jsonpath='{.data.token}' | base64 -d)
~$ kl config set-credentials createpod --token=$TOKEN
User "createpod" set.
~$ kl config set-context createpod --cluster kubernetes --user createpod
Context "createpod" created.
```

我们尝试用这个sa来创建pod，这个sa所在的group为system:serviceaccounts，所以按照预期，这个pod会绑定clusterrole:restrict-previleged-psp-binding, restrict-previleged-psp-binding会绑定psp:restrict-privileged.我们来确认一下：

```
~$ kl --context=createpod run ng --image=nginx
pod/ng created

~$ kl get pod ng -o jsonpath='{.metadata.annotations}'
{"kubernetes.io/psp":"restrict-privileged"}
```

与我们预期的一致。

注意一个特例，在我们初始的集群中，kubectl使用的用户是system:masters组下的，是一个拥有特权的用户，所以对于系统中的所有psp，都是有use权限的，因此system:masters下的用户使用的psp会从系统中全部的psp中选择一个。

```
~$ kl run ng2 --image=nginx
pod/ng2 created

~$ kl get pod ng2 -o jsonpath='{.metadata.annotations}'
{"kubernetes.io/psp":"no-privilege"}
```

可以看到psp:no-privilege虽然没有被任何rolebinding和clusterrolebinding所绑定，依然被pod选为使用的psp。

# psp优先级选择

我们上面提过一嘴，如果一个pod关联了多个psp，那么只能选择一个，选择的过程就相对复杂一些。

```
create pod->user/sa->rolebinding1->role1->psp1->psp rules
                   ->rolebinding2->role2->psp2->psp rules
```

我们可以通过这些文档了解psp选择的逻辑:

```
https://kubernetes.io/docs/concepts/policy/pod-security-policy/#policy-order
https://mozillazg.com/2020/05/k8s-kubernetes-use-which-psp-when-there-are-multiple-pod-security-policies.html

代码：plugin/pkg/admission/security/podsecuritypolicy/admission.go
func (p *Plugin) computeSecurityContext(...)
```

官方文档这么描述：

```
1.PodSecurityPolicies which allow the pod as-is, without changing defaults or mutating the pod, are preferred. The order of these non-mutating PodSecurityPolicies doesn't matter.
2.If the pod must be defaulted or mutated, the first PodSecurityPolicy (ordered by name) to allow the pod is selected.
# 即优先选择不修改pod的psp，其次选择字母序更小的会修改pod的psp。
# 他这里说对于不修改pod的psp，无所谓选择了哪一个。从效果看确实是无所谓的，但是从事实上的选择来说，对于不修改pod的psp，也是按照字母序选择更小的一个psp。
```

更简单的规则描述是，psp按照两层优先级选择最优的一个。首先不修改pod的优先级>修改pod的优先级，其次字母序更小的优先级>字母序更大的优先级。


# 参考
[树莓派搭建k8s集群](https://yizhi.ren/2022/01/25/setupk8s/)
[Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
[Pod Security Policies](https://kubernetes.io/docs/concepts/policy/pod-security-policy/)
[Why is PodSecurityPolicy going away](https://kubernetes.io/blog/2021/04/06/podsecuritypolicy-deprecation-past-present-and-future/#why-is-podsecuritypolicy-going-away)
[node-binding.yaml](https://github.com/kubernetes/kubernetes/blob/a1513161b3056d4c5ef711ab1c5314e97e90811a/cluster/gce/addons/podsecuritypolicies/node-binding.yaml)
[create pod](https://yizhi.ren/2022/02/05/dangerousprivileges/#create-pod)
[policy-order](https://kubernetes.io/docs/concepts/policy/pod-security-policy/#policy-order)
[当有多个可用的 Pod Security Policy 时 k8s 的 PSP 选择策略](https://mozillazg.com/2020/05/k8s-kubernetes-use-which-psp-when-there-are-multiple-pod-security-policies.html)

