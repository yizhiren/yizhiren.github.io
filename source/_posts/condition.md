---
title: condition_variable为什么需要mutex
tags:
  - 西佳佳
categories:
  - 代码
date: 2016-11-14 17:34:46
updated: 2016-11-14 17:34:46
---

## condition_variable 

### 简介
在头文件< condition_variable >中，顾名思义是一个条件变量，主要功能是阻塞线程直到另一个线程把你唤醒。

条件两个字看起来似乎是指，在另一个线程中满足了条件，才把你唤醒；然而如果仅仅如此的话信号量就能满足要求了。

所以条件二字更体现在你需要满足更具体的"条件"才能被唤醒。

来看一个简单的例子：

<!-- more -->

```

#include <iostream>             
#include <thread>               
#include <mutex>                
#include <condition_variable>   


std::mutex mtx; 
std::condition_variable cv; 
bool ready = false; 

void wait_ready()
{
    std::unique_lock <std::mutex> lck(mtx);
	
    std::cout << "before wait." << std::endl;
    cv.wait(lck,[](){return ready;}); 
	std::cout << "after wait." << std::endl;
    
}

void make_ready()
{
    std::unique_lock <std::mutex> lck(mtx);
    ready = true;
	
    std::cout << "before notify." << std::endl;
    cv.notify_all(); 
    std::cout << "after notify." << std::endl;
}


int main(int argc, char** argv) {
	std::thread wait_t(wait_ready);
	std::thread ready_t(make_ready);
	
	wait_t.join();
	ready_t.join();
	return 0;
}

/*** output:
before wait.
before notify.
after notify.
after wait.
***/

```

可以看到这里wait_ready()等待make_ready()的唤醒后才往下执行。这是condition_variable的典型用法，一边wait一边notify。


### wait函数的参数
我们一步一步说，wait函数可以有两个参数，第一个参数是一个mutex类型，也就是一个锁；第二个参数是一个返回类型是bool的函数，意思是直到这个函数返回true才往下执行。可以放心的是它不是通过死循环来判断这个条件的，不然还需要另一边notify干嘛。wait会在刚进入时判断这个函数返回值，如果false就睡眠，每次被唤醒后再次判断。

带来疑问的是第一个参数是否有必要，为什么我们要传入一个锁呢。很多同学说是为了保护类内部的资源，因为可以想象这里面应该会有一个队列存放着所有wait的线程，wait和notify的时候都会来访问这个队列，所以至少这个队列是需要一个锁来保护的。理由都对，结论却不对。内部资源确实是需要保护，但是难道它不能再内部创建一个锁来使用吗，它的实现也确实是用了内部的锁。所以这个lock一定不是用来保护内部的资源。那又是为何呢？


### 不用锁会遇到什么问题
我们只要知道不用锁会遇到的问题也就知道为什么用了。

我们首先把cv.wait( lck,\[\](  ){return ready;} );做个等价变换：

```
 
 // 如果不使用锁，也就是这样
 while(! ready ){
	cv.wait()
 }

```

同时另一个线程notify的步骤不受影响

```
 ready = true;
 cv.notify_all();

```

那么如果按先上面再下面的顺序执行，先执行上面的线程，首先 ready为false，进入wait。再执行下面，ready变为true，wait被唤醒，并检查ready，不满足while条件，于是跳出while，线程走下去了。

再看按照先下面再上面的顺序执行，先下面，ready变成true，然后notify_all，因为没有线程在wait，于是属于空操作；接着上面的线程执行，while条件不满足，于是跳出，线程走下去了。

没毛病！


但是你没注意交叉执行的情况：

```
Process A                             Process B


while (！ready)

                                      ready = true;
                                      cv.notify_all();

    cv.wait()

```



看到了吧，这种情况下A线程永远无法走下去，然而从编程者的期待中一定觉得是应该走下去的。

解决方法也很简单，加锁嘛。


```
Process A                             Process B

mtx.lock()
while (！ready)
                                      mtx.lock()
                                      ready = true;
                                      cv.notify_all();
                                      mtx.unlock();

    cv.wait()
mtx.unlock()
```

由于你加了锁，上面的顺序是无法发生的，所以这样是安全的。
现在我们知道了不能没有锁，下面我们再看看锁怎么用。

### 用了锁还有什么问题
前面加锁的方法真的安全吗？ 并不是，虽然不会交叉执行了，但是却也无法顺序执行了，如果B先拿到锁，接着释放并没什么问题；但是如果A先拿到锁，接着等待，并持续持有锁，此时B无法拿到锁，也就无法唤醒A线程。问题好像更大了。

这时wait 函数说这个问题我来处理，我可以在进入睡眠状态后把锁释放掉，然后在被唤醒后再把锁抢回来，这样对外部来说是感觉不到锁被释放过的。

是个好主意，也确实是这么做的，传入锁不是为了加锁而是为了解锁，于是就有了我们把lck传给wait的这个用法。终于弄清楚为什么这么设计了。

再补充一点，对于如线程B这样的先修改判断条件再notify的过程，加锁不一定要把cv.notify_all加进去，你只要把修改判断条件的放到锁里面就好，notify_all也放锁里当然也没问题。 如果只notify，不改条件，那自然无所谓，不会影响wait的结果。对于要修改条件的，由于涉及到了并发访问了，基本上上锁就对了。


### 总结

condition_variable 通过wait和notify来达到线程间的同步；

wait函数可传入条件函数，在首次进入和被唤醒时执行条件函数，返回true才真正被唤醒往下走。

wait必须传入mutex，这个不是保护类内部资源，而是保护外部的条件函数到睡眠状态的间隙，避免被其他线程打断，丢失唤醒的机会。

传入wait的mutex在类内部不是一直加着锁也不是一直解开锁，而是先被解锁再被加锁，以让其他线程能有机会得到锁。




	 
