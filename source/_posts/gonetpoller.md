---
title: golang netpoller
tags:
  - 狗狼
categories:
  - 代码
date: 2019-06-08 17:34:46
updated: 2019-06-08 17:34:46
---

# Golang netpoller

本文主要记录go是如何处理网络IO的，以及这么做的目的和原理，穿插一部分源码跟踪。同时对比go的线程模型与别的通用线程模型的差别。

## 网络阻塞

在Go的实现中，所有IO都是阻塞调用的，Go的设计思想是程序员使用阻塞式的接口来编写程序，然后通过goroutine+channel来处理并发。因此所有的IO逻辑都是直来直去的，先xx，再xx,  你不再需要回调，不再需要future，要的仅仅是step by step。这对于代码的可读性是很有帮助的。

在[go scheduler](https://yizhi.ren/2019/06/03/goscheduler/)一文中我们讲述了go如何处理阻塞的系统调用，当goroutine调用阻塞的系统调用时，这个goroutine和物理线程都会一直处于阻塞状态，不能处理别的任务；而当goroutine调用channel阻塞时，goroutine会阻塞而物理线程不会阻塞，会继续执行别的任务。所以如果我们基于操作系统提供的阻塞的IO接口来构建golang的应用，我们就必须为每个处于阻塞读写状态的客户端建立一个线程。当面对高并发的包含大量处于阻塞IO状态的客户端时，将浪费大量的资源。而如果能够像channel那样处理，就可以避免资源浪费。

Go的解决方案是如channel一般在用户层面(程序员层面)保留阻塞的接口，但是在Runtime内部采用非阻塞的异步接口来与操作系统交互。

这里面关键的角色就是netpoller。

<!-- more -->

## netpoller

netpoller的工作就是成为同步（阻塞）IO调用和异步（非阻塞）IO调用之间的桥梁。

```
这里我为了简化概念，特意混淆了同步异步跟阻塞非阻塞的关系，使得二者等价得来看待，默认同步即使用了阻塞IO，异步即使用了非阻塞IO。
其实同步异步和阻塞非阻塞是有一些差异的，同步确实绝对的关联阻塞，但异步在某种场景下可以通过阻塞IO来实现的。
比如linux的文件IO都是阻塞的，那些异步IO库就会把读写文件的请求扔到一个线程池中去阻塞的读写，完成之后再进行回调。

下面的总结来自：https://github.com/calidion/calidion.github.io/issues/40

1. 同步异步分IO与代码两种。
2. 在IO上同步IO等于阻塞IO，异步IO等于非阻塞IO
3. 在代码上同步代码等同于调用同步IO，等同于调用阻塞IO；但并不表示异步代码一定有异步IO调用，从而也无法确定是不是一定是非阻塞IO。
```

### 同步转异步调度

当goroutine发起一个同步调用比如下面的Read函数，经过一系列的调用，最后会进入gopark函数，gopark将当前正在执行的goroutine状态保存起来，然后切换到新的堆栈上执行新的goroutine。由于当前goroutine状态是被保存起来的，因此后面可以被恢复。这样调用Read的goroutine以为一直同步阻塞到现在，其实内部是异步完成的。

```c++
func (fd *netFD) Read(p []byte) (n int, err error) {
	n, err = fd.pfd.Read(p)
	runtime.KeepAlive(fd)
	return n, wrapSyscallError("read", err)
}
```

```c++
// Read implements io.Reader.
func (fd *FD) Read(p []byte) (int, error) {
	if err := fd.readLock(); err != nil {
		return 0, err
	}
	defer fd.readUnlock()
	if len(p) == 0 {
		// If the caller wanted a zero byte read, return immediately
		// without trying (but after acquiring the readLock).
		// Otherwise syscall.Read returns 0, nil which looks like
		// io.EOF.
		// TODO(bradfitz): make it wait for readability? (Issue 15735)
		return 0, nil
	}
	if err := fd.pd.prepareRead(fd.isFile); err != nil {
		return 0, err
	}
	if fd.IsStream && len(p) > maxRW {
		p = p[:maxRW]
	}
	for {
		n, err := syscall.Read(fd.Sysfd, p)
		if err != nil {
			n = 0
			if err == syscall.EAGAIN && fd.pd.pollable() {
				if err = fd.pd.waitRead(fd.isFile); err == nil {
					continue
				}
			}

			// On MacOS we can see EINTR here if the user
			// pressed ^Z.  See issue #22838.
			if runtime.GOOS == "darwin" && err == syscall.EINTR {
				continue
			}
		}
		err = fd.eofError(n, err)
		return n, err
	}
}

```

```c++
func (pd *pollDesc) waitRead(isFile bool) error {
	return pd.wait('r', isFile)
}
```

```c++
func (pd *pollDesc) wait(mode int, isFile bool) error {
	if pd.runtimeCtx == 0 {
		return errors.New("waiting for unsupported file type")
	}
	res := runtime_pollWait(pd.runtimeCtx, mode)
	return convertErr(res, isFile)
}
```

```c++
//go:linkname poll_runtime_pollWait internal/poll.runtime_pollWait
func poll_runtime_pollWait(pd *pollDesc, mode int) int {
	err := netpollcheckerr(pd, int32(mode))
	if err != 0 {
		return err
	}
	// As for now only Solaris uses level-triggered IO.
	if GOOS == "solaris" {
		netpollarm(pd, mode)
	}
	for !netpollblock(pd, int32(mode), false) {
		err = netpollcheckerr(pd, int32(mode))
		if err != 0 {
			return err
		}
		// Can happen if timeout has fired and unblocked us,
		// but before we had a chance to run, timeout has been reset.
		// Pretend it has not happened and retry.
	}
	return 0
}

```

```c++
func netpollblock(pd *pollDesc, mode int32, waitio bool) bool {
	gpp := &pd.rg
	if mode == 'w' {
		gpp = &pd.wg
	}

	// set the gpp semaphore to WAIT
	for {
		old := *gpp
		if old == pdReady {
			*gpp = 0
			return true
		}
		if old != 0 {
			throw("runtime: double wait")
		}
		if atomic.Casuintptr(gpp, 0, pdWait) {
			break
		}
	}

	// need to recheck error states after setting gpp to WAIT
	// this is necessary because runtime_pollUnblock/runtime_pollSetDeadline/deadlineimpl
	// do the opposite: store to closing/rd/wd, membarrier, load of rg/wg
	if waitio || netpollcheckerr(pd, mode) == 0 {
		gopark(netpollblockcommit, unsafe.Pointer(gpp), "IO wait", traceEvGoBlockNet, 5)
	}
	// be careful to not lose concurrent READY notification
	old := atomic.Xchguintptr(gpp, 0)
	if old > pdWait {
		throw("runtime: corrupted polldesc")
	}
	return old == pdReady
}

```

```c++
// Puts the current goroutine into a waiting state and calls unlockf.
// If unlockf returns false, the goroutine is resumed.
// unlockf must not access this G's stack, as it may be moved between
// the call to gopark and the call to unlockf.
func gopark(unlockf func(*g, unsafe.Pointer) bool, lock unsafe.Pointer, reason string, traceEv byte, traceskip int) {
	mp := acquirem()
	gp := mp.curg
	status := readgstatus(gp)
	if status != _Grunning && status != _Gscanrunning {
		throw("gopark: bad g status")
	}
	mp.waitlock = lock
	mp.waitunlockf = *(*unsafe.Pointer)(unsafe.Pointer(&unlockf))
	gp.waitreason = reason
	mp.waittraceev = traceEv
	mp.waittraceskip = traceskip
	releasem(mp)
	// can't do anything that might move the G between Ms here.
	mcall(park_m)
}
```

```c++
// park continuation on g0.
func park_m(gp *g) {
	_g_ := getg()

	if trace.enabled {
		traceGoPark(_g_.m.waittraceev, _g_.m.waittraceskip)
	}

	casgstatus(gp, _Grunning, _Gwaiting)
	dropg()

	if _g_.m.waitunlockf != nil {
		fn := *(*func(*g, unsafe.Pointer) bool)(unsafe.Pointer(&_g_.m.waitunlockf))
		ok := fn(gp, _g_.m.waitlock)
		_g_.m.waitunlockf = nil
		_g_.m.waitlock = nil
		if !ok {
			if trace.enabled {
				traceGoUnpark(gp, 2)
			}
			casgstatus(gp, _Gwaiting, _Grunnable)
			execute(gp, true) // Schedule it back, never returns.
		}
	}
	schedule()
}
```

### 异步调度回来

那什么时候G被调度回来呢？

```c++
schedule() -> findrunnable() -> netpoll()
```

```c++
// polls for ready network connections
// returns list of goroutines that become runnable
func netpoll(block bool) *g {
	if epfd == -1 {
		return nil
	}
	waitms := int32(-1)
	if !block {
		waitms = 0
	}
	var events [128]epollevent
retry:
	n := epollwait(epfd, &events[0], int32(len(events)), waitms)
	if n < 0 {
		if n != -_EINTR {
			println("runtime: epollwait on fd", epfd, "failed with", -n)
			throw("runtime: netpoll failed")
		}
		goto retry
	}
	var gp guintptr
	for i := int32(0); i < n; i++ {
		ev := &events[i]
		if ev.events == 0 {
			continue
		}
		var mode int32
		if ev.events&(_EPOLLIN|_EPOLLRDHUP|_EPOLLHUP|_EPOLLERR) != 0 {
			mode += 'r'
		}
		if ev.events&(_EPOLLOUT|_EPOLLHUP|_EPOLLERR) != 0 {
			mode += 'w'
		}
		if mode != 0 {
			pd := *(**pollDesc)(unsafe.Pointer(&ev.data))

			netpollready(&gp, pd, mode)
		}
	}
	if block && gp == 0 {
		goto retry
	}
	return gp.ptr()
}
```

在某一次调度G的过程中，处于就绪状态的FD对应的G就会被调度回来。

### 何时注册的netpoller

在初始化的时候，最终调到netpollopen，里面调了epollctrl注册了fd上去。

```
func (fd *netFD) init() error {
	return fd.pfd.Init(fd.net, true)
}
```

```
func (fd *FD) Init(net string, pollable bool) error {
	// We don't actually care about the various network types.
	if net == "file" {
		fd.isFile = true
	}
	if !pollable {
		fd.isBlocking = true
		return nil
	}
	return fd.pd.init(fd)
}

```

```
func (pd *pollDesc) init(fd *FD) error {
	serverInit.Do(runtime_pollServerInit)
	ctx, errno := runtime_pollOpen(uintptr(fd.Sysfd))
	if errno != 0 {
		if ctx != 0 {
			runtime_pollUnblock(ctx)
			runtime_pollClose(ctx)
		}
		return syscall.Errno(errno)
	}
	pd.runtimeCtx = ctx
	return nil
}
```

```
//go:linkname poll_runtime_pollOpen internal/poll.runtime_pollOpen
func poll_runtime_pollOpen(fd uintptr) (*pollDesc, int) {
	pd := pollcache.alloc()
	lock(&pd.lock)
	if pd.wg != 0 && pd.wg != pdReady {
		throw("runtime: blocked write on free polldesc")
	}
	if pd.rg != 0 && pd.rg != pdReady {
		throw("runtime: blocked read on free polldesc")
	}
	pd.fd = fd
	pd.closing = false
	pd.seq++
	pd.rg = 0
	pd.rd = 0
	pd.wg = 0
	pd.wd = 0
	unlock(&pd.lock)

	var errno int32
	errno = netpollopen(fd, pd)
	return pd, int(errno)
}
```

```
func netpollopen(fd uintptr, pd *pollDesc) int32 {
	var ev epollevent
	ev.events = _EPOLLIN | _EPOLLOUT | _EPOLLRDHUP | _EPOLLET
	*(**pollDesc)(unsafe.Pointer(&ev.data)) = pd
	return -epollctl(epfd, _EPOLL_CTL_ADD, int32(fd), &ev)
}
```

上面可以看到fd在初始化的时候就注册了，这个时候Read()还没调用，waitRead()也没有调用，那么这时候在read和waitread调用之前有数据到来G被激活的话会怎么样呢？

```
netpoll() -> netpollready() -> netpollunblock()
```

```
func netpollunblock(pd *pollDesc, mode int32, ioready bool) *g {
	gpp := &pd.rg
	if mode == 'w' {
		gpp = &pd.wg
	}

	for {
		old := *gpp
		if old == pdReady {
			return nil
		}
		if old == 0 && !ioready {
			// Only set READY for ioready. runtime_pollWait
			// will check for timeout/cancel before waiting.
			return nil
		}
		var new uintptr
		if ioready {
			new = pdReady
		}
		if atomic.Casuintptr(gpp, old, new) {
			if old == pdReady || old == pdWait {
				old = 0
			}
			return (*g)(unsafe.Pointer(old))
		}
	}
}

```

netpollready负责把多个活跃的G串起来，netpollunblock则把G状态更新为pdReady并返回该G。

可以看到由于waitRead调用前rg，wg字段是空的，所以这里old值是0，所以netpollunblock返回空指针，netpollready就不会把空指针串进去。

所以waitread之前G被激活也不会有问题。



## 线程模型

写过select和epoll的都能看出来go的netpoller就是基于epoll（linux上）的多路复用机制写出来的，基于epoll的线程设计要么是reactor，要么是proactor，而从go的代码可以看出，go的netpoll就是一种reactor的模型。使用reactor的线程模型通常包括下面的三大类：

单loop：

![single loop](/linkimage/gonetpoller/threadmodel1.png)

一组loop：

![多loop](/linkimage/gonetpoller/threadmodel2.png)

双loop组：

![双loop组](/linkimage/gonetpoller/threadmodel3.png)



图片来自[Netty 系列之 Netty 线程模型](https://www.infoq.cn/article/netty-threading-model)

三种模型依次适用于更大系统规模和更高复杂度的系统，golang由于是全局的netpoller，只有一个，因此属于第一种模型，当然go使用协程来调度任务，使得它在线程的调度上是优于上图任何一种的，但是在网络IO的性能上go并没有什么优势。



## 单loop的不足

线程模型我们说适合的是最好的，它取决你的规模，你的业务模型等。但是就像libev作者说的`one loop per thread is usually a good model`([@Chapter:THREADS AND COROUTINES](http://para.se/perldoc/EV/libev.html)),我也认同一个线程一个loop的设计。

原因包括：多个loop可以更好的进行负载的分配、类型的分类，把连接均分到不同的loop可以做到负载均衡，而把不同类型的连接分到不同的loop就可以很好的进行连接分类；多个loop可以提升连接的响应速度，应对一些突发IO，可以降低延迟，在高并发的场景下会更有优势。

采用`one loop per thread`设计的网络框架，C++中有Muduo，Java中有Netty，等。都是非常优秀的网络框架，采用单loop的go在这方面就会面临这方面的劣势，我认为go在这方面是需要有所改进的。



## 参考

[Golang netpoll](http://likakuli.com/post/2018/06/06/golang-network/)

[The Go netpoller](https://morsmachine.dk/netpoller)

[Netty 系列之 Netty 线程模型](https://www.infoq.cn/article/netty-threading-model)

[Go语言源码笔记](https://cloud.tencent.com/developer/article/1234360)