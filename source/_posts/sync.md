---
title: 同步三要素
tags:
  - 系统
categories:
  - 代码
date: 2022-07-11 17:34:46
updated: 2022-07-11 17:34:46
---

# 同步三要素

## 简介
在我之前写过一篇[lockfree](https://yizhi.ren/2017/09/19/reorder/)的文章，里面提到了CAS和内存屏障以及之间的关系，这里先总结一下。

![lockfree技术点关系图](/linkimage/reorder/techniques.png)

lockfree主要是通过一定的编程规范来避免线程之间流程阻塞。不阻塞并不难，难的是不阻塞的基础上确保结果的正确性。

图中有两条重要的路线，一条是并发写，写的过程是一个Read-Modify-Write的过程，不是单步的，因此为了确保正确性，需要一个把RMW做成原子操作，于是CAS就出场了，这是一个处理器支持的操作，在汇编级别支持RMW原子性。

另一条线是多核指令顺序一致性，cpu为了性能，会做指令乱序，这种乱序在同一cpu的程序看来是感知不到的（cpu会自己保证这一点），但是会被其他cpu上的程序感知到，带来异常，为了消除这种乱序，我们需要使用经过封装的原子变量类型，或者使用内存屏障。如果要防止乱序的场景是一个线程写一个值，一个线程读一个值，那么我们通过acquire和release两个轻量屏障就可以实现了，别的场景有可能需要使用全能内存屏障，别的场景是什么呢？比如生产者生产的同时还消费，消费者消费的同时还生产，这就比较复杂，可能需要全能屏障来解决。

那么这两条路线的交集是什么呢，交集是多核执行RMW指令序列时，为了顺序一致性，除了要做到顺序一致，还需要保证结果正确。这个时候就需要CAS配合内存屏障了。

总结完之后，这一文，主要是要展开讲一下这里面更本质的东西，cpu乱序的本质是什么，内存屏障的本质是什么，cas的本质是什么，并延伸到锁的本质是什么。涉及到的技术主要是3点，包括：缓存一致性协议，内存屏障，锁。这三点可总结为同步三要素。

<!-- more -->

## 缓存一致性协议
### 缓存带来的一致性问题
现在的cpu都会配一个缓存，一个cpu一个缓存(可能是多层缓存，这里统一简化成一个缓存来理解)，不同的cpu之间以及cpu和内存之间彼此相连。cpu可以只跟缓存交互就完成一次读写，这提高了处理性能，但也带来了一致性的问题。
![cpucache](/linkimage/sync/cpucache.png)

（图片来自[lecture13-memory-barriers](https://www.ics.uci.edu/~aburtsev/cs5460/lectures/lecture13-memory-ordering/lecture13-memory-barriers.pdf)）

比如这个简单的场景，变量x已经存在于两个cpu的缓存中，我们在两个cpu上分别执行函数`bool cmp_and_set(ptr, oldval, newval)`。
我们假设这函数生成了单一汇编指令，这个指令会比较`[*ptr]`和`old`的值，如果相等，就把`[*ptr]`设为`newval`,并返回`true`，否则就返回`false`。这样的指令在x86平台上是存在的，分别是`cmpxchgq`,`cmpxchgl`,`cmpxchgw`,`cmpxchgb`。对应变量的字节数为8,4,2,1个字节。
这里我们不展开成汇编，直接在下图中用cmp_and_set表示。

![bothcpuadd](/linkimage/sync/bothcpuadd.png)

[>_<]: 以下是作者备份上图uml，读者忽略
		uml script作者备份用读者请忽略
		
		@startuml
		!pragma teoz true
	
		participant cpu0
		participant cpu1
	
		cpu0 -> cpu0 : cmp_and_set(addr,0,1)
		& cpu1 -> cpu1 : cmp_and_set(addr,0,1)
	
		@enduml

两个线程各自执行`cmp_and_set(addr,0,1)`操作，都执行成功了，返回`true`，但产生的结果是`addr`的值只是被增加了一次，会有一次最终丢失了。


### MESI协议
那么解决这个问题的方法是什么呢？`缓存一致性协议`。
缓存一致性协议通过一系列的状态来管理缓存行的状态，来消除数据的不一致。缓存一致性协议可以有很多不同的设计和实现，我们只需要了解只含4种状态的MESI协议就要可以了。
`M`即`modified`，表示这个缓存行被这个cpu独占，这个缓存行数据必须首先回写内存才能更新成其他内存数据。

`E`即`exclusive`，表示这个缓存行被这个cpu独占，但是值还没更新，所以这个值跟内存中的值是一样的，丢弃这个缓存行时不需要回写。

`S`即`shared`，表示这个缓存行很可能被多个cpu共享，因此cpu不能直接修改这个缓存行，但是这个值跟内存中的值也是保持一致的，可以随时丢弃。

`I`即`invalid`，表示这个缓存行被丢弃了，可以随时用来填充新的内存数据。

有了这个协议后，我们再来看上面的场景：两个cpu同时持有一份缓存并更新。

![bothcpuaddsuccone](/linkimage/sync/bothcpuaddsuccone.png)


[>_<]: 以下是作者备份上图uml，读者忽略
	uml script作者备份用读者请忽略
	@startuml
	!pragma teoz true
	
	participant cpu0
	participant cpu1
	
	hnote over cpu0 : S
	& hnote over cpu1 : S
	
	cpu0 ->(10) cpu1 : Invalidate
	hnote over cpu1 : I
	
	cpu1 ->(10) cpu0 : Acknowledgement
	hnote over cpu0 : E
	
	cpu0 -> cpu0 :  cmp_and_set_with_mesi(addr,0,1)
	hnote over cpu0 : M
	
	@enduml

我们看到两个cpu中原先对应addr的缓存行的状态都是S，cpu0想要更新缓存，发现是状态S就发起`Invalidate`消息给别的cpu，别的cpu收到后就把自己对应的缓存行给失效了，然后响应给cpu0，cpu0于是就可以更新自己缓存行状态为E独占，如此就可以更新缓存了。更新完后缓存行状态变成M。更新成功，返回true。

那么cpu1上的程序会怎么样呢？这个时候由于cpu1的状态是I所以他要首先发送`Read Invalidate`消息给别的cpu，这条消息要求目标cpu不光返回最新的值（如果有）还要失效他的缓存行。当cpu1收到了最新值`Read Response`以及所有cpu的`Invalidate acknowledge`，就把自己的状态设为E，并执行`cmp_and_set(addr,0,1)`。

![bothcpuaddfailone](/linkimage/sync/bothcpuaddfailone.png)

[>_<]: 以下是作者备份上图uml，读者忽略
	uml script作者备份用读者请忽略
	@startuml
	!pragma teoz true
	
	participant cpu0
	participant cpu1
	
	hnote over cpu0 : M
	& hnote over cpu1 : I
	
	cpu1 ->(10) cpu0 : read invalidate
	cpu0 -> cpu0 : write back to memory
	cpu0 ->(10) cpu1 : Read Response
	cpu0 ->(10) cpu1 : invalidate acknowledge
	
	hnote over cpu0 : I
	& hnote over cpu1 : E
	
	cpu1 -> cpu1 :  cmp_and_set_with_mesi(addr,0,1)
	@enduml

但是此时addr地址上的值已经是1了，比较失败，cmp_and_set返回false。

由此我们看到有了缓存一致性协议，原先会丢失一次更新，现在两次更新一次成功一次失败，符合预期。

你可能会问，如果cpu0和cpu1同时发起`Invalidate`消息怎么办，这个时候cpu会有个总线仲裁，判断谁的`Invalidate`有效，因此只有一个`invalidate`消息能发成功。

### MESI异步消息
MESI中读写数据的过程中都要经过一轮消息的收发，在并发读数据的过程中最终每个cpu在那个缓存行上都会处于S状态，不需要再发送同步消息了。但是在并发写的过程中，cpu之间不存在稳定的状态，每次写的时候要确保独占，因此cpu之间要经常发起`Invalidate`消息，这导致写的性能会很低。

因此mesi协议针对写的流程做了优化，思路是进行异步化。

![storebuffer](/linkimage/sync/storebuffer.png)

(图片来自[whymb](http://www.rdrop.com/users/paulmck/scalability/paper/whymb.2010.07.23a.pdf))

cpu0在触发`Invalidate`或者`ReadInvalidate`消息的同时把store操作记录到`StoreBuffer`中，然后cpu0就可以接着执行紧接着的后续指令。当cpu0收到其他cpu的响应后，cpu0更新相应缓存行的状态和内容。

这还不够异步化，当cpu1收到`Invalidate`或者`ReadInvalidate`的时候需要失效本地的缓存行，但是如果cpu1正在密集的读写缓存，这个`invalidate`操作就可能会延迟；另外如果cpu1同时收到大量的`Invalidate`或者`ReadInvalidate`，也会导致cpu1处理延迟，从而阻塞住其他cpu的执行。因此接收端也需要异步化。

![storeinvalidatebuffer](/linkimage/sync/storeinvalidatebuffer.png)

(图片来自[whymb](http://www.rdrop.com/users/paulmck/scalability/paper/whymb.2010.07.23a.pdf))

cpu1在收到`Invalidate`或者`ReadInvalidate`的时候，直接塞到`InvalidateQueue`中，并直接响应给cpu0。这个塞进去的消息会确保在cpu1发出对应缓存行的消息之前被处理。

### 异步化后的问题

我们看一个简单的场景，cpu0执行foo函数，cpu1执行bar函数。

```c
// 初始时a==0,b==0
void foo(void)
{
	a=1;
	b=1;
}

void bar(void)
{
	while(b==0)continue;
	assert(a==1);
}
```

按照预期，bar函数中的断言是不可能失败的。但是实际上并不能保证，我们来看一下在异步化之后，执行流程如何。当然我会尽量构造出一个会让assert失败的流程出来。。。

![asyncflow](/linkimage/sync/asyncflow.png)

我们假设cpu0执行foo函数，cpu1执行bar函数，变量a和b初始都是0。cpu0上a状态是S，b状态是E；cpu1上a的状态也是S，b的状态是I。

1. cpu0执行`a=1`，但是发现a在缓存中的状态是S，于是cpu0发送一个`invalidate`消息给其他cpu以便独占缓存。但是因为异步化，在发送`invalidate`的同时会记录`a=1`到`storebuffer`中。紧接着，cpu0执行后续的指令，不同步等待`acknownledgement`。

2. cpu0紧接着执行完`b=1`,b在cpu0上已经是E状态因此可以直接修改b，改完后b状态变成M。

3. 这时候cpu1开始执行`while(b==0)continue;`。这时候b的状态是`Invalidate`。于是b发起Read请求给别的cpu。
4. cpu0收到消息并响应给cpu1，携带b的缓存行。于是`while(b==0)continue;`就退出了。

5. 紧接着cpu1执行`assert(a==1);`，此时a的`Invalidate`消息还在`InvalidateQueue`中，cpu1中a的状态依然是S，于是直接读到`a==0`。assert失败。

6. 后续cpu0这边会接收到返回的`acknowledgement`。
7. 然后cpu0更新`a=1`到缓存中，a状态变成M。
8. cpu1则也在某个时间处理`InvalidateQueue`中的消息，失效缓存行，a状态变成I。

可以看到，assert在第5步的时候失败了，这跟我们的预期不符。

### cpu乱序

什么是cpu乱序，就是指cpu为了性能考虑，可能会打乱执行的序列，导致后面的指令先执行。

不过cpu乱序会确保该cpu上的执行不受影响，意思是虽然我会乱序但是我会确保在我这个cpu上执行的程序看到的结果跟不乱序是一样的。那么影响的是什么呢，影响的是其他cpu上的程序看到的此cpu的结果，会跟实际的指令顺序不同。

比如上面的例子中，mesi协议异步化之后，cpu0上执行`a=1;b=1;`,无论是否乱序，在cpu0都是连续更新了a和b的值，a和b中间并没有读，因此交换顺序没啥关系。
```
聪明的你可能想到一个问题，如果在a=1;b=1;中间也读一下a的值，那cpu0还会选择乱序吗？
a=1;assset(a==1);b=1;这条指令如果执行那么理应是assert true的(假设只有cpu0会去修改a)。
如果乱序了那么assert就可能会fail。cpu在这里其实依然会选择做乱序，
但是它在读取a的值得时候会同时参考StoreBuffer和cache。
如果StoreBuffer中存在就用store buffer中的了，因此这时候虽然乱序了，但是结果符合预期。
这也就是上面说的即便乱序，cpu也会确保在我这个cpu上执行的程序看到的结果跟不乱序是一样的。
```

但是在cpu1有读a和b的操作，它看到的却是乱序后的`b=1;a=1`先看到了b的修改，导致了问题。引起这个问题的原因是`StoreBuffer`和`InvalidateQueue`的存在。如果要规避，我们得同时消除这两者的副作用。

假如我们只消除`StoreBuffer`的副作用（比如禁用`StoreBuffer`），那么在cpu0这边实际执行的顺序就是`a=1;b=1;`，但是在cpu1这一边由于`InvalidateQueue`的存在，cpu1在执行`assert(a==1)`的时候读取a的值，a的缓存行依然可能是S状态。导致cpu1依然是先看到`b=1`再看到`a=1`。

假如我们只消除`InvalidateQueue`的副作用（比如禁用`InvalidateQueue`），那么在cpu0这一侧`a=1`会放到`StoreBuffer`中，并发生乱序，先执行`b=1`，再最终执行`a=1`。cpu1这一侧，收到`Invalidate`消息后立即失效缓存行，接着cpu1在执行到`assert(a==1)`的时候读取a的值，a的缓存行是`Invalidate`，于是发起`Read`请求，cpu0响应`ReadResonse`，但此时可能cpu0这一侧还没有执行`a=1`，这可能是`StoreBuffer`中还没有收到其他全部cpu(实际情况可能不止cpu1)的`acknownledgement`，也可能是收到了`acknownledgement`，但还没有写回缓存中。cpu拿到的缓存行依然是`a==0`，导致assert失败，也就是cpu1依然是先看到`b=1`再看到`a=1`。

可以看到，cpu乱序的本质是缓存一致性协议的异步化，他加速了cpu指令的执行，但是带来的后果是其他cpu看到的指令顺序错乱，引起预期外的结果。

## 内存屏障

为了抵消cpu乱序的副作用，cpu引入了内存屏障的概念，他可以强制执行`StoreBuffer`和`InvalidateQueue`的清空，或者说等待他们的清空。
内存屏障分为写屏障和读屏障，写屏障,出现在写写之间，即如下场景。

```c
a=1;
smp_wmb();
b=1;
```
当执行到`smp_mb`的时候，cpu可以选择原地等待`a=1`执行完；或者给`a=1`添加标记（`StoreBuffer`中的每一项都标记上），然后`b=1`执行的时候，发现`StoreBuffer`中有带标记的项，于是`b=1`也放进`StoreBuffer`，即使b的状态已经是E或者M，不是独占就照原先的逻辑，放进去的同时发送`Invalidate`/`ReadInvalidate`消息，但是`b=1`不会做标记，当`StoreBuffer`中全部带标记的操作都完成后，`b=1`才会开始执行，这时候如果b的缓存状态不是独占会涉及到重发`Invalidate`/`ReadInvalidate`消息。
读屏障，出现在读读之间,比如：

```c
	while(b==0)continue;
	smp_rmb();
	assert(a==1);
```
当执行到smp_rmb的时候，cpu会给`InvalidateQueue`中的每一项添加一个标记，当后续遇到读指令的时候，发现`InvalidateQueue`中有带标记的项，就阻塞直到`InvalidateQueue`中的每一项都应用到缓存中。添加了读写屏障后，完整代码如下：

```c
// 初始时a==0,b==0
void foo(void)
{
	a=1;
	smp_wmb();
	b=1;
}

void bar(void)
{
	while(b==0)continue;
	smp_rmb();
	assert(a==1);
}
```

原先引起assert失败的流程变成如下的流程：

![withmbr](/linkimage/sync/withmbr.png)

可以看到现在这个流程中，`b=1`是等待`a=1`执行完之后再执行的，同样`assert(a==1)`是在`while(b==0)continue`之后执行的。

注意图中`while(b==0)continue`是画在`b=1`之后执行，如果画在之前执行的话，不影响结果，但是流程较多会让图看起来复杂。cpu1会先进行一轮`read`和`read response`交互，随后发现b是0就继续循环，然后cpu0开始执行`b=1`,因为此时b的状态变成S了就发起`Invalidate`交互，执行完后，cpu1因为b状态变成Invalidate了就又发起一轮`read`交互，然后读到b为1才退出循环。

图最后的部分`assert(a==1)`中需要发起`Read`交互，是因为`InvalidateQueue`把a的状态变成`Invalidate`了。

### 内存屏障类型

#### 写写乱序和读读乱序

前面讲到了两种乱序，写写乱序和读读乱序。对应的内存屏障是写屏障和度屏障，相应的原理是清空`StoreBuffer`和清空`InvalidateQueue`。

那么还有其他的乱序和内存屏障吗？我们来看一下另外两种乱序，读写乱序和写读乱序。

#### 读写乱序

```c
// 初始时a==0,b==0
void foo(void)
{
	read a;
	b=1;
}

void bar(void)
{
	while(b==0)continue;
	a=1;
}
```

在上面的代码中，可以知道`read a`拿到的值一定是0，不可能是1.但是如果foo中发生了读写乱序，`b=1`先执行了，那么`read a`就可以变成1。但是我们如果回看MESI协议的流程，可以发现读时虽然可能发生`Read`和`ReadResponse`交互。但实际上这个过程是同步等待的，并不存在异步，所以读也就不存在被乱序到稍后执行的可能性，既然如此我们也就可以认为不存在读写乱序，因此也没法定义读写乱序的内存屏障该如何实现。我们现在可以针对MESI协议作出结论：不存在读写乱序，也不存在读写乱序对应的内存屏障。

#### 写读乱序

那么写读乱序呢？

```c
// 初始时a==0,b==0
void foo(void)
{
	a=1;
	read b;
}

void bar(void)
{
	b=1;
	read a;
}
```

上面的例子中，我们可以在心里简单过一遍流程，可以想象一下函数执行完之后，a和b分别是多少，容易分析到，a可能是0也可能是1，同样b可能是0也可能是1，因此我们在代码中使用assert做断言是没有意义的，因为a和b的值本身就不确定。但是如果我们以第三者的角度看a和b的值组合，容易分析到，可能存在3种情况`1-0`,`1-1`,`0-1`。但是不存在`0-0`的可能性。

理论上不存在`0-0`的可能性，但是实际上我们知道写是可以异步化的，因此可能乱序成如下结果：

```c
void foo(void)
{
	read b;
	a=1;
}

void bar(void)
{
	read a;
	b=1;
}
```

如此就可以导致`0-0`的结果。我在[lockfree](https://yizhi.ren/2017/09/19/reorder/?highlight=lockfre#%E9%A1%BA%E5%BA%8F%E4%B8%80%E8%87%B4%E6%80%A7)一文中也通过代码验证过这一结论，发生`0-0`的概率大概1/200。

我们从流程上来看一下这一现象发生的过程。

![result00](/linkimage/sync/result00.png)

可以看到两个cpu都发生了乱序写读乱序，导致两边都会读到0。为了解决乱序，我们需要一个写屏障来在读之前清空`StoreBuffer`。

```c

void foo(void)
{
	a=1;
	smp_wmb();
	read b;
}

void bar(void)
{
	b=1;
	smp_wmb();
	read a;
}
```

我们也看一下加了写屏障后的可能流程：

![result00withwmb](/linkimage/sync/result00withwmb.png)

我们可以看到虽然加了写乱序后，代码并没有乱序了，但是由于read操作依然位于`InvalidateQueue`清空之前，所以结果依然是`0-0`。

这样的结果出乎意料，我们说内存屏障是为了避免乱序，然而加了写屏障后乱序不存在了，怎么结果还是有问题呢？

这里本质上还有一个因果关系需要解决，当cpu0执行`a=1;smp_wmb();read b;`时候，由于存在写屏障，当`read b`执行前，`a=1`确定被写入成功，那么此时其他cpu就确定能够看到a的最新值了，那么假设另一个cpu1执行指令`b=1;smp_wmb();read a;`，如果我们确认cpu1的`read a`没有读到a的最新值，我们是不是可以确认cpu1的`b=1`一定发生在cpu0的`read b`之前呢？当然是这样了，可以看下面的指令顺序。

```c++
// 如果cpu1.read a在cpu0.a=1之前，那么cpu1.b=1也必然在cpu0.read b之前。
// 下面这个顺序跟上图并不完全对应，但是有一点是一致的，那就是cpu1.read a没有读到cpu0.a=1的值。
  cpu0                    cpu1
  
                          b=1;
                          smp_wmb();
                          read a;

  a=1;
  smp_wmb();
  read b;

////////////////////////////////////////////////////////////////////////
// 如果cpu1.read a在cpu0.a=1之后，那么cpu1.b=1可能在cpu0.read b之前也可能在之后。
// 这种情况我们不做更多分析
  cpu0                    cpu1
  
                          [b=1; smp_wmb();]
  a=1;smp_wmb();
  read b;
                          [b=1; smp_wmb();]
                          read a;

```

因此我们分析到如果`cpu1.read a`没有读到`cpu0.a=1`的值那么按照因果关系,`cpu1.b=1`必须能够被`cpu0.read b`读到。于是为了这种情况的正确性，我们必须在`cpu0.read b`之前添加读屏障，清空`InvalidateQueue`。同理`cpu1.read a`之前也应该添加读屏障。

```c
void foo(void)
{
  a=1;
  smp_wmb();
  smp_rmb();
  read b;
}

void bar(void)
{
  b=1;
  smp_wmb();
  smp_rmb();
  read a;
}
```

如此之后，流程就变得确定了：

![result00withwmbrmb](/linkimage/sync/result00withwmbrmb.png)

经过在写读之间添加写屏障和读屏障，我们可以避免写读乱序带来的副作用。我们可以用`smp_mb`来表示全能屏障，表示`smp_wmb+smp_rmb`。我们也可以看出写读乱序的屏障是最重的一个屏障，需要同时清空`StoreBuffer`和`InvalidateQueue`。

### 不同层次的内存屏障

#### 设计层面

我们已经知道了在cpu设计层面，有`写写`，`读读`，`写读`，`读写`四种乱序类型，总结如下（当然这是在基于MESI协议的前提下）：

| 乱序类型     | 写写   | 读读   | 写读 | 读写 |
| ------------ | ------ | ------ | ---- | ------ |
| 内存屏障类型 | 写屏障   | 读屏障   | 全能屏障 | 不需要 |
| 原理         | 清空`StoreBuffer` | 清空`InvalidateQueue` | 清空`StoreBuffer`和`InvalidateQueu` | 无 |

#### 指令层面

上面是在cpu设计层面上来说的，也就是说所谓的读屏障写屏障多少是有点抽象层面上来说的，在实际cpu指令层面它可能不是这么区分的。比如

| 内存屏障类型 | 写屏障   | 读屏障   | 全能屏障  |
| ------------ | ------ | ------ | ---- |
| powerPC指令 | lwsync   | lwsync   | sync | 
| x86指令         | nop | nop | mfence |


可以看到powerpc中只区分了全能屏障和非全能屏障，读屏障和写屏障是同一个指令。

x86中读屏障和写屏障居然是一个空指令，这点的本质是因为x86的cpu实现中，拿掉了`InvalidateQueue`,并且会把每个写操作都会放到`StoreBuffer`中，因此效果上自带了读屏障和写屏障，只有写读乱序是需要加全能屏障。

#### 应用层面

最后到了应用层，我们又根据应用场景的需要，把内存屏障分成了Acquire和Release两种。

![acq-rel-barriers](/linkimage/sync/acq-rel-barriers.png)

（图片来自[Acquire and Release Semantics](https://preshing.com/20120913/acquire-and-release-semantics/))

我们把避免了读读和读写乱序的屏障称为acquire，把避免了读写和写写乱序的屏障称为release。

由于我们已经知道读写乱序其实是不存在的，因此acquire可以通过读屏障实现，release可以通过写屏障实现。

| 内存屏障类型 | acquire | release | 
| ------------ | ------ | ------ | 
| powerPC指令 | lwsync | lwsync | 
| x86指令 | nop | nop | 


上面讲到的cpu指令和acquire/release的实现都可以通过linux源码看到：
```javascript
https://github.com/torvalds/linux/blob/master/arch/powerpc/include/asm/barrier.h
https://github.com/torvalds/linux/blob/master/arch/x86/include/asm/barrier.h
```
现在我们把上面的表格全部合并到一起来做个总结：

| 乱序类型     | 写写   | 读读   | 写读 | 读写 |
| ------------ | ------ | ------ | ---- | ------ |
| 内存屏障类型 | 写屏障   | 读屏障   | 全能屏障 | 不需要 |
| 原理         | 清空`StoreBuffer` | 清空`InvalidateQueue` | 清空`StoreBuffer`和`InvalidateQueue` | 无 |
| powerPC指令 | lwsync   | lwsync   | sync | nop |
| x86指令         | nop | nop | mfence | nop |
| 应用层语义         | release | acquire | 无 | acquire + release |

### Acquire和Release

上面我们提到一个应用层屏障语义Acquire和Release，那他们的使用场景和意义是什么呢？

任何情况下，当我们想确保指令顺序的时候都可以使用全能屏障，只不过鉴于全能屏障较重，才有了Acquire和Release，这二者通常都比全能屏障要轻。

acquire的语义是禁止读读和读写乱序，也就是禁止某条读指令跟后面的读写指令发生乱序, 如下指令中，`acquire`指令可以避免它前面的读指令跟他后面的读写指令发生乱序。

```c
void foo(void)
{
	read a;
	acquire();
	read b;
	c=1;
}
```
release的语义是禁止读写和写写乱序，也就是禁止某条写指令跟前面的读写指令发生乱序，如下指令中,`release`指令可以避免它前面的读写指令跟他后面的写指令发生乱序。
```c
void bar(void)
{
	read b;
	c=1;
	release();
	a=1;
}
```
那么我们把二者配合起来使用，来看看有什么效果：
```c
  cpu0                    cpu1
                          void bar(void)
                          {
                            xxx;
                            release();
                            a=1;
                          }
  
void foo(void)
{
    read a;
    acquire();
    yyy;
}

```
综合我们前面所学到的，如果cpu0的`read a`能读到cpu1的`a=1`的值，那么可以确认cpu0的`yyy`一定是发生在cpu1的`xxx`之后，这里`xxx`和`yyy`可以是任意多的指令，不是专指某一条指令。我们稍微改一下：
```c
  cpu0                    cpu1
                          void bar(void)
                          {
                            xxx;
                            release();
                            a=1;
                          }
  
void foo(void)
{
    while(a!=1)continue;
    acquire();
    yyy;
}

```
我们把`read a`改成`while(a!=1)continue;`,这样foo就可以一直等待bar执行完，并且确保foo能看到bar的全部修改。因此我们通过轻量的内存屏障外加一个共享变量就实现了类似全能屏障的顺序性。
但是依然要记在心里，这依然是个轻量屏障，依然存在乱序情况。

![stillreorderexist](/linkimage/sync/stillreorderexist.png)

由于acquire不会清空`StoreBuffer`因此`zzz=1`是可以乱序到acuqire之后的；同样release不具有清空`InvalidateQueue`的功能，因此`read b`可能读到release之前就在`InvalidateQueue`中而还没有令b失效的b的旧缓存值，相当于是乱序到了release之前。但是即便如此，yyy是可以确认在xxx之后发生的，这一点能保证就达到目的了。




## 锁

我们来看看锁跟内存屏障有什么关系。首先锁的本质是什么，本质是把一个内存地址从0变成1（加锁），再从1变成0（解锁）。

而为了保证每一次修改的原子性，我们需要使用cas（compare-and-swap）来操作。

### cas
cas是原子性的修改一个内存值的指令，他接收3个参数 `bool cas(ptr, old, new);`，ptr是内存地址，old是旧值，new是新值，他会比较ptr所在地址的值跟old之间是否相等，相等就把new设置到ptr所在的内存, 如果设置成功返回true，否则返回false。	
他的底层实现是基于cpu提供相关指令，在x86体系中使用的是cmpxchg系列指令，我们来看一下源码中相关的定义：

```c
// https://github.com/torvalds/linux/blob/v5.19-rc7/tools/arch/x86/include/asm/cmpxchg.h
/*
 * Atomic compare and exchange.  Compare OLD with MEM, if identical,
 * store NEW in MEM.  Return the initial value in MEM.  Success is
 * indicated by comparing RETURN with OLD.
 */

#define __raw_cmpxchg(ptr, old, new, size, lock)			\
({									\
	__typeof__(*(ptr)) __ret;					\
	__typeof__(*(ptr)) __old = (old);				\
	__typeof__(*(ptr)) __new = (new);				\
	switch (size) {							\
	case __X86_CASE_B:						\
	{								\
		...		\
		break;							\
	}								\
	case __X86_CASE_W:						\
	{								\
		...		\
		break;							\
	}								\
	case __X86_CASE_L:						\
	{								\
		...				\
		break;							\
	}								\
	case __X86_CASE_Q:						\
	{								\
		volatile u64 *__ptr = (volatile u64 *)(ptr);		\
		asm volatile(lock "cmpxchgq %2,%1"			\
			     : "=a" (__ret), "+m" (*__ptr)		\
			     : "r" (__new), "0" (__old)			\
			     : "memory");				\
		break;							\
	}								\
	default:							\
		...\
	}								\
	__ret;								\
})

#define LOCK_PREFIX "\n\tlock; "

#define __cmpxchg(ptr, old, new, size)					\
	__raw_cmpxchg((ptr), (old), (new), (size), LOCK_PREFIX)

#define cmpxchg(ptr, old, new)						\
	__cmpxchg(ptr, old, new, sizeof(*(ptr)))

```

可以看到`cmpxchg(ptr, old, new)`最终是预编译成`lock;cmpxchgq...`(假设`sizeof(*(ptr))`是`__X86_CASE_Q`)。这个指令中cmpxchgq完成cas的操作，而lock完成cpu独占的功能，因为我们不能允许每个线程同时执行cas都成功，cmpxchgq并不能自动触发缓存一致性协议的独占，因此需要lock来协助完成。

```
https://stackoverflow.com/questions/25382009/purpose-of-cmpxchg-instruction-without-lock-prefix
这里有讨论cmpxchgq和lock配合的事。
```

cpu在遇到lock指令时，会做两个事

```
https://cana.space/cas/
当cpu发现lock指令会立即做两件事
	1.将当前内核中线程工作内存中该共享变量刷新到主存；
	2.通知其他内核里缓存的该共享变量内存地址无效；
底层有两种实现方式
	缓存一致性协议，如mesi
	锁总线
```

我们以我们介绍过的缓存一致性协议为例，可以想到，cpu做的事情一个是把自己的缓存值写入内存（如果其缓存行的状态是M，否则就没必要），另一个是给别的cpu发送`Invalidate`消息，如此这个cpu就独占缓存行了。至于另一个锁总线的方式，我不知道他是如何做到1和2的，只知道最后是通过锁住总线来独占修改的。

独占之后，再执行cmpxchgq。这就是cas的底层原理。现在我们可以使用cmpxchg来实现cas函数:

```c
bool cas(ptr, old, new)
{
	return old == cmpxchg(ptr,old,new);
}
```

### 自旋锁

通过锁的本质和cas操作，我们可以实现一个自旋锁：

```c
// *addr init to 0

void lock(addr)
{
	while(!cas(addr, 0, 1));
}

void unlock(addr)
{
	*addr = 0;
}
```

同时一个使用自旋锁的例子可能是这样的：

```c
  cpu0                    cpu1
                          lock();
                          xxx;
                          unlock();
                         
lock();
yyy;
unlock();
                          lock();
                          zzz;
                          unlock();

```

我们看到了3段加锁的区间。显然这三段区间的发生顺序是xxx->yyy->zzz。但现在这并不能保证，我们需要使用内屏屏障，通过对比我们前面讲acquire和release语义时候的代码，我们可以对他进行套用。

```c
  cpu0                    cpu1
                          lock();
                          acquire();
                          xxx;
                          release();	// 1
                          unlock();
                         
lock();
acquire();	// 2
yyy;
release();	// 3
unlock();
                          lock();
                          acquire();  // 4
                          zzz;
                          release();
                          unlock();
// 这里1和2可以确保xxx->yyy顺序，3和4可以确保yyy->zzz顺序
```

我们可以分别把acquire移到lock内，把release移到unlock内，于是不难得出，修正后的自旋锁实现为：

```c
// *addr init to 0

void lock(addr)
{
    while(!cas(addr, 0, 1));
    acquire();
}

void unlock(addr)
{
    release();
    *addr = 0;
}
```



### 信号量

类似于锁的本质是把内存值写上0和1，信号量的本质是通过wait函数把内存值减1，通过post函数把内存值加1。我们来自己设计一个信号量，经过自旋锁的设计经验我们大概也知道套路了。这次我们用面向对象的方式来设计。

```c
class sem_t {
public:
	sem_t(int cnt):count(cnt){}
	void wait(){
		int cur = count;
		while(
			!(cur && cas(&count,cur,cur-1))
		)cur = count;
		acquire();
	}
	void post(){
		int cur = count;
		release();
		while(
			!(cur && cas(&count,cur,cur+1))
		)cur = count;
	}
private:
  int count;
};

sem_t sem(10);


cpu0                      cpu1
  
                          sem.wait()
                          xxx;
                          sem.post()
                         
sem.wait()
yyy;
sem.post()

```

`sem`的`wait()`和`post()`类似`spinlock`的`lock()`和`unlock()`，`wait`中包含`acquire`，`post`中包含`release`。如此我们可以同样做到被`wait()`和`post()`包围的代码段的顺序：xxx->yyy。

在上面的实现中，我们在wait和post中都使用了while循环，所以我们这个sem_t叫spinsem更合适。我们没有用操作系统中真实sem_t的逻辑，真实的sem_t在wait的时候，如果count数<=0的时候会进入休眠。这里我补充一下真实sem_t的wait函数的逻辑，不感兴趣就麻烦跳过，不影响对本文的理解。

```c
// https://code.woboq.org/userspace/glibc/nptl/sem_wait.c.html#__new_sem_wait

int
__new_sem_wait (sem_t *sem)
{
  if (__new_sem_wait_fast ((struct new_sem *) sem, 0) == 0)
    return 0;
  else
    return __new_sem_wait_slow64 ((struct new_sem *) sem,
				  CLOCK_REALTIME, NULL);
}
// sem_wait会先走fast路径，在信号量内部的count数>0的情况，做一次cas，是非阻塞非等待的。
// 接着会走slow路径，


static int
__new_sem_wait_fast (struct new_sem *sem, int definitive_result/*0*/)
{
  uint64_t d = atomic_load_relaxed (&sem->data);
  do
    {
      //...
      if (atomic_compare_exchange_weak_acquire (&sem->data, &d, d - 1))
				return 0;
    }
  while (definitive_result);
  return -1;
}


static int
__attribute__ ((noinline))
__new_sem_wait_slow64 (struct new_sem *sem, clockid_t clockid,
		       const struct __timespec64 *abstime)
{
  int err = 0;
  //...
    
  // 循环直到成功
  for (;;)
  {
      // 如果count数不够了
      if ((d & SEM_VALUE_MASK) == 0)
      {
        // 进入睡眠
        err = do_futex_wait (sem, clockid, abstime);
        if (err == ETIMEDOUT || err == EINTR || err == EOVERFLOW)
        {
           // 如果出错就break返回
          break;
        }
        // 否则重新获取count数并重试
        // 这里可能是因为睡眠被唤醒
        // 也可能是因为此时count数增加了不再是0了，在真正进入睡眠时会检查当前count数是否是0
        // 是0就睡眠，这是一步原子操作, 这点很重要，如果非原子性就会存在错过唤醒机会的问题
        // 非零就不睡。这些逻辑封装在do_futex_wait中了
        d = atomic_load_relaxed (&sem->data);
      }
      else
      {
        // count数非0就尝试cas获取一下，跟fast路径下的差不多
        if (atomic_compare_exchange_weak_acquire (&sem->data,
            &d, d - 1 - ((uint64_t) 1 << SEM_NWAITERS_SHIFT)))
          {
            err = 0;
            break;
          }
      }
    }

  //...
  return err;
}
```

### 互斥锁

我们刚才已经实现了自旋锁，又实现了自旋信号量，我们可能已经发现，自旋锁跟自旋信号量差别不大，本质差别是锁的状态值就是0和1，而信号量的状态值可以是0-n。我们可以发现自旋锁就是一个初始值是1的自旋信号量，二者没有本质区别。

那么假设我们的信号量是操作系统中的支持睡眠的sem_t, 那么我们可不可以简单利用sem_t来实现一个支持睡眠的互斥锁呢？显然，也是可以的。

```c
// 伪码

#define Lock(sem) (sem.wait())
#define Unlock(sem) (sem.post())
#define DefineLock(name) sem_t name(1)

DefineLock(mylock);

Lock(mylock);
xxxxx;
Unlock(mylock);
```




## 参考
[cas](https://cana.space/cas/)
[whymb](http://www.rdrop.com/users/paulmck/scalability/paper/whymb.2010.07.23a.pdf)
[sem_wait.c](https://code.woboq.org/userspace/glibc/nptl/sem_wait.c.html)
[x86-barrier.h](https://github.com/torvalds/linux/blob/master/arch/x86/include/asm/barrier.h)
[powerpc-barrier.h](https://github.com/torvalds/linux/blob/master/arch/powerpc/include/asm/barrier.h)
[Java Memory Model (JMM)](https://juejin.cn/post/6844904144273145863)
[lecture13-memory-barriers](https://www.ics.uci.edu/~aburtsev/cs5460/lectures/lecture13-memory-ordering/lecture13-memory-barriers.pdf)
[Acquire and Release Semantics](https://preshing.com/20120913/acquire-and-release-semantics/)
[purpose-of-cmpxchg-instruction-without-lock-prefix](https://stackoverflow.com/questions/25382009/purpose-of-cmpxchg-instruction-without-lock-prefix)
[Does isync prevent Store-Load reordering on CPU PowerPC](https://stackoverflow.com/questions/43944411/does-isync-prevent-store-load-reordering-on-cpu-powerpc)

