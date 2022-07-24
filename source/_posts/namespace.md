---
title: linux namespace
tags:
  - kubernetes
categories:
  - 架构
date: 2022-06-15 17:34:46
updated: 2022-06-15 17:34:46
---

# linux namespace
linux通过namespace技术为进程提供虚拟视图，这项技术是容器的基础。本文主要介绍每个namespace的实现原理，但很可能不对技术本身做探讨。比如会讨论如何实现cgroup的虚拟视图，但不会研究cgroup的控制器的实现原理。
目前在内核(v5.19-rc2,为写作之日的最新版本)中已经支持的namespace有8个。

```
https://github.com/torvalds/linux/blob/v5.19-rc2/include/linux/nsproxy.h#L31
uts namespace
ipc namespace
mnt namespace
pid namespace
net namespace
time namespace
cgroup namespace

https://github.com/torvalds/linux/blob/v5.19-rc2/include/linux/user_namespace.h#L66
user namespace
```
这些namespace起作用的场景是3个系统调用：
1. clone, 他接收namespace等参数，并完成fork进程的功能。
https://man7.org/linux/man-pages/man2/clone.2.html
2. unshare,他创建新的namespace，并把本进程放到新namespace内。
https://man7.org/linux/man-pages/man1/unshare.1.html
3. setns, 把当前进程加入到某些指定的namespace。
https://man7.org/linux/man-pages/man2/setns.2.html

在分别讲每一个namespace之前，我们大致了解下内核代码的相关结构。

<!-- more -->

```c
// 内核中用struct task_struct结构表示进程，其中包含nsproxy字段，其中包含8个namespace中的7个，而另一个namespace则包含在real_cred和cred中。

struct task_struct {
	...
	/* Namespaces的集合: */
	struct nsproxy			*nsproxy;
	...
	const struct cred __rcu		*real_cred;
	const struct cred __rcu		*cred;
}
struct nsproxy {
	atomic_t count;
	struct uts_namespace *uts_ns;
	struct ipc_namespace *ipc_ns;
	struct mnt_namespace *mnt_ns;
	struct pid_namespace *pid_ns_for_children;
	struct net 	     *net_ns;
	struct time_namespace *time_ns;
	struct time_namespace *time_ns_for_children;
	struct cgroup_namespace *cgroup_ns;
};
struct cred {
	...
	struct user_namespace *user_ns;
	...
}

//内核中通过以下标志位来指明是否新建指定的namespace。
#define CLONE_NEWNS	0x00020000	/* New mount namespace group */
#define CLONE_NEWCGROUP		0x02000000	/* New cgroup namespace */
#define CLONE_NEWUTS		0x04000000	/* New utsname namespace */
#define CLONE_NEWIPC		0x08000000	/* New ipc namespace */
#define CLONE_NEWUSER		0x10000000	/* New user namespace */
#define CLONE_NEWPID		0x20000000	/* New pid namespace */
#define CLONE_NEWNET		0x40000000	/* New network namespace */
#define CLONE_NEWTIME	0x00000080	/* New time namespace */
```
当我们调用clone系统调用时，会新建task_struct，同时根据参数决定是否新建namespace。
当调用fork时，会新建task_struct，但不会新建namespace。
当调用unshare时，根据参数决定是否新建namespace，但不会新建task_struct。
当调用setns时，不会新建task_struct，也不会新建namespace。

这里特别解释一下unshare，作为一个系统调用，他把当前进程加入某些新的namespace，但是linux有个命令也叫unshare，这个命令的行为是unshare进程本身加入某些新的namespace，然后这个进程把自己切换成指定的执行体。比如我执行`unshare -T bash`那么unshare进程会启动，然后把自己加入到一个新的time namespace（通过unshare系统调用），并直接启动执行体bash（通过execvp系统调用），也就是接下来这个进程变成unshare的身体，bash的灵魂。

知道了这几个场景后，下面介绍的时候可能只会介绍其中一种场景，比如大部分情况下clone和unshare对namespace的逻辑是一致的，所以会只讲clone或只讲unshare。再比如setns和fork不会新建namespace，因此相对逻辑少一点，就基本上很少讲到这两个调用。

好了下面分别讲每个namespace的原理。

## uts namespace
### 演示
```bash
# 主机中
ubuntu@server2:~$ hostname
server2

# 把当前进程放到新的的uts namespace
ubuntu@server2:~$ sudo unshare -u
root@server2:/home/ubuntu# hostname
server2
# 更改hostname
root@server2:/home/ubuntu# hostname aaa
root@server2:/home/ubuntu# hostname
aaa
root@server2:/home/ubuntu#

# 另开一个窗口查询主机的hostname
ubuntu@server2:~$ hostname
server2

```
可以看到主机的hostname跟那个进程的hostname是隔离的
注意以上修改hostname用hostnamectl的话不成立，这里不展开。

### 介绍
uts namespace设置hostname和nis domain的虚拟视图，nis（网络信息服务）介绍如下，但这已经是一项过时的技术，所以我们不去关注, 只需要关注hostname。
```
https://docs.freebsd.org/doc/7.1-RELEASE/usr/share/doc/zh_CN/books/handbook/network-nis.html
NIS， 表示网络信息服务 (Network Information Services) 
...
　　这是一个基于 RPC 的客户机/服务器系统， 它允许在一个 NIS 域中的一组机器共享一系列配置文件。 这样， 系统管理员就可以配置只包含最基本配置数据的 NIS 客户机系统， 并在单点上增加、 删除或修改配置数据。
...
```
另外要说的是uts全称是UNIX Time-Sharing，这个名称跟时间无关，他的意思表达的是多用户的分时系统，所以目的是让多用户看到不同的信息，所以这里uts ns也就是让不同的进程看到不同的系统信息。

### 原理
由于nis我们不关注，因此这里只关注uts namespace对hostname的影响。
uts namespace的逻辑比较简单，在进程结构task_struct->nsproxy->uts_ns->name中保存了一个hostname等信息:
```c
// 进程结构
struct task_struct {
	...
	/* Namespaces: */
	struct nsproxy			*nsproxy;
	...
}
// namespace集合
struct nsproxy {
	...
	struct uts_namespace *uts_ns;
	...
};
// uts namespace
struct uts_namespace {
	struct new_utsname name;
	...
}
// hostname等相关信息的存储结构
struct new_utsname {
	...
	char nodename[__NEW_UTS_LEN + 1];
	...
};

```

当前面指定的clone系统调用被执行时，将发生namespace是否新建的检查，如果没有指定CLONE_NEWUTS，那么子进程和父进程共享同一个结构，也就是子进程的task_struct->nsproxy->uts_ns指针与父进程相同，如果指定CLONE_NEWUTS参数，那么就会从父进程拷贝一份赋给子进程。后续gethostname和sethostname都是直接操作task_struct->nsproxy->uts_ns->name这个结构，因此可以做到每个进程有自己hostname。unshare的逻辑与clone相似，差别是unshare只新建nsproxy不新建task_struct。
```c
// 获取hostname的系统调用，将从task_struct->nsproxy->uts_ns->name结构中拷贝nodename结构。同样sethostname逻辑类似，不做列举。
SYSCALL_DEFINE2(gethostname, char __user *, name, int, len)
{
	...
	char tmp[__NEW_UTS_LEN + 1];
	...
	u = utsname();
	...
	memcpy(tmp, u->nodename, i);
	if (copy_to_user(name, tmp, i))
	...
}
static inline struct new_utsname *utsname(void)
{
	return &current->nsproxy->uts_ns->name;
}
```

再补充一点new_utsname中不止nodename，还包含其他字段，所有字段加起来就是uname命令能查看的全部信息。
```c
struct new_utsname {
	char sysname[__NEW_UTS_LEN + 1];
	char nodename[__NEW_UTS_LEN + 1];
	char release[__NEW_UTS_LEN + 1];
	char version[__NEW_UTS_LEN + 1];
	char machine[__NEW_UTS_LEN + 1];
	char domainname[__NEW_UTS_LEN + 1];
};
```
只是除了nodename(hostname)和domainname(nis)外并没有提供字段的设置方法，所以其他字段是没法修改的，所以子进程看到的其他字段跟父进程是一样的，整个主机看到的也都是一样的。

## ipc namespace
ipc namespace主要负责隔离3个进程间通信的资源，一个是消息队列（Message queues），一个是共享内存（Share Memory），一个是信号量（Semaphore）, 这些 IPC 机制的共同特点是 IPC 对象由文件系统路径名以外的机制标识。他们的实现隔离的方法也比较简单，跟uts ns类似，在进程中存储一份独立的ipc相关的资源，后续的系统调用都从进程的这个资源中进行操作。在创建进程的时候如果不指定CLONE_NEWPID参数则与父进程共享task_struct->nsproxy->ipc_ns，如果指定CLONE_NEWPID参数，则调用create_ipc_ns新建：
```c
static struct ipc_namespace *create_ipc_ns(struct user_namespace *user_ns, struct ipc_namespace *old_ns)
{
	struct ipc_namespace *ns;
	...
	ns = kzalloc(sizeof(struct ipc_namespace), GFP_KERNEL_ACCOUNT);
	...
	err = mq_init_ns(ns);
	msg_init_ns(ns);
	...
	sem_init_ns(ns);
	...
	shm_init_ns(ns);
	...
	return ns;

	...
}
```
后续相关的ipc操作都会操作namespace下的资源：
```c
SYSCALL_DEFINE3(semget, key_t, key, int, nsems, int, semflg)
{
	return ksys_semget(key, nsems, semflg);
}
long ksys_semget(key_t key, int nsems, int semflg)
{
	struct ipc_namespace *ns;
	...
	struct ipc_params sem_params;
	ns = current->nsproxy->ipc_ns;
  ...
	sem_params.key = key;
	sem_params.flg = semflg;
	sem_params.u.nsems = nsems;
	// 从ns中get或者create信号量
	return ipcget(ns, &sem_ids(ns), &sem_ops, &sem_params);
}
```
可以看到semget是从当前进程的ipc_ns（current->nsproxy->ipc_ns）中去get的，其他shmget和msgget也是一样的。


## mnt namespace
### 演示
```bash
# 创建临时目录xfs
ubuntu@server2:~$ mkdir xfs
# 把当前进程放到新的mount namespace中
ubuntu@server2:~$ sudo unshare -m
# 确认当前xfs为空
root@server2:/home/ubuntu# ls xfs
# 把/tmp目录和xfs绑定起来
root@server2:/home/ubuntu# mount --bind /tmp ./xfs
# 此时xfs下已经跟/tmp目录下一致了
root@server2:/home/ubuntu# ls xfs
1                             systemd-private-04c03578189843079c7ac8a0f81bbc32-fwupd-refresh.service-DlzrBz
...


# 新开一个窗口，查看xfs, 依然为空
ubuntu@server2:~$ ls xfs
ubuntu@server2:~$
```
可以看到mount namespace中的mount不会影响主机的mount。 
再来看一个例子：

```bash
# 找到k8s中位于server2主机上的一个pod
ubuntu@server2:~$ kubectl get pod busycat -owide
NAME      READY   STATUS    RESTARTS   AGE    IP             NODE      NOMINATED NODE   READINESS GATES
busycat   1/1     Running   0          5d8h   10.244.192.7   server2   <none>           <none>

# 进入该容器
ubuntu@server2:~$ kubectl exec busycat -it -- sh
# cat随便一个文件
/ # echo aaa > /tmpfile
/ # cat /tmpfile
aaa

# 新开一个窗口，查看同样的文件
ubuntu@server2:~$ cat /tmpfile
cat: /tmpfile: No such file or directory

```
可以看到容器中的文件系统根主机的是不同的

### 介绍
mount namespace用于给进程提供一个独立的目录结构，也就是他看到的/xxx目录跟主机上的/xxx是不同的，甚至主机上可以不存在这个xxx目录。他采用CLONE_NEWNS标志位表示是否需要新建mount namespace, 这个namespace是linux最早引入的namespace，当时只有这一种namespace，所以直接把NS作为名字来代表他，沿用至今。

### 原理
当前面指定的clone系统调用被执行时，将发生namespace是否新建的检查，如果没有指定CLONE_NEWNS，那么子进程和父进程共享同一个结构，也就是子进程的task_struct->nsproxy->mnt_ns指针与父进程相同，所以子进程和父进程mount的是同样的节点和内容, 如果指定CLONE_NEWNS参数，那么会遍历父进程的每一个mount，全部拷贝一份给子进程，mount列表存储在进程的task_struct->nsproxy->mnt_ns结构中, 拷贝后子进程跟父进程看到的文件结构视图还是跟父进程一样的。只有在重新卸载和挂载不同文件系统后子进程才能看到不同的文件视图。
mount结构存储在struct mnt_namespace，并以两种组织方式存在，一个是树形结构，一个是链表结构，只是组织方式不同，用于不同场景。
```c
struct mnt_namespace {
	...
	struct mount *	root; // 根路径，树形结构
	...
	struct list_head	list;  // 所有的mount组成的链表
	...
} 
```
内核在拷贝mout列表时，采用深度遍历root字段进行拷贝的方式来生成新的root和list字段。

![dfsmount](/linkimage/namespace/dfsmount.png)

图片基于[mnt_namespace的拷贝过程解读(copy_tree函数)](http://blog.chinaunix.net/uid-26552184-id-5842494.html)

mount的挂载过程有点复杂，但是mount namespace提供视图隔离的过程却很简单。
当新进程创建了mount ns后，由于在task_struct->nsproxy->mnt_ns存储了进程独有的所有mount，所以进程可以独立的更改自己文件系统。(但是用户调用mount时，具体流程中是哪个函数关联了mnt ns我还是找不到，望知道的同学告知。）接下来我们来看如何让子进程看到不同的视图，我们已经已经知道了这需要一个重新挂载文件系统的过程，那么是用什么方法来挂载呢？
先补充一个知识，什么是根文件系统rootfs，有些地方把rootfs专用于指内核启动之后挂载的一个小型文件系统，内核启动后内存中是空的，这时候他会加载一个小型的文件系统到内存中，这个文件系统会挂载到根目录"/",整个系统中包含启动所需的bin和lib，这个文件系统就叫rootfs，于是内核执行rootfs中的init进程，init进程于是找到磁盘中的文件系统，并执行系统调用把根目录切换到磁盘中的大文件系统，init重启自己，重启的就是磁盘中的init了。我们看linux系统中boot目录下的两个主要的文件，vmlinuz就是内核，initrd.img就是rootfs。至于内核跟rootfs为啥分开分步加载，是为了内核保持稳定，rootfs保持开放。
```bash
~$ ls /boot
...
initrd.img                     vmlinuz
...
```
这种定义rootfs的方式比较狭义，还有一种广义的说法，rootfs就是挂载到"/"的文件系统，而其他所有的文件系统都是挂载到rootfs中的某个节点。从这个角度说rootfs就是一个进程看到的文件视图。我们可以采用这个个广义的说法来理解。
那么为了给进程一个全新的视图，我们的思路就很清楚了，1：创建进程携带创建CLONE_NEWNS参数，2：给子进程挂载rootfs，3：启动子进程。 这样甚至子进程的执行文件都可以来自于新的rootfs，非常的灵活。能实现这个功能的两个系统调用一个是chroot一个是pivot_root,他俩的内核代码分别是：
```c
// 把进程所在mnt ns的所有进程的rootfs设为new_root, 并且原root挂到新root的put_old下
SYSCALL_DEFINE2(pivot_root, const char __user *, new_root,
		const char __user *, put_old)
{
	...
	/* 1.把新root从原root那里卸载 */
	umount_mnt(new_mnt);
	...
	/* 2.把原root挂载到put_old */
	attach_mnt(root_mnt /*原root*/, old_mnt /*put_old*/, old_mp /*put_old对应的挂载点*/);

	/* 3. 把新root挂载到根 / */
	attach_mnt(new_mnt /*新root*/, root_parent /*目标root*/, root_mp/*目标root对应的挂载点*/);
	...
	/* 4. 给mount ns下的全部进程更新root */
	chroot_fs_refs(&root, &new);
}

// 给相同fs结构的进程切换root到filename所在位置
SYSCALL_DEFINE1(chroot, const char __user *, filename)
{
	...
	// 进程之间如果通过CLONE_FS参数clone的，fs会指向相同的结构，那么就都会受到影响
	set_fs_root(current->fs, &path);
	...
}

```
对比来看突出一点是，pivot_root改变了整个mount ns下进程的root，而chroot是改变相同fs结构的进程的root。但是本质上都可以实现我们的功能。
还有个区别是chroot可以切换到任意路径，但是pivot_root要求新root得是独立的文件系统，也就是能够从原来的rootfs中卸载，同时还要求put_old得是新root下的某个目录，因为原root还得挂回新root的put_old下。你可能会觉的新root下挂个老的root不是很奇怪吗也不安全，所以实际中调用完pivot_root后往往会把put_old卸载，然后删除put_old目录。

## pid namespace
### 演示
```bash
# 在主机上查看进程1的stat。
ubuntu@server2:~$ cat /proc/1/stat
1 (systemd) S 0 1 1 0 -1 4194560 253243 27738159 129 20158 24351 27841 292248 243904 20 0 1 0 0 171737088 3041 18446744073709551615 1 1 0 0 0 0 671173123 4096 1260 0 0 0 17 3 0 0 80 0 0 0 0 0 0 0 0 0 0

# 创建一个新进程，新进程会创建pid namespace和mount namespace，并重新挂载procfs
ubuntu@server2:~$ sudo unshare -mp --fork --mount-proc
# 在新进程上查看进程1的stat。
root@server2:/home/ubuntu# cat /proc/1/stat
1 (bash) S 0 1 0 34817 12 4194560 949 1644 0 0 3 2 1 3 20 0 1 0 152887052 10334208 1220 18446744073709551615 187650098462720 187650099827568 281474713196688 0 0 0 65536 3686404 1266761467 1 0 0 17 0 0 0 0 0 0 187650099894296 187650099946120 187651076325376 281474713200821 281474713200827 281474713200827 281474713202670 0
```
可以看到两个进程看到的1号进程的信息是不同的。这里不是要讲procfs，而是想说，在pid namespace中，pid是独立分配的。

这里介绍一下上面unshare命令中的几个参数：
首先-p以及--fork是配合的，我们知道unshare默认是不会新建进程的，如果我们想通过-p来创建新的pid ns，虽然是新建成功了，但是此进程并不会真的加入到新的pid中，pid ns只能在进程新建时设置并起作用，所以我们这里通过--fork来新建一个进程, 默认新进程是${SHELL}。
接着-m和--mount-proc也是配合使用的，由于我们要查看/proc下的信息，而默认proc会继承父进程的proc，因此你只能看到原来的proc信息，为了看到新的pid ns下的proc信息，我们需要重新挂载procfs，于是我们指定--mount-proc来挂载新的procfs，但是我们不能在挂载新的procfs时候影响到主机的/proc目录，因此我们这个新进程得新建一个mount namespace来隔离与主机之间mount信息，因此我们指定-m参数。不过这里-m可以不指定，--mount-proc会隐含-m参数。

### 介绍
pid namespace用来给进程提供一个虚拟的pid视图，一个pid namespace内的进程id可以独立分配，与其他pid namespace的pid可以重复。

### 原理
内核中进程结构中与pid相关几个字段
```c
struct task_struct {
	...
	pid_t				pid;
	struct pid			*thread_pid;
	struct nsproxy			*nsproxy;
	...
}
```
其中pid字段的类型是pid_t，这就是一个整数，这个pid是内核空间用来管理这个进程的，也就是可以理解成不存在namespace的时候进程的原本的一个id。有多少namespace都不影响这个值。
thread_pid是一个pid的结构体，这个结构很关键：
```c
struct pid
{
	unsigned int level;
	...
	struct upid numbers[1];
};
struct upid {
	int nr;
	struct pid_namespace *ns;
};
```
其中level代表这个进程位于第几层namespace，原始的进程都是第0层，如果你创建了一个进程，并且没有指明新建pid namespace，那么这个新进程的level还是第0层，也就是和父进程一样的值。如果这个进程指明了要新建pid namespace，那么level就会加1，比父进程的level大1. 如果level值越大，代表嵌套的pid namespace越深。由于进程在每个namespace层次中都具体不同的pid，因此numbers这里记录了每一层中进程在其中的pid和这一层的namespace指针。这里numbers虽然数组长度是1，但是他是结构的最后一个字段，因此在实际使用numbers的时候是直接溢出访问的，只要使用者自己控制好内存的安全，可以把numbers当成任意长度的数组。
接下来是nsproxy中的pid_namespace结构，pid_namespace中也有level字段，表示这个namespace位于第level层：
```c
struct pid_namespace {
	…
	unsigned int level;
	…
}

```
现在我们看到两个地方都有level字段，一个是`thread_pid->level`，一个是`nsproxy->pid_ns_for_children->level`，大多数时候，一个进程的`thread_pid->level`和`nsproxy->pid_ns_for_children->level`，这两个值应该是相同的，因此`thread_pid->numbers[thread_pid->level].nr` 和`thread_pid->numbers[nsproxy->pid_ns_for_children->level].nr`大部分时候是相等的。不相等的场景是，我们用`unshare -p`把当前进程带入一个新的pid ns，这时候`nsproxy->pid_ns_for_children->level`会+1，而`thread_pid->level`不会+1，这就是我们在演示中提到需要`--fork`参数来新建进程，否则这个进程的`thread_pid->level`不会增加，因此进程实际并没有加入新的pid namespace，`echo $$`拿到的pid也依然是`thread_pid->numbers[thread_pid->level].nr`没有变。
那么对一个进程来说，他自己看到的自己的pid是哪一层的呢？当我们在进程中调用getpid的系统调用的时候，通过追踪代码，他实际是通过thread_pid->numbers[thread_pid->level].nr拿到的，也就是拿到thread_pid结构中最深层namespace下的pid。

```c
SYSCALL_DEFINE0(getpid)
{
	// current是当前进程的task_struct结构
	return task_tgid_vnr(current);
}
// 最终调到pid_nr_ns
// 其中ns通过thread_pid->numbers[thread_pid->level].ns得到
pid_t pid_nr_ns， 其中(struct pid *pid, struct pid_namespace *ns)
{
	struct upid *upid;
	pid_t nr = 0;

	if (pid && ns->level <= pid->level) {
		upid = &pid->numbers[ns->level];
		if (upid->ns == ns)
			nr = upid->nr;
	}
	return nr;
}

```
还剩两个问题，一个是pid_namespace是在什么时候新建的呢？
跟前面的namespace一样，pid namespace也是在clone或者unshare的时候根据标志位CLONE_NEWPID来决定是跟父进程一样还是新建一个。
另一个问题是进程新建的时候要每一层namespace都分配一个pid，那么如何做到每一层单独分配的。可以通过这个函数看到：

```c
struct pid *alloc_pid(struct pid_namespace *ns, pid_t *set_tid,
		      size_t set_tid_size)
{
	struct pid *pid;  // 对应新建的pid结构
	struct pid_namespace *tmp; // 暂存入参的ns，ns是前面刚新建的pid namespace结构
	...
	tmp = ns;
	pid->level = ns->level; // 设置level值

	// 遍历每一层，每一层都新建一个pid
	// 然后把新建的pid和这一层的namespace赋给pid结构的numbers字段。
	for (i = ns->level; i >= 0; i--) {
		int tid = 0;
		...
			// 每一层的pid可分配值是维护在该层namespace的idr结构上的
			// 一个分配完，idr字段随即也更新。
			// 所以每一层namespace的pid分配是独立的。
			nr = idr_alloc_cyclic(&tmp->idr, NULL, pid_min,
					      pid_max, GFP_ATOMIC);
		...
		pid->numbers[i].nr = nr;
		pid->numbers[i].ns = tmp;
		tmp = tmp->parent;
	}

}
```
关键信息是在每个pid namespace结构中维护了一个id分配器。



## net namespace
### 演示

```bash
# 把当前进程加入一个新建的net namespace中
ubuntu@server2:~$ sudo unshare -n
root@server2:/home/ubuntu# ip link
1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
root@server2:/home/ubuntu#

# 新建一个窗口执行
ubuntu@server2:~$ ip link
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
2: eth0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc mq state DOWN mode DEFAULT group default qlen 1000
    link/ether e4:5f:01:71:5e:16 brd ff:ff:ff:ff:ff:ff
3: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP mode DORMANT group default qlen 1000
    link/ether e4:5f:01:71:5e:17 brd ff:ff:ff:ff:ff:ff
......
```

可以看到主机和某个net namespace中的进程是独立的，不一样。


### 介绍
net namespace可以让进程看到自己独有的网络资源，包括网络设备，IPv4 IPv6协议栈, 端口号，路由表, 防火墙等，比如每个net ns有自己的lo。

### 原理
跟其他namespace一样，net ns也是在创建进程的时候通过标志位CLONE_NEWNET来决定是继承父进程的net结构还是自己新建一个net结构。而我们所知道的lo设备就是在新建net结构后的初始化过程中创建出来的：

```c
//复用或者新建net结构
struct net *copy_net_ns(unsigned long flags,
			struct user_namespace *user_ns, struct net *old_net)
{
	...
	// 新建net结构
	net = net_alloc();
	...
	//初始化net结构
	rv = setup_net(net, user_ns);
	...
}
//初始化net结构
static __net_init int setup_net(struct net *net, struct user_namespace *user_ns)
{
	...
	// 遍历每一个初始化器为新建的net ns进行初始化
	list_for_each_entry(ops, &pernet_list, list) {
		error = ops_init(ops, net);
		if (error < 0)
			goto out_undo;
	}
	...
}
// 其中一个初始化器，完成初始化lo的工作
static __net_init int loopback_net_init(struct net *net)
{
	...
	dev = alloc_netdev(0, "lo", NET_NAME_UNKNOWN, loopback_setup);
	...
	net->loopback_dev = dev;
	return 0;
	...
}

```
再比如我们创建socket的时候，也会绑定到当前进程的net ns：
```c
// 创建socket
int sock_create(int family, int type, int protocol, struct socket **res)
{
	// 传入当前进程的net namespace
	return __sock_create(current->nsproxy->net_ns, family, type, protocol, res, 0);
}
// 最终调用到
void sock_net_set(struct sock *sk, struct net *net)
{
	write_pnet(&sk->sk_net, net);
}
static inline void write_pnet(possible_net_t *pnet, struct net *net)
{
	pnet->net = net;
}

```
### net namespace之间通信
另外关于net namespace的注意点就是关于如何跨net ns通信，内核提供了veth pair，这是一种类似进程中的pipe的虚拟设备对，一对设备包括两个虚拟网卡，一个放入ns1，一个放入ns2,那么往一边写入数据，另一边就可以收到数据，方向则是双向的。

![vethpair](/linkimage/namespace/vethpair.png)

图片来自[linux 网络虚拟化： network namespace 简介](https://cizixs.com/2017/02/10/network-virtualization-network-namespace/)

那么为了让多个ns之间彼此通信该怎么做呢，这时候需要再引入一个网桥设备，这个设备起到一个交换机的作用，每个ns创建后，配套创建一个veth pair对，把veth pair的一端放入ns，另一端放到网桥上，这样ns之间就彼此联通了。

![bridgevethpair](/linkimage/namespace/bridgevethpair.png)

图片来自[linux 网络虚拟化： network namespace 简介](https://cizixs.com/2017/02/10/network-virtualization-network-namespace/)

比如在我的主机上执行:

```bash
ubuntu@server2:~$ bridge link
9: vethwe-bridge@vethwe-datapath: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1376 master weave state forwarding priority 32 cost 2
12: vethwepl4866066@if11: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1376 master weave state forwarding priority 32 cost 2
…
```
这里可以看到在名叫weave的这个网桥上挂的所有虚拟网卡，而每一个都是veth pair的一端，这可以从他们的名字上看出`id:xxx@yyy`，这个格式表示序号为id的本网卡和yyy是一个网卡对，yyy可能只是名字上部分匹配对端的网卡名，需要稍微辨别一下。比如`9: vethwe-bridge@vethwe-datapath`表示本网卡id是9，对端网卡名接近vethwe-datapath。比如`12: vethwepl4866066@if11`表示本网卡id是12，对端网卡名接近if11。
但是目标网卡不一定存在于我们主机的初始net ns中，可能在一个容器的ns中，我们可以通过下面这行脚本来找出这个对端在什么地方,以寻找if11为例：

```bash
ubuntu@server2:~$ ip netns | cut -f 1 -d " " | xargs -i{} sh -c 'echo {} && sudo ip netns exec {} ip addr | grep 11'
cni-8324acc1-9d90-1985-9e71-55859269bb80
cni-31bfe5a7-1950-8a93-0f37-d0be6e4c784b
cni-741285dc-d526-ad63-c258-146f99fb7931
    inet6 fe80::cc25:c1ff:fe7b:f11b/64 scope link
cni-13603be0-dd99-995f-fca5-5e7df88582d5
...
cni-e2665039-d33a-9f75-17df-5c8c90a4f4ec
11: eth0@if12: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1376 qdisc noqueue state UP group default
```
可以看到if11是在`cni-e2665039-d33a-9f75-17df-5c8c90a4f4ec`这个net ns下，是id为11的网卡。但是我们查找vethwe-datapath却不能用这个脚本，因为vethwe-datapath直接在主ns下，`ip netns`不会列出主net ns所以需要直接执行ip addr来查看。
```bash
ubuntu@server2:~$ ip addr | grep  veth
8: vethwe-datapath@vethwe-bridge: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1376 qdisc noqueue master datapath state UP mode DEFAULT group default
9: vethwe-bridge@vethwe-datapath: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1376 qdisc noqueue master weave state UP mode DEFAULT group default
...
```

## time namespace
### 演示
```bash
# 把当前进程放入新建的time namespace中，下面这些命令和参数后面都会解释
ubuntu@server2:~$ sudo unshare -T -- bash --norc
# 配置offset
bash-5.1# echo "boottime  $((7*24*60*60)) 0" > /proc/$$/timens_offsets
# 查看uptime
bash-5.1# uptime --pretty
up 1 week, 28 minutes
bash-5.1#


# 新开一个窗口
ubuntu@server2:~$ uptime --pretty
up 28 minutes
ubuntu@server2:~$
```
可以看到主机和处于time namespace的进程，拿到的uptime是有差异的，是独立的。


### 介绍
time namespace影响的是两个时间，`CLOCK_MONOTONIC`和`CLOCK_BOOTTIME`。`CLOCK_BOOTTIME`表示系统启动到现在的时间，`CLOCK_MONOTONIC`表示`CLOCK_BOOTTIME`-`系统暂停的时间`，也就是启动后系统实际运转的时间。
但time namespace不影响系统的实时时间。也就是你调用date命令不会有什么改变的。

### 原理
和其他ns一样，time ns也是在进程创建时候指定了CLONE_NEWTIME参数后从父进程拷贝一份。time_namespace的结构体如下：

```c
struct time_namespace {
	...
	struct timens_offsets	offsets;
	...
	/* 禁止修改的标志 */
	bool			frozen_offsets;
}
struct timens_offsets {
	struct timespec64 monotonic;
	struct timespec64 boottime;
};
```
他起作用的方式是通过指定monotonic和boottime这两个offset字段，随后在系统返回相应的时间的时候叠加上offset值。以uptime为例(sudo cat /proc/uptime)：
```c
static int uptime_proc_show(struct seq_file *m, void *v)
{
	...
	// 获取时间
	ktime_get_boottime_ts64(&uptime);
	// 叠加boottime的offset
	timens_add_boottime(&uptime);
	...
	// 按照指定格式输出
	seq_printf(...)
}
static inline void timens_add_boottime(struct timespec64 *ts)
{
	//当前进程的time ns的offset
	struct timens_offsets *ns_offsets = &current->nsproxy->time_ns->offsets;
	//给ts叠加offset
	*ts = timespec64_add(*ts, ns_offsets->boottime);
}
```
可以看到uptime返回前会叠加ns_offsets->boottime值。
那么offset值如何配置呢，是通过修改`/proc/$$/timens_offsets`文件来做到的。timens_offsets文件的格式第一列是offset类别，第二列是offset的秒数，第三列是offset的纳秒数。下面我们操作一下：

```bash
# 用uptime命令来读取boottimne，比直接读/proc/uptime文件可读性好
ubuntu@server2:~$ uptime --pretty
up 2 weeks, 3 days, 1 hour, 16 minutes
# 读当前进程的timens的offset
ubuntu@server2:~$ cat /proc/$$/timens_offsets
monotonic           0         0
boottime            0         0

# 创建新的time namespace，本进程加入新的time namespace，并启动命令bash --norc(注意这并不创建新进程，依然在当前进程(unshare进程)中，unshare默认是不创建新进程的)。此时uptime和/proc/$$/timens_offsets还是和父进程一样的，但我们这里暂时不能读，在修改offset前读了会导致后续修改offset失败，后面会解释原因。
ubuntu@server2:~$ sudo unshare -T -- bash --norc
# 修改offset
bash-5.1# echo "boottime  $((7*24*60*60)) 0" > /proc/$$/timens_offsets
bash-5.1# echo "monotonic $((2*24*60*60)) 0" > /proc/$$/timens_offsets
# offset已经改变
bash-5.1# cat /proc/$$/timens_offsets
monotonic      172800         0
boottime       604800         0
# uptime也已经变了
bash-5.1# uptime --pretty
up 3 weeks, 3 days, 1 hour, 16 minutes
```

### bash --norc背后的玄机
如果不感兴趣，这段可以不看，问题不大。

这里有一个注意点，我们执行unshare创建bash的时候，需要传递参数--norc，而且在我的注释中也写到在改offset前不能读offset和uptime，否则不管是没传--norc还是提前读了offset，都会导致后续写/proc/$$/timens_offsets报错Permission denied.
```bash
ubuntu@server2:~$ sudo unshare -T -- bash
root@server2:/home/ubuntu# echo "boottime  $((7*24*60*60)) 0" > /proc/$$/timens_offsets
bash: echo: write error: Permission denied
```

```bash
ubuntu@server2:~$ sudo unshare -T -- bash --norc
bash-5.1# cat /proc/$$/timens_offsets
monotonic           0         0
boottime            0         0
bash-5.1# echo "boottime  $((7*24*60*60)) 0" > /proc/$$/timens_offsets
bash: echo: write error: Permission denied
```

这是为什么呢，本质上都是要求在修改offset之前不能创建子进程，norc参数可以让bash不要执行bashrc等脚本，执行脚本就会产生fork系统调用创建子进程，而读了offset也会fork进程。在fork进程的流程中，time_namespace结构中的frozen_offsets字段会被设置上，导致无法更改offset。
```c
struct time_namespace {
	...
	struct timens_offsets	offsets;
	...
	/* 禁止修改的标志 */
	bool			frozen_offsets;
}

https://man7.org/linux/man-pages/man7/time_namespaces.7.html
Above, we started the bash(1) shell with the --norc options so
       that no start-up scripts were executed.  This ensures that no
       child processes are created from the shell before we have a
       chance to update the timens_offsets file.
```

那么有个很奇怪的问题，为什么这里echo这个指令引起的fork没有导致Permission denied？？？？？？
答案是因为bash把echo命令内置了，它并不会fork进程，如果你使用/bin/echo来echo的话就也会导致Permission denied。
```
https://edoras.sdsu.edu/doc/bash/abs/internal.html
A builtin may be a synonym to a system command of the same name, but Bash reimplements it internally. For example, the Bash echo command is not the same as /bin/echo, although their behavior is almost identical.
```
那么为什么内核会有这样一个设定呢，为什么修改offset之前fork一下就不能修改了呢？
```
https://lore.kernel.org/lkml/20191112012724.250792-3-dima@arista.com/t/
Allocate the timens page during namespace creation. Setup the offsets
when the first task enters the ns and freeze them to guarantee the pace
of monotonic/boottime clocks and to avoid breakage of applications.
```
根据这个讨论记录可以看出，设计的目的是确保这个offset修改只发生在time ns的首个进程启动之前，启动后就不修改了防止对进程的影响。

但是unshare不受此约束，不会去设置frozen_offsets。上面他们的讨论中有提到unshare，不过我不太能看懂是否这是特意留下的一种修改offset方式。我比较倾向于这是设计者特意留下的一种修改已经启动的进程的offset的方法。

进程启动后的修改我们知道可以通过timens_offsets文件修改，那么进程启动前怎么修改？是通过[vdso](https://man7.org/linux/man-pages/man7/vdso.7.html)配置的，我也不懂就不展开了，可以自己有兴趣去搜一下。
但是还有个问题，frozen_offsets实际是配在子进程上的，只会对子进程生效，怎么bash创建一个子进程执行脚本后，自己也不能修改offset了呢，我们来捋一下这个流程。
在进程中保存time ns的字段实际有两个:

```c
struct nsproxy {
	...
	struct time_namespace *time_ns;
	struct time_namespace *time_ns_for_children;
	...
};
```
对于unshare流程来说，这两个字段中time_ns直接和父进程的值相同，time_ns_for_children则根据有没有设置标志位选择与父进程的time_ns_for_children一致或者自己新建。假设我们初始进程的结构是：
```c
struct nsproxy {
	...
	time_ns: N1;
	time_ns_for_children: N2;
	...
};
```
我们可以大概的认为time_ns是父进程的ns,time_ns_for_children是本进程的ns，而二者的差异可以判断ns是否新建。
当我们执行sudo unshare -T -- bash(不带norc)时，我们新建出来的bash进程(也就是unshare进程, 此时是unshare的身体，bash的灵魂)的结构是：

```c
struct nsproxy {
	...
	time_ns: N1;
	time_ns_for_children: N3;
	...
};
```
可见unshare之后新进程的time_ns保留了父进程的ns，而time_ns_for_children则新建了。这时候unshare不会为我们做别的了，也不会设置frozen_offsets。
接着bash会fork子进程来执行脚本或者执行命令行，这个过程不会设置CLONE_NEWTIME的标志位。这时候新建出来的子进程的结构是：

```c
struct nsproxy {
	...
	time_ns: N1;
	time_ns_for_children: N3;
	...
};
```
跟父进程保持不变，但是还没完，fork会比unshare多做一步，会执行一遍timens_on_fork检查：
```c
void timens_on_fork(struct nsproxy *nsproxy, struct task_struct *tsk)
{
	...
	if (nsproxy->time_ns == nsproxy->time_ns_for_children)
		return;
	nsproxy->time_ns = nsproxy->time_ns_for_children;
	timens_commit(tsk, ns);
}
```
这里time_ns和time_ns_for_children不相同(N1 != N3)，表示有新的time ns创建了，这时候就会把time_ns_for_children赋值给time_ns(time_ns也变成N3)，同时设置上N3的frozen_offsets。于是这个子进程没法修改offset了，同时unshare出来的那个进程因为也是拥有N3，所以也没法修改offset了。这与我们的结果相符。

因此整个过程是，unshare导致了time_ns和time_ns_for_children的差异，然后在fork时子进程继承time_ns和time_ns_for_children，接着由于fork的frozen_offsets的特性，检测到time_ns和time_ns_for_children差异后，把time_ns_for_children设置上frozen_offsets。于是这两个进程都没法修改了。



## cgroup namespace
### 演示
演示流程是：
1.查看当前进程的cgroup节点路径
2.新建cgroup namespace不变的子进程，验证cgroup节点路径默认继承
3.新建创建了新cgroup namespace的子进程，验证cgroup节点路径有变化

```bash
###########################################################
# 先记下cgroup挂载路径
ubuntu@server2:~$ mount | grep cgroup
cgroup2 on /sys/fs/cgroup type cgroup2 (rw,nosuid,nodev,noexec,relatime)

# 查看当前进程的cgroup节点路径
ubuntu@server2:~$ cat /proc/self/cgroup
0::/user.slice/user-1000.slice/session-21.scope
# 当前进程的pid
ubuntu@server2:~$ echo $$
347990

# 验证当前进程cgroup确实在指定节点
ubuntu@server2:~$ cat /sys/fs/cgroup/user.slice/user-1000.slice/session-21.scope/cgroup.procs  | grep 347990
347990

##############################################################
# 验证不创建新cgroup namespace时，新进程依然在父进程相同的cgroup节点
# 创建跟原namespace相同的进程
ubuntu@server2:~$ unshare
# 查看当前进程的cgroup节点路径，发现跟父进程的节点路径是一样的
ubuntu@server2:~$ cat /proc/self/cgroup
0::/user.slice/user-1000.slice/session-21.scope
# 当前进程的pid
ubuntu@server2:~$ echo $$
352785
# 验证当前进程cgroup确实在指定节点
ubuntu@server2:~$ cat /sys/fs/cgroup/user.slice/user-1000.slice/session-21.scope/cgroup.procs  | grep 352785
352785
# 退出新进程
ubuntu@server2:~$ exit
logout

##############################################################
# 查看新建cgroup后，cgroup节点的变化
# 创建进程，进程的cgroup namespace是新建出来的。
ubuntu@server2:~$ sudo unshare -Cm
# 查看当前进程的cgroup节点路径，发现跟父进程的节点路径不一样，变成/了
root@server2:/home/ubuntu# cat /proc/self/cgroup
0::/
# 当前进程的pid
root@server2:/home/ubuntu# echo $$
357039
# 验证当前进程cgroup并不再cgroup跟路径
root@server2:/home/ubuntu# cat /sys/fs/cgroup/cgroup.procs | grep 357039
# 验证当前进程cgroup依然在父进程的父进程的cgroup节点下
root@server2:/home/ubuntu# cat /sys/fs/cgroup/user.slice/user-1000.slice/session-21.scope/cgroup.procs | grep 357039
357039

# 重新挂载cgroup
root@server2:/home/ubuntu# umount /sys/fs/cgroup
root@server2:/home/ubuntu# mount -t cgroup2 none /sys/fs/cgroup
# 发现这回进程确实在cgroup根路径下了
root@server2:/home/ubuntu# cat /sys/fs/cgroup/cgroup.procs | grep 357039
357039
root@server2:/home/ubuntu# cat /sys/fs/cgroup/user.slice/user-1000.slice/session-21.scope/cgroup.procs | grep 357039
cat: /sys/fs/cgroup/user.slice/user-1000.slice/session-21.scope/cgroup.procs: No such file or directory

# 但新开窗口执行，发现进程其实还是在父进程相同的节点路径
ubuntu@server2:~$ cat /sys/fs/cgroup/user.slice/user-1000.slice/session-21.scope/cgroup.procs | grep 357039
357039
```
你可能想说，你这一长串都讲了个啥呀？我再来个精简版：
```bash
# 主机上
ubuntu@server2:~$ cat /proc/self/cgroup
0::/user.slice/user-1000.slice/session-21.scope

# 创建跟原namespace相同的进程
ubuntu@server2:~$ unshare
# 查看当前进程的cgroup节点路径，发现跟父进程的节点路径是一样的
ubuntu@server2:~$ cat /proc/self/cgroup
0::/user.slice/user-1000.slice/session-21.scope

# 创建进程，进程的cgroup namespace是新建出来的。
ubuntu@server2:~$ sudo unshare -Cm
# 查看当前进程的cgroup节点路径，发现跟父进程的节点路径不一样，变成/了
root@server2:/home/ubuntu# cat /proc/self/cgroup
0::/
```

可以看到新的cgroup namespace中，进程看到的cgroup节点路径是/，提供了一个虚拟的cgroup路径视图。

### 介绍
cgroup namespace为进程提供一个虚拟的cgroup节点路径。
在整个系统中存在cgroup树，每个进程都会属于一棵树中的唯一一个节点，一个进程如果新建了cgroup namespace，那么这个进程会把当前所属的节点当做是根节点，而自己进程的节点路径就变成根/了。这个路径就是通过/proc/pid/cgroup文件展示的。
cgroup目前存在两个版本，v1和v2, v1会存在多个cgroup树，比如memory树，cpu树，等等，对应到/proc/pid/cgroup文件就会有多行; v2只有一棵树，所有控制都在一棵树上解决，对应到/proc/pid/cgroup文件就会只有一行。
在没有cgroup namespace的时候，所有进程都以cgroup树的根作为根，也就是把系统的cgroup树的根看做/,其余节点都是/xx/xx的形式。但是有了cgroup namespace后，每个进程都可以有自己对于根/的定义。比如系统的树形结构是/a/b/c/d/e,那么我可以给某个进程设置c节点作为根/，这时候用/..表示b节点，/../..表示a节点，/../../..表示系统根，/d表示d节点，/d/e表示e节点。
给cgroup路径虚拟化成/，有3个作用：
1.是让进程看不到外部的cgroup树结构，防止信息泄露；
2.让进程迁移更容易，因为都从/开始就可以在不同机器上保持一致；
3.让进程没法操作外部的cgroup树，因为会把进程看到的根节点/挂载到/sys/fs/cgroup，所以操作不了外部cgroup节点了；

### 原理
我们首先来看cgroup在系统中是如何表示如何维护的，各个结构之间的关系是怎么样的：

![cgroupv1](/linkimage/namespace/cgroupv1.png)
在cgroup v1中，每种资源可以有独立的cgroup树，因此整个系统中会有多个cgroup树，每一棵树可以负责多个资源。
树的每个节点叫做cgroup，树的根节点叫cgroup_root，cgroup_root本身也承担普通cgroup节点的作用，也就是根节点也同时是一个cgroup。每个cgroup内部包含根节点cgroup_root的指针。
每个cgroup下可以挂任意多个task，cgroup v1中不区分进程和线程，都叫task。
每个进程包含一个css_set结构，其中包含全部cgroup_subsys_state,一个cgroup_subsys_state内部指向一个cgroup。

![cgroupv2](/linkimage/namespace/cgroupv2.png)
在cgroup v2中，整个系统只有一个全局的cgroup树，所有控制器都通过这棵树来配置。
树的每个节点也叫cgroup，根节点也叫cgroup_root, 根节点同时也是一个cgroup，cgroup内部指向cgroup_root。
cgroup v2节点下支持下挂pid和tid，可以支持对进程和线程的不同控制。
每个进程包含一个css_set,一个css_set中包含一个cgroup。
v2和v1在内核中代码是混在一起的，中间通过一些标志性的字段的判断来区分是v2还是v1，比如通过判断cgroup的root等于全局唯一的cgrp_dfl_root来判断这是一个v2的cgroup节点。

而不管v1还是v2，体现cgroup namespace的就是这个cgroup的节点路径，路径的获取途径是/proc/pid/cgroup文件。我们来看这里的显示逻辑。
首先在代码结构中`task_struc->cgroup`包含css_set结构，`task_struct->nsproxy->cgroup_ns->root_cset`中也包含一个css_set结构，这两个字段的意义分别是当前进程所在cgroup节点集合(集合的意思是针对有多棵树的情况)以及当前进程虚拟根cgroup节点的集合。后者也等于父进程的`task_struc->cgroup`。
```c
struct task_struct {
	...
	struct css_set __rcu		*cgroups;
	...
  struct nsproxy			*nsproxy;
  ...
}

struct nsproxy {
	...
	struct cgroup_namespace *cgroup_ns;
};

struct cgroup_namespace {
	...
	struct css_set          *root_cset;
};
```

打个比方，父节点的cgroup节点在/aa/bb/cc，那么父进程的`task_struc->cgroup`就指向/aa/bb/cc节点，父进程的`task_struct->nsproxy->cgroup_ns->root_cset`指向暂时不重要；接着父进程创建子进程，子进程的`task_struc->cgroup`和`task_struct->nsproxy->cgroup_ns->root_cset`都继承自父进程的`task_struc->cgroup`，指向/aa/bb/cc节点。接着如果我们把子进程移到/aa/xx/yy下，那么子进程的`task_struc->cgroup`指向/aa/xx/yy，而`task_struct->nsproxy->cgroup_ns->root_cset`依旧指向/aa/bb/cc。也就是进程的虚拟根cgroup节点不会发生变动。如图：

![cssset](/linkimage/namespace/twocssset.png)

看到这里我们先记下两个信息，一个是通过`task_struc->cgroup`可以获取一个进程当前所属的cgroup节点，另一个通过`task_struct->nsproxy->cgroup_ns->root_cset`可以获取当前进程虚拟根cgroup节点。
现在我们来看/proc/pid/cgroup的显示逻辑：
```c
int proc_cgroup_show(struct seq_file *m, struct pid_namespace *ns,
		     struct pid *pid, struct task_struct *tsk)
{
	...
	// 遍历每一个cgroup_root，如果是v1就会有多个，mem,cpu...
	// 如果是v2，就只有一个全局的。
	for_each_root(root) {
		...

		/// 显示cgroup路径的逻辑如下，经过整理和重命名，主要是这4行逻辑

		// root树下目标进程的cgroup节点
		target_process_cgroup = cset_cgroup_from_root(tsk->cgroup, root);
		// root树下当前进程的cgroup节点
		this_process_cgroup = cset_cgroup_from_root(current->nsproxy->cgroup_ns->root_cset, target_process_cgroup->root);
		// 计算出从this_process_cgroup到target_process_cgroup的相对路径
		kernfs_path_from_node(target_process_cgroup->kn, this_process_cgroup->kn, buf, buflen);
		seq_puts(m, buf);

		...
	}
	...
}
// 获取root树下指定节点的路径
static struct cgroup *cset_cgroup_from_root(struct css_set *cset,
					    struct cgroup_root *root)
{
	struct cgroup *res = NULL;
	...

	if (cset == &init_css_set) {
		// 系统中第0层的进程，也就是最上层的进程
		// 直接用root的cgroup，也就是最上层的cgroup
		res = &root->cgrp;
	} else if (root == &cgrp_dfl_root) {
		// cgroup v2中cgroup_只有全局一个，所有cgroup的root都是cgrp_dfl_root，
		// 所以每个进程只有一个cgroup就够了，所以直接返回进程对应的cgroup。
		res = cset->dfl_cgrp;
	} else {
		// 否则就得遍历进程的每个cgroup，返回指定root下的cgroup。
		struct cgrp_cset_link *link;

		list_for_each_entry(link, &cset->cgrp_links, cgrp_link) {
			...
			if (c->root == root) { //证明c在root树下
				res = c;
				break;
			}
		}
	}

	BUG_ON(!res);
	return res;
}
```
可以看到/proc/[pid]/cgroup显示的路径计算方式是
1.拿到目标进程的当前所属cgroup节点
2.拿到本进程虚拟根节点的cgroup节点
3.计算从2到1的相对路径

所以/proc/[pid]/cgroup显示的路径是从本进程的虚拟cgroup根节点到目的进程当前cgroup的相对路径，如果1和2相同，相对路径就是/。
```c
//https://github.com/torvalds/linux/blob/v5.19-rc2/fs/kernfs/dir.c#L144

	if (kn_from == kn_to)
		return strlcpy(buf, "/", buflen);
```

### 验证相对路径
这部分不感兴趣可以不看。这里会演示移动一个进程的cgroup后，/proc/[pid]/cgroup显示会如何变。
```bash
# 启动一个busybox容器，不停打印当前的cgroup路径
> kubectl run busycat --image busybox -- sh -c 'while true; do echo $$$$ && cat /proc/$$$$/cgroup; sleep 1;done'
# 查看容器的日志
> kubectl logs -f busycat
1
0::/
1
0::/
```
可以看到cgroup路径是/,这是因为k8s中每个容器都会加入独立的cgroup namespace。
随后我们在容器所在主机修改掉进程的cgroup：
```bash
> ps -ef | grep cgroup | grep -v grep
root     3117992 3117905  0 20:38 ?        00:00:01 sh -c while true; do echo $$ && cat /proc/$$/cgroup; sleep 1;done
> echo 3117992 | sudo tee -a /sys/fs/cgroup/jin/cgroup.procs
3117992
```
完成这一步操作后，这个进程的cgroup就被移动到了指定路径下，这个进程的`task_struc->cgroup`会随之改变，但是这个进程的`current->nsproxy->cgroup_ns->root_cset`不会变，于是在进程内，它看到的`/proc/$$/cgroup`将发生变化，它其中的路径是`current->nsproxy->cgroup_ns->root_cset`到`task_struc->cgroup`(这里即`/jin`)的相对路径。
在busycat的日志中会看到内容改变了
```
1
0::/../../../../jin
1
0::/../../../../jin
```
符合预期。

### 重新挂载cgroup
在最开始的演示中，我们看到如果不重新挂载cgroup，那么我们依然可以从/sys/fs/cgroup目录下去看出当前进程真实的cgroup节点位置。可以拆穿当前cgroup在根/下的谎言。所以我们必须执行命令来重现挂载cgroup。
```
root@server2:/home/ubuntu# umount /sys/fs/cgroup
root@server2:/home/ubuntu# mount -t cgroup2 none /sys/fs/cgroup
```
但是为了避免子进程挂载cgroup时对父进程产生影响，我们的子进程必须在创建cgroup namespace的同时创建一个mount namespace，这也是我们演示中执行的`sudo unshare -Cm`中包含`-m`参数的原因。


## user namespace

### 演示
```bash
# 读主机uid=1000
ubuntu@server2:~$ id
uid=1000(ubuntu) gid=1000(ubuntu) groups=1000(ubuntu),4(adm),20(dialout),24(cdrom),25(floppy),27(sudo),29(audio),30(dip),44(video),46(plugdev),118(netdev),121(lxd)
# 把当前进程加入新建的user namespace
ubuntu@server2:~$ unshare -U
# 再读一遍uid=65534
nobody@server2:~$ id
uid=65534(nobody) gid=65534(nogroup) groups=65534(nogroup)
# 读一下当前pid
nobody@server2:~$ echo $$
24307


# 新建一个窗口
# 读uid主机uid依然是1000
ubuntu@server2:~$ id
uid=1000(ubuntu) gid=1000(ubuntu) groups=1000(ubuntu),4(adm),20(dialout),24(cdrom),25(floppy),27(sudo),29(audio),30(dip),44(video),46(plugdev),118(netdev),121(lxd)
# 然后向刚才的进程的目录下的uid_map文件写入一个配置
ubuntu@server2:~$ echo "1 1000 1" | sudo tee  /proc/24307/uid_map
1 1000 1
# 读uid主机uid依然是1000
ubuntu@server2:~$ id
uid=1000(ubuntu) gid=1000(ubuntu) groups=1000(ubuntu),4(adm),20(dialout),24(cdrom),25(floppy),27(sudo),29(audio),30(dip),44(video),46(plugdev),118(netdev),121(lxd)

# 再到刚才的窗口读一遍uid=1
nobody@server2:~$ id
uid=1(daemon) gid=65534(nogroup) groups=65534(nogroup)

```
可以看到原先uid=1000,随后我们加入一个新的user namespace，发现uid变成65534了，随后我们在新窗口中写一个配置，然后发现刚才的uid又变成1了。
可以发现加入了user namespace的进程他内部的uid的变化跟主机的uid是不相关的。

### 介绍
user namespace隔离安全相关的属性，包括uid，gid，能力集等，一个用户在namespace外可能是普通用户，在ns内可以是root用户，因此在ns内可以具有最高权限。

### 原理
user_namespace没有放到task_struct下的nsproxy里面，因为他的使用比较特殊。
他放在task_struct.real_cred.user_ns，这是因为user namespace需要用来做进程的凭据，所以被放在在凭据相关的结构下。
注意task_struct下存在real_cred和cred两个字段，功能类似，real_cred定义该进程被其他对象操作的时候的上下文，cred定义该进程操作其他对象时候的上下文，后面讲解时不做区分。
```c
https://github.com/torvalds/linux/blob/master/include/linux/cred.h#L101

 * A task has two security pointers.  task->real_cred points to the objective
 * context that defines that task's actual details.  The objective part of this
 * context is used whenever that task is acted upon.
 *
 * task->cred points to the subjective context that defines the details of how
 * that task is going to act upon another object.  This may be overridden
 * temporarily to point to another security context, but normally points to the
 * same context as task->real_cred.
 */
struct cred {
	...
	kuid_t		uid;		/* real UID of the task */
	...
	kernel_cap_t	cap_inheritable; /* caps our children can inherit */
	kernel_cap_t	cap_permitted;	/* caps we're permitted */
	kernel_cap_t	cap_effective;	/* caps we can actually use */
	kernel_cap_t	cap_bset;	/* capability bounding set */
	kernel_cap_t	cap_ambient;	/* Ambient capability set */
	...
	struct user_namespace *user_ns; /* user_ns the caps and keyrings are relative to. */
	...
}

```

在real_cred结构下有3个主要部分：
一个是uid，代表该进程的真实uid，这也代表了该进程的真实权限，不会因为在子namespace中是root用户，他就可以操作外层的root权限的操作。
一个是几个cap_xxx字段，代表了这个进程拥有的能力，新usernamespace下的第一个进程拥有全部能力，所以对应的cap_xxx的值表示的是全部的能力，这个能力是指在新namespace下的能力。
一个是user_ns，主要完成gid和uid的映射。映射的意思是下层ns中的uid对应的是上层ns中的哪一个uid, 重点讲。
```c
struct user_namespace {
	struct uid_gid_map	uid_map;  // 映射pid
	struct uid_gid_map	gid_map;	// 映射gid
	...
	struct user_namespace	*parent; // 上级ns，指向level-1级的user_namespace
	int			level;	// namespace嵌套层级
	kuid_t			owner; // 父进程uid
	kgid_t			group; // 父进程gid
	...
} 
```
在user_namespace的结构中，parent和level的意义跟上面pid namespace的一样，parent代表上一层级的namespace，level代表这个user namespace处在第几层。
而uid_map和gid_map代表id的映射。
```c
struct uid_gid_map { /* 64 bytes -- 1 cache line */
	// 几项映射
	u32 nr_extents;
	union {
		struct uid_gid_extent extent[UID_GID_MAP_MAX_BASE_EXTENTS];
		struct {
			struct uid_gid_extent *forward;
			struct uid_gid_extent *reverse;
		};
	};
};
// 一个uid_gid_extent对象代表一项映射
struct uid_gid_extent {
	u32 first;
	u32 lower_first;
	u32 count;
};
```
这个结构里nr_extents代表有几项映射，`nr_extents<=UID_GID_MAP_MAX_BASE_EXTENTS`时，数据存到extent数组，大于extent时，数据存在forward-reverse之间，存到外部了。
每一项映射的格式是uid_gid_extent，这个结构的意思是把子ns中[first,first+count)的id区段映射到父ns中[lower_first+count)。这里有一个重要的信息需要注意，lower_first代表的是上一级的ns还是第0级的ns中的uid？我猜这里跟你的预想会有出入，这个lower_first是第0层的的uid，也就是ns中的uid直接映射到主机上的uid。我估计的理由是避免递归查找，如果指向的是上一级的uid，那么从第n层查找第0层需要不停查找每一层的映射规则，低效。而现在这样的设计只需要一次查找。同时还有个场景是计算NS-x下的uid对应另一个NX-y下的uid，任意两个ns。在当前设计下也只需要两次查找，一次从[NS-x]->[NS-0],另一次是[NS-0]->[NS-y]。也可以很好的完成需求，也就是说虽然user_namespace是多层嵌套的结构，但是uid-map是只有一层映射的，直接映射到第0层的uid。

了解了映射的规则，现在我们来看一下子ns中的进程如何获取到ns内部的uid
```c
SYSCALL_DEFINE0(getuid)
{
	// current_user_ns()->当前进程所在user ns
	// current_uid()->当前进程在主机的真实uid
	return from_kuid_munged(current_user_ns(), current_uid());
}
uid_t from_kuid_munged(struct user_namespace *targ, kuid_t kuid)
{
	uid_t uid;
	// 在namespace中查找uid是否被有效映射
	uid = from_kuid(targ, kuid);

	// 如果没有找到映射就返回固定的65534
	if (uid == (uid_t) -1)
		uid = overflowuid; // 65534
	return uid;
}
uid_t from_kuid(struct user_namespace *targ, kuid_t kuid)
{
	// 从nemespace中的uid_map中查找uid
	return map_id_up(&targ->uid_map, __kuid_val(kuid));
}

static u32 map_id_up(struct uid_gid_map *map, u32 id)
{
	...
	
	if (extent) // 如果能找到映射
		id = (id - extent->lower_first) + extent->first;
	else // 如果找不到映射
		id = (u32) -1;

	return id;
}
```
从这里我们可以看到如果用户真实uid在nsmespace 的uid_map映射中找到映射，那么就根据公式返回`ret_id=(real_id - extent->lower_first) + extent->first`。如果找不到映射就最终返回65534.
看到这里我们就可以看懂演示中的现象了，首先刚刚创建user namespace的时候，因为实际不存在uid_map映射，那么我们通过id命令查看uid的时候，返回了65534。接着我们向进程的uid_map文件写入一条映射，如此我们的uid就被映射成1了，再次执行id就返回1了。

### uid_map文件
这部分不感兴趣可以不看，不影响。
我们上面看到配置uid map是通过向uid_map文件写入映射来实现的，那么这里会有一个问题。
假如我们有3层namespace，主机>namespaceA>namespaceB,这时候namespaceA中的进程尝试去配置namespaceB的uid map，于是他准备执行`echo "id_b id_host 1" | sudo tee  /proc/pid/uid_map`，那么这时候他就迷茫了，因为他怎么知道要映射到主机上的哪个id_host呢，他是在namespace中的，他并不能感知到主机的id真实值有哪些。
答案是他不需要知道，他只要执行`echo "id_b id_a 1" | sudo tee  /proc/pid/uid_map`就可以了，他只要把目标namespace的uid映射到自己的uid就可以了。然后uid_map文件背后的写入逻辑会把id_a转成对应的id_host。同样当我们`cat /proc/pid/uid_map`的时候背后的读取逻辑也会把id_host转成id_a给我们显示，如果是在其他ns比如namespaceX中读那就会转成id_x。这部分逻辑的内核代码如下：
```c
static inline struct user_namespace *seq_user_ns(struct seq_file *seq)
{
	return seq->file->f_cred->user_ns;
}
static int uid_m_show(struct seq_file *seq, void *v)
{
	// ns代表文件所属的进程的ns，
	struct user_namespace *ns = seq->private;
	struct uid_gid_extent *extent = v;
	struct user_namespace *lower_ns;
	uid_t lower;

	// lower_ns代表打开文件这个进程所在的ns
	// 也表示要把真实uid转成lower_ns的uid
	lower_ns = seq_user_ns(seq);

	// 这个判断是说如果是在文件所属的ns内部的进程打开的文件，那么lower_ns往上跳一层
	// 也就是如果文件所属的ns内部的进程打开的文件，那么真实uid会转成父进程的uid
	// 不做这一转换的话，那看到的就是自己的uid转成自己的uid，没啥意义
	if ((lower_ns == ns) && lower_ns->parent)
		lower_ns = lower_ns->parent;

	// 这个过程就是把第0层的lower_first(即extent->lower_first)转成lower_ns这个ns下映射出来的uid。
	// 所以我们在不同ns下打开这个文件看到的可能是不同的。
	lower = from_kuid(lower_ns, KUIDT_INIT(extent->lower_first));

	seq_printf(seq, "%10u %10u %10u\n",
		extent->first,
		lower,
		extent->count);

	return 0;
}

```
逻辑已经发在注释中标出来了。我们来做一个演示和验证，看看是不是在不同ns下读到的uid_map文件内容是不同的。
```bash
#首先通过unshare创建两层新的user namespace，并以此打印出每一层的pid备用，并查看user namespace id证明在不同的ns中。这里unshare命令会带上-r参数，这样我们就不需要去手动写入uid_map映射了，自动帮我们写上了。

## 第0层
ubuntu@server2:~$ echo $$
1432594
ubuntu@server2:~$ sudo readlink /proc/1432594/ns/user
user:[4026531837]
ubuntu@server2:~$ unshare -r --user /bin/bash

# 第1层
root@server2:~# echo $$
1434585
root@server2:~# readlink /proc/1434585/ns/user
user:[4026532618]
root@server2:~# unshare -r --user /bin/bash

# 第2层
root@server2:~# echo $$
1434704
root@server2:~# readlink /proc/1434704/ns/user
user:[4026532689]

# 随后我们从不同的namespace层次，去查看第2层的uid_map文件，看看每一层看到的是不是一样
# 新开一个窗口，从第0层看
ubuntu@server2:~$ cat /proc/1434704/uid_map
         0       1000          1
# 从第1层看，需要先通过nsenter进入指定进程的user namespace
ubuntu@server2:~$ nsenter --user -t 1434585 --preserve-credentials bash
root@server2:~#  cat /proc/1434704/uid_map
         0          0          1
# 从第2层看，需要先通过nsenter进入指定进程的user namespace
ubuntu@server2:~$ nsenter --user -t 1434704 --preserve-credentials bash
root@server2:~# cat /proc/1434704/uid_map
         0          0          1
```
可以看到符合我们的结论，在第0层，lower_first值对应了第0层的uid，ubuntu用户的uid就是1000。第1层看到的lower_first值也是对应了第1层的uid=0。第2层就是ns自己这个ns内，那lower_first对应（2-1)层的uid=0。符合我们的预期。



## 参考
[namespace API](https://icloudnative.io/posts/introduction-to-linux-namespaces-part-1-api/)
[cred.h](https://github.com/torvalds/linux/blob/master/include/linux/cred.h#L101)
[nsproxy.h](https://github.com/torvalds/linux/blob/v5.19-rc2/include/linux/nsproxy.h#L31)
[user_namespace.h](https://github.com/torvalds/linux/blob/v5.19-rc2/include/linux/user_namespace.h#L66)
[clone(2) — Linux manual page](https://man7.org/linux/man-pages/man2/clone.2.html)
[unshare(1) — Linux manual page](https://man7.org/linux/man-pages/man1/unshare.1.html)
[setns(2) — Linux manual page](https://man7.org/linux/man-pages/man2/setns.2.html)
[vdso(7) — Linux manual page](https://man7.org/linux/man-pages/man7/vdso.7.html)
[网络信息服务](https://docs.freebsd.org/doc/7.1-RELEASE/usr/share/doc/zh_CN/books/handbook/network-nis.html)
[network namespace 简介](https://cizixs.com/2017/02/10/network-virtualization-network-namespace/)
[time_namespaces(7) — Linux manual page](https://man7.org/linux/man-pages/man7/time_namespaces.7.html)
[Internal Commands and Builtins](https://edoras.sdsu.edu/doc/bash/abs/internal.html)
[kernel: Introduce Time Namespace](https://lore.kernel.org/lkml/20191112012724.250792-3-dima@arista.com/t/)
[mnt_namespace的拷贝过程解读](http://blog.chinaunix.net/uid-26552184-id-5842494.html)
[Linux Namespace系列user namespace](https://blog.csdn.net/dolphin98629/article/details/79172005)
[理解user namespace](https://www.junmajinlong.com/virtual/namespace/user_namespace/)
[user namespace internals](https://terenceli.github.io/%E6%8A%80%E6%9C%AF/2019/12/17/user-namespace)
[User Namespace 详解](https://blog.csdn.net/pwl999/article/details/115186689)
[Pid Namespace 原理与源码分析](https://zhuanlan.zhihu.com/p/335171876)
[Linux 容器化技术](https://www.ffutop.com/posts/2019-06-18-understand-kernel-12/)
[IPC Namespace 详解](https://tinylab.org/ipc-namespace/)
[Cgroup 整体介绍](http://119.23.219.145/posts/%E5%AE%B9%E5%99%A8-cgroup-%E6%95%B4%E4%BD%93%E4%BB%8B%E7%BB%8D/)
[Cgroup - 从CPU资源隔离说起](https://zorrozou.github.io/docs/books/cgroup_linux_cpu_control_group.html)
[浅谈 Cgroups V2](https://www.infoq.cn/article/hbqqfeyqxzhnes5jipqt)
[Linux的cgroup详细介绍](http://www.freeoa.net/osuport/sysadmin/linux-cgroup-detail_3446.html)
[Organizing Processes and Threads](https://www.kernel.org/doc/html/v4.18/admin-guide/cgroup-v2.html#organizing-processes-and-threads)
[资源限制cgroup v1和cgroup v2的详细介绍](https://www.lijiaocn.com/%E6%8A%80%E5%B7%A7/2019/01/28/linux-tool-cgroup-detail.html#cgroups-v2%E7%BA%BF%E7%A8%8B%E6%A8%A1%E5%BC%8Fthread-mode)

