---
title: SOA框架iceoryx原理解析
tags:
  - 通信
categories:
  - 架构
date: 2024-06-22 17:10:46
updated: 2024-06-22 17:10:46
---


## SOA框架iceoryx原理解析

### 简介

在我之前的一篇[微服务](https://yizhi.ren/2019/06/25/microservice/)的文章中曾经总结了微服务跟SOA的差异点和相同点，总结的结论如下：
```
差异可以归纳为：
SOA面向企业范围，微服务面向应用范围。
SOA带有异构集成的语义，微服务没有这个语义。
SOA服务内部支持组件分离的架构，微服务则是更彻底的组件分离架构-组件在网络上隔离。
```
基于这个总结，如果我们现在要写一套SOA服务框架，我们可以推导出这个框架的哪些特性呢？
> 从第一条中我们可以看出这套框架将是一个企业级别的框架，他不像微服务那样可以给每个服务灵活和独立的特性，SOA框架一旦推广使用，他就是企业级别的。

> 从第二条中我们可以看出，这个框架承担着异构集成的职责，异构集成简单讲就是适配加标准化公开这两点。展开来讲的话就是适配现有系统中的的专用数据格式、协议、传输机制，并使用标准化的机制将这些公开为服务。

> 从第三点上我们可以看出，这个框架所公开的服务，他们不一定像微服务那样一个服务与一个服务之间是网络隔离的，他们有可能是位于同一个主机上的，换句话说SOA的服务与服务之间可以网络隔离也可以网络不隔理。

这里面第一点可以认为是第二点的一个顺其自然的结果，由于各个服务都采用标准化的方式公开，那采用同一套框架是顺理成章的。所以下面我就只关注第二点和第三点。

这次要对其分析的这个框架叫iceoryx中文叫冰羚（其实就是对ice-oryx的翻译）。他是一个在特定领域（至少在智驾领域）很有名的SOA通信框架，在SOA特性的第二点和第三点特性中他都有很典型的体现，如下：
<!-- more -->

### 特性

#### 标准化服务
为了做到第二点标准化的服务公开，iceoryx首先要求每个服务提供服务描述信息，用来唯一标志服务网络中的一个服务；
其次规定了专用数据格式，必须使用用户预定义的结构体（注意iceoryx没有规定使用IDL，IDL是在DDS等别的框架中的要求），或者无结构（也就是二进制流），用户想要传递自己已有的结构，需要在收发前后做数据结构的转换和赋值，这点在各类通信框架中到并不特殊; 
再次，在传输机制上，iceoryx封装了较为复杂的消息编排和消息路由机制，确保消息是按照各异构服务提供方和消费方的要求做了保持或者丢弃，以及按需路由到了各个异构服务。要知道微服务是不做消息编排和路由的，这个也是SOA框架复杂麻烦的地方。即便只有一个服务需要这个特性，作为公司级的框架，你就不得不提供这个特性。

#### 同主机通信
为了做到第三点对同一主机上的不同服务进行通信，iceoryx直接把自己瞄准在了这个细分领域，专注于提供同一主机上的不同服务之间的通信，他没有提供对不同主机上的服务的通信能力，因此在实践上，往往是跟其他框架整合使用。由于限定在同一主机上，他可以提供远高于主机之间的通信吞吐和远低于主机之间的通信延迟。


### 架构
我们已经知道iceoryx具有提供标准化服务的能力以及高性能同主机通信的能力，那么我们来逐步分析和拆解iceoryx是如何来实现这些特性的，从架构到流程到实现，尽可能的了解他的内部设计。

![iceoryx logo](/linkimage/iceoryx/iceoryx_logo.jpg)
这个是他的logo，很漂亮，会让你忍不住想，这大概是个很酷的框架。

#### 进程模型
接下来首先来看一下iceoryx运行时候的进程模型：
![iceoryx process](/linkimage/iceoryx/iceoryx_process.jpg)
整个进程模型，包括3类角色，一个角色是RouDi，是一个中心进程节点，类似于Daemon进程，本身不属于业务进程，只是提供服务支持。RouDi的意思就是Route & Discovery，路由和发现，用来做消息路由和服务发现。
一个角色是Runtime，Runtime被集成到各个业务进程中，给进程提供服务集成的能力，根据使用方式不同，有的进程变成publisher，有的变成subscriber，有的既是publisher又是subscriber。
第三个角色是share memory，本身被RouDi创建和销毁，但被publisher和subscriber同时使用，被用来作为高效的数据传递介质。是其高性能的关键所在。

RouDi和Runtime之间通过domain socket（运行在Linux系统的话）通信，RouDi作为server，Runtime作为client。

### 交互

roudi与runtime的交互过程，首先是roudi要先启动，如果runtime先启动，会等待若干秒，等待roudi启动，等不到就退出。

```shell
2024-06-29 16:32:03.011 [Warning]: RouDi not found - waiting ...
2024-06-29 16:33:03.099 [ Fatal ]: Timeout registering at RouDi. Is RouDi running?
```

所以所有的交互过程都是基于roudi已经启动成功的情况，暂不考虑roudi晚启动的异常情况。

交互总共包括以下几个指令，`REG`、`CREATE_PUBLISHER`、`CREATE_SUBSCRIBER`、`CREATE_CLIENT`，`CREATE_SERVER`、`CREATE_CONDITION_VARIABLE`、`CREATE_INTERFACE`、`PREPARE_APP_TERMINATION`、`TERMINATION`，如下面的代码所示， roudi收到对应的命令后会进入对应的命令处理逻辑。

```c++
void RouDi::processMessage(const runtime::IpcMessage& message,
                           const iox::runtime::IpcMessageType& cmd,
                           const RuntimeName_t& runtimeName) noexcept
{
    // ...

    // 处理不同的命令
    switch (cmd)
    {
        case runtime::IpcMessageType::REG:
        {
            ...
            break;
        }
        case runtime::IpcMessageType::CREATE_PUBLISHER:
        {
            ...
            break;
        }
        case runtime::IpcMessageType::CREATE_SUBSCRIBER:
        {
            ...
            break;
        }
        case runtime::IpcMessageType::CREATE_CLIENT:
        {
            ...
            break;
        }
        case runtime::IpcMessageType::CREATE_SERVER:
        {
            ...
            break;
        }
        case runtime::IpcMessageType::CREATE_CONDITION_VARIABLE:
        {
            ...
            break;
        }
        case runtime::IpcMessageType::CREATE_INTERFACE:
        {
            ...
            break;
        }
        case runtime::IpcMessageType::PREPARE_APP_TERMINATION:
        {
            ...
            break;
        }
        case runtime::IpcMessageType::TERMINATION:
        {
            ...
            break;
        }
        default:
        {
            ...
            break;
        }
    }
}
```

#### REG 命令

`REG`命令是用来告诉roudi我runtime启动了，我的名字叫xx，我的其他信息是xxx，请记录。如果原先存在同名的runtime会在此时信息被更新。每个runtime因此必须有独一无二的name。

#### CREATE_PUBLISHER 命令
`CREATE_PUBLISHER`命令是告诉roudi，我要在xx这个runtime下创建一个publisher。roudi于是分配一片内存给这个publisher，这片内存是在专为publisher们准备的相同大小内存块的内存池中选取的一个，随后把这个内存的地址回复给runtime，这个地址本质上是一个offset值，不是一个真正的内存地址，因为roudi和runtime在不同进程，大家各自有各自的内存虚地址，我给你一个虚地址过去没有什么意义。在回复地址给到runtime之前，roudi还会同时做一个服务发现的工作，他会遍历当前已经存在的subscribers，把其中topic跟你这个publisher相同的subscriber选出来，这些subscriber，每一个也都绑定了一段专属的内存块，这些选出来的subscriber对应的内存块地址会被填入到publisher的专属内存地址中，一个存放subscriber信息的队列中。这样就完成了一个初始的服务发现的工作，publisher能够成功拿到当前有哪些关注我这个topic的subscribers。runtime拿到roudi的回复，就可以做后续的消息发布工作了。下面的代码反应了这个过程：

```c++
expected<PublisherPortRouDiType::MemberType_t*, PortPoolError>
PortManager::acquirePublisherPortData(const capro::ServiceDescription& service,
                                      const popo::PublisherOptions& publisherOptions,
                                      const RuntimeName_t& runtimeName,
                                      mepoo::MemoryManager* const payloadDataSegmentMemoryManager,
                                      const PortConfigInfo& portConfigInfo) noexcept
{
    return acquirePublisherPortDataWithoutDiscovery(
               service, publisherOptions, runtimeName, payloadDataSegmentMemoryManager, portConfigInfo)
        .and_then([&](auto publisherPortData) {
            PublisherPortRouDiType port(publisherPortData);
            this->doDiscoveryForPublisherPort(port);
        });
}
```

下面的图则描述了这个过程。

![publisher create flow](/linkimage/iceoryx/roudi_publish_create_flow.png)

(右键-在新标签页中打开图片，可以看得更清晰)

#### CREATE_SUBSCRIBER 命令

`CREATE_SUBSCRIBER`命令同`CREATE_PUBLISHER`类似的，roudi先是分配一段内存给这个subscriber，然后遍历全部的publisher，把这段内存地址的信息塞到相同topic的publisher的对应结构中去，如此完成初始的服务发现机制，然后把这段内存地址响应给subscriber，后续subscriber就可以根据这个信息去读取对应的数据。上图中在subscriber1的内存区域中有一个dat数组，就是存放publisher发过来的数据的。另外熟悉共享内存数据传递的同学应该知道，数据放在指定位置后，还得去做通知唤醒，告诉对方有新数据。不过呢`CREATE_SUBSCRIBER`这个命令不负责这件事，但又做了部分的工作。当RouDi把subscriber的内存信息塞到publisher的对应结构中时，随同一起塞入的还有一个指针，指向通知器，只不过这个时候这个指针是空指针，也就是压根不会做通知。不做通知的话subscriber怎么读消息的，答案是轮询，这个场景也是合理的，轮询在适当场景下有更佳的性能。

```
template <typename ChunkQueueDataProperties, typename LockingPolicy>
struct ChunkQueueData : public LockingPolicy
{
	//...
    RelativePointer<ConditionVariableData> m_conditionVariableDataPtr; // 默认是空指针
    optional<uint64_t> m_conditionVariableNotificationIndex;
};
```

#### CREATE_CONDITION_VARIABLE 命令
`CREATE_CONDITION_VARIABLE`命令的作用就是创建一个通知器，当用户代码中创建一个Listener, 他就会发送`CREATE_CONDITION_VARIABLE`的命令，然后在用户代码中调用listener的attachEvent函数，完成subscriber与通知器的绑定，上面`CREATE_SUBSCRIBER`命令介绍中提到的通知器指针，就会在这个时候被赋值，这样每次subscriber有新数据到来就会通知用户指定的回调。

```c++
     listener
         .attachEvent(subscriberLeft,
                      iox::popo::SubscriberEvent::DATA_RECEIVED,
                      iox::popo::createNotificationCallback(onSampleReceivedCallback))
         .or_else([](auto) {
             std::cerr << "unable to attach subscriberLeft" << std::endl;
             std::exit(EXIT_FAILURE);
```

#### TERMINATION 命令
`TERMINATION`命令发生在Runtime进程退出的时候，RouDi收到后会做一些清理操作，包括从订阅关系中移除这个进程，以及从进程列表中移除这个进程。如果Runtime进程异常退出，没来得及发送这个命令，那么这些清理操作将会发生在进程与RouDi心跳超时之后。

#### KEEPALIVE 命令
关于心跳这个命令，在iceoryx的`release_2.0`分支下是一条独立的命令`KEEPALIVE`, 由runtime定时发送给RouDi，但是在master分支下，已经取消了这个命令，而是在REG命令处理的时候直接分配一段内存存放心跳信息，后面Runtime直接向这块内存更新心跳信息。

#### 其他命令
此外其他的命令我在使用订阅发布机制的情况下并没有观察到，这里我不做描述，可以自行查阅代码，就在`RouDi::processMessage`这个函数里面。



## RouDi

### 功能入口

roudi的代码入口在`iceoryx_posh\source\roudi\application\roudi_main.cpp`. 做的事情简单说是从配置文件加载配置，然后传入IceOryxRouDiApp类，并启动。

```
int main(int argc, char* argv[]) noexcept
{
    using iox::roudi::IceOryxRouDiApp;

    ...

    IceOryxRouDiApp roudi(config.value());
    return roudi.run();
}

```

### 创建内存

RouDi在启动的时候做的最重要的一件事情是创建共享内存，他是怎么来创建的呢？

#### 对象关系

首先来找出创建内存相关的类或对象，我根据源码上的类关系，梳理成下面的类（或者对象）关系：

```shell
IceOryxRouDiApp
	├ IceOryxRouDiComponents
	|	├ IceOryxRouDiMemoryManager
	|	|	├ DefaultRouDiMemory
	|	|	|	 ├ introspectionMemPoolBlock
	|	|	|	 ├ discoveryMemPoolBlock
	|	|	|	 ├ heartbeatPoolBlock
	|	|	|	 ├ segmentManagerBlock
	|	|	|	 └ PosixShmMemoryProvider
	|	|	|		 └ vector<MemoryBlock*>
	|	|	├ portPoolBlock
	|	|	├ PortPool
	|	|	└ RouDiMemoryManager
	|	|		 └ vector<MemoryProvider*>
	|	└ PortManager
	|		├ PortPool
	|		└ IceOryxRouDiMemoryManager
	|
	└ RouDi
		├ IceOryxRouDiMemoryManager
		└ PortManager
```

1. 这里面两处`PortManager`是引用同一个，两个`PortPool`也是引用的同一个，三处`IceOryxRouDiMemoryManager`也是引用的同一个。

2. 这里面多个Block都是继承`MemoryBlock`基类，并最终被放到`vector<MemoryBlock*>`这个数组里面；

3. 这几面`PosixShmMemoryProvider`是继承`MemoryProvider`接口的，并最终被放到`vector<MemoryProvider*>`这个数组里面。

这个关系中还是看不出重点，我们来看一下初始化之后这些类（或者对象）的关系变成什么样：

```shell
IceOryxRouDiApp
	├ ｛IceOryxRouDiComponents｝
	|	├ 【IceOryxRouDiMemoryManager】
	|	|	├ PortPool
	|	|	|	└ PortPoolData
	|	|	└ RouDiMemoryManager
	|	|		 └ vector<MemoryProvider*>
	|	|			└ PosixShmMemoryProvider
	|	|				└ vector<MemoryBlock*>
    |   |   	   			├ introspectionMemPoolBlock
    |   |					├ discoveryMemPoolBlock
    |   |					├ heartbeatPoolBlock
    |   |					├ segmentManagerBlock
    |	|					└ portPoolBlock
    |	|						└ 【PortPoolData】
	|	└ ｛PortManager｝
	|		├ PortPool
	|		└ IceOryxRouDiMemoryManager
	|
	└ ｛RouDi｝
		├ IceOryxRouDiMemoryManager
		└ PortManager
		

｛｝和【】用来标记关键的类和对象
```

可以看出，这里面`IceOryxRouDiMemoryManager`下面挂了（引用了）一大堆的东西，有port相关的有block相关的；而反过来被多个对象引用的则是`PortPoolData`，直接或间接地被`PortManager`、`IceOryxRouDiComponents`、`RouDi`引用。因此这里面最核心的类就是`IceOryxRouDiMemoryManager和PortPoolData`了。`IceOryxRouDiMemoryManager`在这里的作用是什么呢，他是负责创建`PortPoolData`和其他的内存的。

这样就串起来了：`PortManager`、`IceOryxRouDiComponents`、`RouDi`引用`IceOryxRouDiMemoryManager`和`PortPoolData`，而`IceOryxRouDiMemoryManager`又是创建`PortPoolData`和其他的内存块。

#### 内存分配

触发内存分配的函数调用来自`IceOryxRouDiMemoryManager::createAndAnnounceMemory()`, 并最终调用到`MemoryProvider::create()`, `PosixShmMemoryProvider`继承自`MemoryProvider::create()`，因此调用的也同时是`PosixShmMemoryProvider::create()`。如下：

```c++
IceOryxRouDiMemoryManager::createAndAnnounceMemory()
	└> RouDiMemoryManager::createAndAnnounceMemory()
		└> MemoryProvider::create()
```

`MemoryProvider::create` 内部做了两件事，一个是计算出他下面挂的`vector<MemoryBlock*>`中全部block所需的内存之和，并向系统申请一整块的内存，由于我们在`PosixShmMemoryProvider`类中，因此他申请内存的方式就是使用共享内存，在linux中就会在/dev/shm/下面创建一个共享内存文件，叫TODO(shm文件名)。另一个事是从这一大片内存中切切切，切一段给这个MemoryBlock，切一段给那个MemoryBlock，切的时候都是字节对齐的，也是一段接一段连续地切的。当前，申请内存的时候已经计算上字节对齐所需要的额外的字节数的。

```c++
expected<void, MemoryProviderError> MemoryProvider::create() noexcept
{
    // ...
    for (auto* memoryBlock : m_memoryBlocks)
    {
        // ... 累加总的内存大小
        totalSize = align(totalSize, alignment) + size;
    }
	// ... 一次性申请总的内存
    auto memoryResult = createMemory(totalSize, maxAlignment);

    // ... 内存分配器用来切内存
    iox::BumpAllocator allocator(m_memory, m_size);

    for (auto* memoryBlock : m_memoryBlocks)
    {
        auto allocationResult = allocator.allocate(memoryBlock->size(), memoryBlock->alignment());
		// ... 切出来的一段内存分配给对应的memeoryblock
        memoryBlock->m_memory = allocationResult.value();
    }

    return ok();
}
```



注意这里只是申请了内存，可以认为是一段裸的内存。由于iceoryx设计上是不允许重复使用共享内存文件的，每次启动都会去清理旧的内存并新建新内存，因此这里的共享内存文件一定是新创建的，并被自动初始化为全零，这是shm_open默认的行为TODO(get doc link from ipc code)。



#### 内存初始值填充

内存在上面被创建以后，初始内存是被初始化为0，接下来就需要做内存值的填充。

```c++
IceOryxRouDiMemoryManager::createAndAnnounceMemory()
	└> RouDiMemoryManager::createAndAnnounceMemory()
		├> MemoryProvider::create()						// 创建内存
		└> MemoryProvider::announceMemoryAvailable()	// 初始值填充
```

`announceMemoryAvailable`函数做的事情，就是依次调用他下面挂的`vector<MemoryBlock*>`中每个block的`onMemoryAvailable`函数，如下：

```c++
void MemoryProvider::announceMemoryAvailable() noexcept
{
    if (!m_memoryAvailableAnnounced)
    {
        for (auto memoryBlock : m_memoryBlocks)
        {
            memoryBlock->onMemoryAvailable(memoryBlock->m_memory);
        }

        m_memoryAvailableAnnounced = true;
    }
}
```

最终结果是每个`MemoryBlock`的`onMemoryAvailable`函数被触发，每个`MemoryBlock`负责把自己负责的那片内存进行初始化。










### Runtime
