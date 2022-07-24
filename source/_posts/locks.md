---
title: 不同形式的锁
tags:
  - 系统
categories:
  - 代码
date: 2019-09-03 17:34:46
updated: 2019-09-03 17:34:46
---

# 不同形式的锁

最近发现锁的类型真是多种多样，好多还是第一次见，我就在这里记录一下。

## RCU

RCU即read-copy-update.一种不阻塞读线程，只阻塞写线程的同步方式。

写线程如果有多个要自己做好互斥，一个时间只能有一个写线程。写线程严格执行R-C-U三步操作，但在第三步操作完的时候，因为把原来的值给更新掉了，原来旧的值就需要释放，那么持有了原来旧的值的读线程必须全部操作完成才行。这里所说的操作的旧值新值都是指针，只有指针才可以直接的确保原子性。

所以这里有个关键步骤是synchronize_rcu()，位于U之后和释放旧指针之前。synchronize_rcu的底层实现我不懂，它的原理大概是说等待所有cpu都调度一遍，就可以确保旧的读线程都操作完成了。为什么都调度一遍就可以确保都操作完了呢？因为所有的读操作都要求添加以下语句：

```c
rcu_read_lock(); // 禁止抢占
p = rcu_dereference(gp); // rcu_dereference主要是加内存屏障
if (p != NULL) {
    do_something_with(p->a, p->b, p->c);
}
rcu_read_unlock(); // 允许抢占
```
<!-- more -->

rcu_read_lock和rcu_read_unlock会组成RCU临界区，这个临界区是不会被中断的，所以只要执行了就一定是执行完成的。那么每个cpu都发生了调度，也就意味着每个正在操作的读，都结束了。

下面是关于写线程的完整的例子：

```c
// 来自 http://www.hyuuhit.com/2018/11/08/rcu/
struct foo {
    int a;
    int b;
    int c;
};
struct foo *gp = NULL;

p = rcu_dereference(gp); // R操作，rcu_dereference主要是加内存屏障
if (p == NULL) {
    /* 做适当操作 */
}

q = kmalloc(sizeof(*p), GFP_KERNEL); 
*q = *p; // C操作
q->b = 2;
q->c = 3;
rcu_assign_pointer(gp, q); // U操作,rcu_assign_pointer主要是加内存屏障
synchronize_rcu(); // U之后要等待持有了旧的gp的线程结束
kfree(p);
```

另外如果对关于释放老指针有兴趣的，可以参考下这段话：

```
来自： http://www.embeddedlinux.org.cn/html/yingjianqudong/201404/07-2830.html

在释放老指针方面，Linux内核提供两种方法供使用者使用，一个是调用call_rcu,另一个是调用synchronize_rcu。前者是一种异步 方式，call_rcu会将释放老指针的回调函数放入一个结点中，然后将该结点加入到当前正在运行call_rcu的处理器的本地链表中，在时钟中断的 softirq部分（RCU_SOFTIRQ）， rcu软中断处理函数rcu_process_callbacks会检查当前处理器是否经历了一个休眠期(quiescent，此处涉及内核进程调度等方面的内容)，rcu的内核代码实现在确定系统中所有的处理器都经历过了一个休眠期之后(意味着所有处理器上都发生了一次进程切换，因此老指针此时可以被安全释放掉了)，将调用call_rcu提供的回调函数。
synchronize_rcu的实现则利用了等待队列，在它的实现过程中也会向call_rcu那样向当前处理器的本地链表中加入一个结点，与 call_rcu不同之处在于该结点中的回调函数是wakeme_after_rcu，然后synchronize_rcu将在一个等待队列中睡眠，直到系统中所有处理器都发生了一次进程切换，因而wakeme_after_rcu被rcu_process_callbacks所调用以唤醒睡眠的 synchronize_rcu，被唤醒之后，synchronize_rcu知道它现在可以释放老指针了。

所以我们看到，call_rcu返回后其注册的回调函数可能还没被调用，因而也就意味着老指针还未被释放，而synchronize_rcu返回后老指针肯定被释放了。所以，是调用call_rcu还是synchronize_rcu，要视特定需求与当前上下文而定，比如中断处理的上下文肯定不能使用 synchronize_rcu函数了。 
```





## RW  lock

关于读写锁，大家应该相对还是比较熟悉的，功能是如果写线程持有锁，那么其他写和读线程都不能再加锁成功；如果是读线程持有锁，那么其他读线程还是可以加锁成功，写线程不能加锁成功。

我们已gcc的源码来分析看他是怎么实现的。

```c
  class __shared_mutex_cv
  {

    mutex		_M_mut; // 内部用的互斥量，保护_M_state
    condition_variable	_M_gate1; // 用来等待当前的写线程完成
    condition_variable	_M_gate2; // 用来等待当前的读线程完成
    
    // 0x80 00 00 00代表加了写锁，< 0x80 00 00 00代表当前加的读锁的个数，0代表没有被加锁
    unsigned		_M_state;
    
    void lock();  // 加写锁
    void unlock(); // 解写锁
    void lock_shared(); // 加读锁
    void unlock_shared(); // 解读锁
  }
```

可以看到内部使用了一个互斥量，所以读写锁内部不是有两个互斥量，而是只有一个的。

另外他使用了一个状态值来表示当前加的是读锁还是解锁，这点你看原理前估计是没有想到的。0代表无锁，最高位置为1代表加了写锁，其他值代表当前加了读锁的个数。

总是里面定义了两个gate，顾名思义是两个关卡，写锁要经过两道，读锁则只需经过一道。

```c
    void lock()
    {
      unique_lock<mutex> __lk(_M_mut);
      _M_gate1.wait(__lk, [=]{ return !_M_write_entered(); }); // 等待写操作完成，但是可能还有读线程
      _M_state |= _S_write_entered; // 加上写锁标识，把后续的读和写线程挡在gate1外面
      _M_gate2.wait(__lk, [=]{ return _M_readers() == 0; }); // 这一步等待读操作完成
    }
```

如上是加写锁的操作，就是等待写完成，再等待读完成。为了防止读操作源源不断，导致写操作饿死，在等待读完成前会置上标志，让后面的读（和写）保持等待。

```c
    void unlock()
    {
      lock_guard<mutex> __lk(_M_mut);
      __glibcxx_assert( _M_write_entered() );
      _M_state = 0;
      _M_gate1.notify_all(); // 唤醒gate1外面的读写线程，这里读线程还是有抢占的机会的
    }
```

如上是解写锁的操作，和简单，把状态置为未加锁，然后唤醒gate1中等待的线程。

```c
    void lock_shared()
    {
      unique_lock<mutex> __lk(_M_mut);
      // 等待写操作完成，且等待读操作个数没有满(_S_max_readers=0x80000000-1)
      _M_gate1.wait(__lk, [=]{ return _M_state < _S_max_readers; });
      ++_M_state;
    }
```

如上是加读锁，跟加写锁类似，需要等待写操作完成，_M_state < _S_max_readers 一方面可以判断没有加写锁，另一方面还可以判断当前读线程没有满。

```c
    void unlock_shared()
    {
      lock_guard<mutex> __lk(_M_mut);
      __glibcxx_assert( _M_readers() > 0 );
      auto __prev = _M_state--; // 读线程个数减1
      if (_M_write_entered()) // 如果有写线程在等待了
	    {
	      if (_M_readers() == 0) // 如果自己是最后一个活跃的读线程
	        _M_gate2.notify_one(); // 唤醒一个写线程
	    }
      else // 没有写线程等待
	    {
	      if (__prev == _S_max_readers) // 如果原先读线程个数是满的
	        _M_gate1.notify_one(); // 唤醒一个读线程
	    }
    }
 
```

如上是解锁读锁的过程，除了把_M_state减1外还要负责在以下情况下唤醒别的线程，当自己是最后一个读线程且已经有写线程在等待了，就唤醒写线程；当原先读线程数是满的时候，且当前没有写线程等待，就唤醒一个读线程。



## seqlock

```c
typedef struct {
	struct seqcount seqcount;
	spinlock_t lock;
} seqlock_t;
```

seqlock是一种针对读写有不同优先权的锁，写的优先权要大于读的优先权。

那多个线程写的时候呢，可以看到结构体中有个spinlock，写线程必须先锁住spinlock，这样确保只有一个线程在写。

那如果写的时候有线程在读呢，不管，照样写。

那读的这个线程怎么办呢，读一半被改了怎么办。这里就用到了结构体中的seqcount。

seqcount只有写线程会进行修改，每次拿到spinlock之后立即seqcount++，在解锁spinlock前又再次seqcount++。同时读线程在开始读之前会取一次seqcount，在读完会再取一次seqcount，如果两次值一样就说明中间没有写线程进入[下面还会解释]。否则就从头开始读。

所以读线程的代码就是像下面这样的，

```c
// 来自linux源码
ktime_t intel_engine_get_busy_time(struct intel_engine_cs *engine)
{
	// ...

	do {
		seq = read_seqbegin(&engine->stats.lock); // 这里读seq
		total = __intel_engine_get_busy_time(engine); // 这里读临界区的数据
	} while (read_seqretry(&engine->stats.lock, seq)); // 这里检查seq是否改变

	return total;
}
```

关于写线程的代码是像下面这样的，

```c
// 来自linux源码
static inline void write_seqlock(seqlock_t *sl)
{
	spin_lock(&sl->lock);
	write_seqcount_begin(&sl->seqcount); // 这里会执行seqcount++
}

static inline void write_sequnlock(seqlock_t *sl)
{
	write_seqcount_end(&sl->seqcount);// 这里会执行seqcount++
	spin_unlock(&sl->lock);
}
```

注意，这里你可能会提几个问题：

`读线程会不会因为cpu缓存而取不到最新的seqcount值？`不会的，跟踪读取seqcount的代码，可以发现读取是使用的volatile read，可以做到总是取最新值。

`两个写线程之间会不会因为cpu缓存看不到对方线程增加的seqcount？`比如原来seqcount=0。A线程进出临界区对seqcount加了2，B线程进出临界区也加了2，如果加的只是cpu缓存中的seqcount，那最终seqcount就只是2不是4。也不会的，因为锁都自带内存屏障，他可以做到，当B线程发现A已经解锁的时候，B也一定能发现A解锁前的那些指令已经执行完了，也即可以发现seqcount已经被++过了。

`为什么写线程进出临界区都要加1？`你想一下如果只加一次，不管是进入加还是离开加，都可能让读线程处在写线程的过程当中，感知不到写线程的存在：

```
--> begin write      
    write              --> begin read
    write                  read   
    write              --> end read
    write
--> end write
```

甚至是进入和离开都写，一样会存在上图的问题，读线程会感知不到写线程的存在。

但是进入和离开都写有一个重要的特性是，当当前没有写线程的时候，seqcount总是偶数，所以读线程这里要做的是只有在seqcount是偶数的时候才开始读，然后读完的时候只要seqcount变化了就重新等待seqcount是偶数再读。这就可以解决感知不到写线程的问题了。

可以看出来这个逻辑对读线程是比较不公平的，可能需要频繁重试，不过这本来也就是这个锁的特点，他适合于write操作较少，但是又对write性能要求高的场景。

此外这个锁还有个致命的缺点，就是由于在写线程存在的时候，读线程还是会进入临界区，因此如果此时写线程释放了某个指针，那么读线程可能就会触发空指针的异常。因此该锁只能用来锁定简单的数据类型。





## 参考

[透过 Linux 内核看无锁编程](https://www.ibm.com/developerworks/cn/linux/l-cn-lockfree/index.html)

[Linux RCU 内核同步机制](http://www.hyuuhit.com/2018/11/08/rcu/)

[再谈Linux内核中的RCU机制](http://www.embeddedlinux.org.cn/html/yingjianqudong/201404/07-2830.html)