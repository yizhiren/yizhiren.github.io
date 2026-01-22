---
title: 零拷贝通信框架iceoryx2原理解析
tags:
  - 通信
categories:
  - 架构
date: 2026-01-21 17:10:46
updated: 2026-01-22 00:00:46
---
## 零拷贝通信框架iceoryx2原理解析

### 简介

在之前的文章[SOA框架iceoryx原理解析](https://yizhi.ren/2024/06/22/iceoryx/)中， 我们讲解了iceoryx的架构、原理、交互，并进行源码的分析，在那篇文章最后我提到要关注iceoryx2这款通信框架， 现在我们来把iceoryx2的分析给补上。
iceoryx2，缩写为iox2，中文名叫冰羚2， 所以当后面提到冰羚2、iox2、iceoryx2的时候，他们都指代的是iceoryx2.
冰羚2与冰羚一样，是一款基于共享内存的零拷贝的通信框架，他通过对共享内存文件读写的封装和操作，实现了同一主机内的进程之间的数据传输。他与冰羚最主要的差别是冰羚2采用了去中心化的架构设计，消除了单点故障分险。早期的冰羚2只支持rust语言， 只支持linux系统，随着版本迭代， 如果已经支持c/c++和python。下面是iceoryx2的整体架构图：

![iox2-architecture](/linkimage/iceoryx2/iox2-architecture.svg)
图片来自[Introduction](https://ekxide.github.io/iceoryx2-book/main/introduction.html)

从图中可以看出，iceoryx2支持各种操作系统， 支持各种编程语言， 同时既支持iox2的app之间的通信，也支持通过扩展来接入到DDS和ROS等通信网络。

这是iceoryx2的整体架构，也可以说是架构愿景， 因为其中有些是还没有实现的， 就比如支持的语言目前2026年1月只有c/c++/rust/python,操作系统也只是刚支持上linux/macos/qnx/win。在与外部网络的接入方面，据我所知，ros2和dds和zenoh在2025年都已经有方案来实现对iox2的接入支持，图中其他的autosar和smoltcp并不了解。 尽管如此，随着不断迭代，更多特性被加入，iceoryx2的代码已经很庞大了，要深入理解已经不太容易。我们下面就选择他较早期的一个版本来深入了解一下。

<!-- more -->

### 整体代码结构

我们使用iceoryx2-0.1.0的版本来进行分析， 这是他在github仓库中打的第一个tag，此时代码结构相对简单，没有复杂的特性， 仅保留核心逻辑， 非常适合做原理分析。

iceoryx2-0.1.0的目录结构如下：

![iox-dirs](/linkimage/iceoryx2/iox-dirs.png)

其中最重要的是4个目录，分别是iceoryx2/iceoryx2-bb/iceoryx2-cal/iceoryx2-pal, internal目录里面是一些脚本非核心。这4各目录分别是什么作用呢？

![layered-architecture](/linkimage/iceoryx2/layered-architecture.svg)

图片来自[Layered Architecture](https://ekxide.github.io/iceoryx2-book/main/fundamentals/layered-architecture.html)

其中pal代表的是Platform Abstraction Layer的意思，表示平台抽象层，是对不同操作系统的一层抽象，由于当前支持的linux/macos/qnx/win都支持posix， 所以当前pal下就是对posix做了一层封装。

bb代表的的Building Blocks的意思，这一层实现的是一些工具或者组件，包括vector容器，queue队列，log日志，内存分配器pool_allocator，等等。对照Building Blocks这个名字，我们可以把这些理解成造房子的砖头。

cal代表的是Concept Abstraction Layer的意思， 表示概念抽象层，这一层开始有了通信相关的概念，比如share_memory共享内存， shm_allocator共享内存分配器，zero_copy_connection零拷贝连接, event事件，serialize序列化，等等。这一层相当于是通信用的模块，bb类比砖头，cal就可以类比成一面墙，一扇窗，一口衣柜。

iceoryx2这一层是通信的实现层加接口层，这一层借助cal层来完成最后通信组件的组装和实现，实现了publisher，subscriber，service等核心组件（0.1.0版本还没有node组件）。同时这些组件也是被用户直接操作的接口， 因此这一层同时也是接口层。

接下来，我会选择其中最重要的几个点进行讲解，分别是pool_allocator内存分配器，share_memory内存对象，service服务组件，publisher发布者组件，subscriber订阅者组件，以及zero_copy_connection零拷贝连接， 通过了解这些对象， 我们能够知晓通信框架是如何被建立的，以及通信是如何实现的。


### pool_allocator内存分配器
#### 内存布局
rust语言中有个 use std::alloc::Layout;这个是做什么的。
```rust
use std::alloc::Layout;

// 创建一个布局：大小为 16 字节，对齐要求为 8 字节
let layout = Layout::from_size_align(16, 8).unwrap();

// 为特定类型创建布局（常用）
let int_layout = Layout::new::<i32>();      // 4 字节，对齐 4
let vec_layout = Layout::new::<Vec<u8>>();   // 24 字节（64位系统）
```
layout代表的是内存块的信息， 包括内存块的大小，和这块内存的字节对齐要求。
上面`Vec<T>` 本质上是一个三元组（胖指针结构）：
```rust
pub struct Vec<T> {
    ptr: *mut T,      // 指向堆上数据的指针
    len: usize,       // 当前元素数量
    cap: usize,       // 分配的总容量}
```
在 64 位系统上：
- `*mut T` (指针)：8 字节
- `len` (usize)：8 字节
- `cap` (usize)：8 字节
总计：8 + 8 + 8 = 24 字节.

layout在alloc和dealloc的时候都要传递进去，alloc的时候传递比较好理解，allocator需要知道内存对齐以及需要知道要分配多大的内存。那为什么dealloc的时候也需要传递layout呢？
我们知道c语言中malloc出来的内存，可以直接free， 不需要传递layout这种类似的结构。这是因为c语言的分配器把分配出来的内存大小隐藏在在分配出来的内存的头部：
```
// 带头部信息的分配器
// +------------+-----------+
// | Header     | User data |
// +------------+-----------+
// ^            ^
// |            |
// 原始ptr      返回给用户的ptr
```
因此dealloc的时候通过把用户指针左移Header大小后就可以知道实际分配的内存大小了。
但是rust没有做这种内存布局的假设， 他允许allocator不需要Header前缀， 因此就需要额外来传递layout， 来获取这个实际分配的内存大小。比如我们可以实现一个基于内存块大小的内存池， 申请的时候， 申请32-size就返回32大小的内存块， 而不必返回一个实际是32+x的内存块。比如实现内存池，按需返回block块， 申请1k就返回1k的，而不是因为要加x额外空间就返回2k的block：
```
// 按大小分类的分配器
// 小对象池：16字节块、32字节块、64字节块...
// 需要知道大小来决定放回哪个池

// 这么使用
use std::alloc::{GlobalAlloc, Layout, System};

unsafe {
    let layout = Layout::new::<[u8; 1024]>();
    let ptr = System.alloc(layout);
    // 使用内存...
    System.dealloc(ptr, layout);
}
```
内存分配器的接口都会伴随着layout的传递。

#### 内存分配器
`接口定义`
BaseAllocator 接口, 定义allocate和deallocate接口：
```
pub trait BaseAllocator {
    fn allocate(&self, layout: Layout) -> Result<NonNull<[u8]>, AllocationError>;
    fn allocate_zeroed(&self, layout: Layout) -> Result<NonNull<[u8]>, AllocationError>;
    unsafe fn deallocate(&self, ptr: NonNull<u8>, layout: Layout) -> Result<(), DeallocationError>;
}
```
Allocator接口，定义grow和shrink接口：
```
/// Allocator with grow and shrink features.
pub trait Allocator: BaseAllocator {
    unsafe fn grow(
        &self,
        ptr: NonNull<u8>,
        old_layout: Layout,
        new_layout: Layout,
    ) -> Result<NonNull<[u8]>, AllocationGrowError>;

    unsafe fn grow_zeroed(
        &self,
        ptr: NonNull<u8>,
        old_layout: Layout,
        new_layout: Layout,
    ) -> Result<NonNull<[u8]>, AllocationGrowError>;

    unsafe fn shrink(
        &self,
        ptr: NonNull<u8>,
        old_layout: Layout,
        new_layout: Layout,
    ) -> Result<NonNull<[u8]>, AllocationShrinkError>;
}

```
`接口实现`
基于内存池并实现内存分配器接口的内存分配器实现 `iceoryx2_bb_memory::pool_allocator::PoolAllocator`如下：
```
pub struct PoolAllocator {
    buckets: UniqueIndexSet,
    bucket_size: usize,
    bucket_alignment: usize,
    start: usize,
    size: usize,
    is_memory_initialized: AtomicBool,
}

impl BaseAllocator for PoolAllocator {
    fn allocate(&self, layout: Layout) -> Result<NonNull<[u8]>, AllocationError> {
        ...
    }

    unsafe fn deallocate(
        &self,
        ptr: NonNull<u8>,
        _layout: Layout,
    ) -> Result<(), DeallocationError> {
        ...
    }
}

impl Allocator for PoolAllocator {
    /// always returns the input ptr on success but with an increased size
    unsafe fn grow(
        &self,
        ptr: NonNull<u8>,
        old_layout: Layout,
        new_layout: Layout,
    ) -> Result<NonNull<[u8]>, AllocationGrowError> {
        ...
    }

    unsafe fn shrink(
        &self,
        ptr: NonNull<u8>,
        old_layout: Layout,
        new_layout: Layout,
    ) -> Result<NonNull<[u8]>, AllocationShrinkError> {
        ...
    }
}
```
所以可以看出`iceoryx2_bb_memory::pool_allocator::PoolAllocator`实现了内存分配/释放和内存增长/缩减的功能，是一个满足功能要求的对象。

但是这还不止，我们从前面分层架构中可知， bb层的对象还不能被iceoryx2层直接使用， 而是需要经过cal层的封装， 因此cal层进行了如下封装：

```rust
// 接口 iceoryx2_cal::shm_allocator::ShmAllocator
pub trait ShmAllocator: Send + Sync + 'static {
    unsafe fn new_uninit(
        max_supported_alignment_by_memory: usize,
        base_address: NonNull<[u8]>,
        config: &Self::Configuration,
    ) -> Self;

    unsafe fn init<Allocator: BaseAllocator>(
        &self,
        allocator: &Allocator,
    ) -> Result<(), ShmAllocatorInitError>;

    unsafe fn allocate(&self, layout: Layout) -> Result<PointerOffset, ShmAllocationError>;

    unsafe fn deallocate(
        &self,
        distance: PointerOffset,
        layout: Layout,
    ) -> Result<(), DeallocationError>;
}

```
```rust
// 实现：iceoryx2_cal::shm_allocator::pool_allocator::PoolAllocator
impl ShmAllocator for PoolAllocator {
    unsafe fn new_uninit(
        max_supported_alignment_by_memory: usize,
        base_address: NonNull<[u8]>,
        config: &Self::Configuration,
    ) -> Self { ... }

    unsafe fn init<Allocator: BaseAllocator>(
        &self,
        allocator: &Allocator,
    ) -> Result<(), ShmAllocatorInitError> { ... }

    unsafe fn allocate(&self, layout: Layout) -> Result<PointerOffset, ShmAllocationError> { ... }

    unsafe fn deallocate(
        &self,
        offset: PointerOffset,
        layout: Layout,
    ) -> Result<(), DeallocationError> { ... }
}
```
`iceoryx2_cal::shm_allocator::pool_allocator::PoolAllocator`本质上就是对`iceoryx2_bb_memory::pool_allocator::PoolAllocator`进行了封装， 并重新暴露了类似的接口， 把内存分配器从bb层提升到了cal层。
bb层和cal层的内存分配接口有个很大的差别， bb层申请和释放的是内存绝对地址（还是虚拟地址不是指物理地址）， cal层申请和释放的是内存相对地址， 即相对一个base地址的offset。offset的设计是有用的，因为当同一个共享内存文件被多个进程打开时，他们的虚拟地址是不同的， 他们需要通过base地址加offset才能定位到同一个内存位置。

同时从`new_uninit`和`init`两个函数来说，`iceoryx2_cal::shm_allocator::pool_allocator::PoolAllocator`需要从外面输入内存基址`base_address`以及内存分配器`allocator`，这个`base_address`也就是待分配的连续内存块，`allocator`则是用于创建辅助数据结构的内存分配器。辅助数据结构的内存分配器也从外面传入，就可以实现`base_address`和辅助数据结构都在同一个共享内存对象/文件中。这样不同进程之间共享内存对象和内存分配器，就是完整的。

#### 分配器原理
内存分配器是怎么实现内存分配的呢？如果你不感兴趣，可以跳过。但是这是个有意思的环节， 能了解底层实现细节。

![pool-allocator-inter](/linkimage/iceoryx2/pool-allocator-inter.png)

PoolAllocator内部有两个关键部分，第一个是bucket列表， bucket的每一个格子是字节对齐后的内存块列表， 内存块是连续分布的， 总共有Capacity块。

第二个部分是一个index列表+header指针，他们组成一个index分配器， 分配到哪个index， 就代表PoolAllocator分配的内存块是bucket列表中的第index个。

index分配器要展开来讲讲， 他初始的长度是Capacity+1, 每个格子是U32类型，正常只要Capacity个格子就够表达需要的index， 多出来的一个是为了操作的安全和便捷。这个U32的数组被模拟成一个链表， 比如初始状态，header的值是0， 表示链表指向数据的第0个格子， 然后第0个格子中的值是1， 表示这个链表的next节点是下标1， 下标1的格子中内容是2，表示1的next是2，以此类推。 这样初始状态下， 这就是一个从0到Capacity的顺序的链表。你会发现初始状态下， 没有一个格子的next指向第0个格子， 为什么呢？因为已经有header指向了0了， 所以不会有第二个指针指向0了。

每次分配一个index的时候，其实就是把header的值分配出去，然后 header就指向了这个模拟链表的下一个节点。分配出去一个index的时候， 这个bucket[index]指向的内存块就相当于分配出去了。比如，初始状态下， 首次分配显然会分配0，header会指向1。

再比如极端情况，我分配Capacity次，header就指向了index列表的第Capacity格（base 0），也就是我们前面多分配的一个格子，最后一个格子， 示意图如下，已分配的格子被赋值成Capacity+1，指向链表尾，表示分配出去了：

![pool-allocator-allocated](/linkimage/iceoryx2/pool-allocator-allocated.png)

当内存释放给PoolAllocator的时候，会传递要释放的内存块的index，这个index会被插入模拟链表的表头， 具体操作的话是把当前header的值填入这个第index个格子， 然后把index赋值给header，新header就指向了第index格子。

假设刚才我们从0到Capacity分配出去了index值， 现在又从0到Capacity释放index，这时候新的header会依次经历指向0，指向1，指向2 ... 最终指向Capacity-1（base 0）格子。最终示意图如下：

![pool-allocator-backall](/linkimage/iceoryx2/pool-allocator-backall.png)

你会发现格子里面有0出现了， 但是没有了7，同样原因，这是因为这个时候header就是7.


#### 关系图
总结一下这一堆Allocator之间的对应关系，如下:

![allocator-relationship](/linkimage/iceoryx2/allocator-relationship.png)

即`iceoryx2_cal::shm_allocator::pool_allocator::PoolAllocator`依赖`iceoryx2_bb_memory::pool_allocator::PoolAllocator`, `iceoryx2_bb_memory::pool_allocator::PoolAllocator`又依赖一个`UniqueIndexSet`结构。

`UniqueIndexSet`结构实现index分配（也就是上面介绍的分配器原理），`iceoryx2_bb_memory::pool_allocator::PoolAllocator`因此能实现payload的内存地址的分配，`iceoryx2_cal::shm_allocator::pool_allocator::PoolAllocator`又因此能实现payload的offset值的分配。


### share_memory内存对象
#### bb层SharedMemory对象
现在先暂时忘记前面内存分配器，来从底往上梳理share_memory对象。
先是定义个`iceoryx2_bb_posix::shared_memory::SharedMemory`对象:
```rust
pub struct SharedMemory {
    name: FileName,
    size: usize,
    base_address: *mut u8,
    has_ownership: bool,
    file_descriptor: FileDescriptor,
    memory_lock: Option<MemoryLock>,
}
```
大概可以想到， 这个SharedMemory对应的就是一个共享内存文件。他具有如下接口：
```rust
impl Drop for SharedMemory {
    fn drop(&mut self) {...}
}

impl SharedMemory {
    pub fn does_exist(name: &FileName) -> bool {...}

    pub fn remove(name: &FileName) -> Result<bool, SharedMemoryRemoveError> {...}

    pub fn name(&self) -> &FileName {...}

    pub fn base_address(&self) -> NonNull<u8> {...}

    pub fn size(&self) -> usize {...}

    fn shm_create(
        name: &FileName,
        config: &SharedMemoryBuilder,
    ) -> Result<FileDescriptor, SharedMemoryCreationError> {...}

    fn shm_open(
        name: &FileName,
        config: &SharedMemoryBuilder,
    ) -> Result<FileDescriptor, SharedMemoryCreationError> {...}

    fn mmap(
        file_descriptor: &FileDescriptor,
        config: &SharedMemoryBuilder,
    ) -> Result<*mut posix::void, SharedMemoryCreationError> {...}

    fn shm_unlink(name: &FileName) -> Result<bool, SharedMemoryRemoveError> {...}
}
```
也就是对一个共享内存文件的实现。

#### cal层Memory对象
接着定义了一个`iceoryx2-cal::shared_memory::posix::Memory`对象, 这个对象很重要， 他把bb层的SharedMemory对象和cal层的ShmAllocator对象囊括在了一起。
```rust
#[derive(Debug)]
pub struct Memory<Allocator: ShmAllocator> {
    shared_memory: iceoryx2_bb_posix::shared_memory::SharedMemory,
    name: FileName,
    allocator: NonNull<AllocatorDetails<Allocator>>,
}

#[repr(C)]
struct AllocatorDetails<Allocator: ShmAllocator> {
    state: AtomicU64,
    allocator_id: u8,
    allocator: Allocator,
    mgmt_size: usize,
}
```
shared_memory字段就是bb层的一个SharedMemory对象，allocator就是cal层的一个ShmAllocator接口，我们从前面已经知道cal层的PoolAllocator就是实现了ShmAllocator接口的。
可见，cal层的Memory对象是一个自包含了内存和分配器的一个完备的内存对象。这个整合了内存分配器和内存对象的结构，对外表现的就是一块可以分配数据的内存， 因此他实现了以下SharedMemory接口：
```rust
/// Abstract concept of a memory shared between multiple processes. Can be created with the
/// [`SharedMemoryBuilder`].
pub trait SharedMemory<Allocator: ShmAllocator>:
    Sized + Debug + NamedConcept + NamedConceptMgmt
{
    fn allocate(&self, layout: std::alloc::Layout) -> Result<ShmPointer, ShmAllocationError>;

    unsafe fn deallocate(
        &self,
        offset: PointerOffset,
        layout: std::alloc::Layout,
    ) -> Result<(), DeallocationError>;
}
```
可以想象的是， 为了实现内存分配， 需要实现一个关键的步骤， 就是把SharedMemory对象的地址传递给ShmAllocator。另外再来看我们前面提到的一段话：
```
同时从new_uninit和init两个函数来说，iceoryx2_cal::shm_allocator::pool_allocator::PoolAllocator需要从外面输入内存基址base_address以及内存分配器allocator，这个base_address也就是待分配的连续内存块，allocator则是用于创建辅助数据结构的内存分配器。辅助数据结构的内存分配器也从外面传入，就可以实现base_address和辅助数据结构都在同一个共享内存对象/文件中。这样不同进程之间共享内存对象和内存分配器，就是完整的。
```
可以知道除了传递payload的地址，还要传递辅助数据结构的内存分配器， 这个辅助数据结构也是我们前面分析过的，一段index数组，有多少块payload就有（多少+1）格的index。那么这个辅助数据结构和payload数据，是如何在这块共享内存上布局的呢？是这样的：

![memory-layout](/linkimage/iceoryx2/memory-layout.png)

Memory对象内部会把内存分成3段， 第一段是AllocatorDetails结构，填充该共享内存本身的一些信息，包括allocator id， allocator指针，和payload起始地址的偏移量。第二段是辅助数据结构index列表，他以一个分配器的形式传给allocator。第三段是待分配的内存块，他把起始的地址传递给allocator。这样allocator如愿得到了index数组的内存分配器和内存块的地址。

补充一下，“第二段是index列表，他以一个分配器的形式传给allocator”， 这一段index列表也就是辅助数据结构是通过一个分配器的形式传给allocator的， 这个分配器实现的也是BaseAllocator接口（包含allocate和deallocate接口），其内部分配策略是一个相当简单的策略， 就是线性向上分配内存， 分配完为止，内存无法重复分配，释放内存则只释放一次，用来重置整段内存。对于index列表的场景来说， index列表是一次性分配整个数组，且不做释放， 所以这个简单的分配器就够用。 

#### 关系图

把内存的定义跟分配器的定义画到一起，大概是这样：

![memory-allocator-relationship](/linkimage/iceoryx2/memory-allocator-relationship.png)

(右键-在新标签页中打开图片，可以看得更清晰)

cal层的Memory对象整合了bb层的ShareMemory对象和cal层的PoolAllocator，组合成了一个自包含内存和分配器的完整的内存对象。


### service服务组件
#### 关系图
#### Service对象
#### ServiceState对象
#### Builder构建器


### publisher发布者组件
#### publisher数据结构
#### publisher的内存文件


### subscriber订阅者组件
#### subscriber数据结构


### zero_copy_connection零拷贝连接
#### SubscriberConnections订阅者连接
#### PublisherConnections发布者连接
#### 关系图
#### 动态维护连接

### 通信过程
#### 数据收发过程
#### 流程图

