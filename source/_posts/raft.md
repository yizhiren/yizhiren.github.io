---
title: raft 协议解析
tags:
  - 分布式
categories:
  - 架构
date: 2020-12-20 00:04:00
updated: 2020-12-20 00:04:00
---

# raft 协议解析



## 高可用的实现方案总结

在工程实践中，高可用的方案有很多，例举几个，大家一定知道大部分的名词：主备，双备，HAProxy, F5, VRRP，Sentinel， gossip， paxos等。

这一系列的技术方案，可以简化和归纳成两类：一类可以叫哨兵， 如图以haproxy为例：

![haproxy](/linkimage/raft/haproxy.png)

图片来自 [Using HAProxy with the Proxy Protocol to Better Secure Your Database](https://www.haproxy.com/fr/blog/using-haproxy-with-the-proxy-protocol-to-better-secure-your-database/)

这一类方案，有个共同点，都有一个类似哨兵的角色，细化的讲，有的叫proxy，有的叫gateway，有的叫monitor，有的叫sentinel，有的叫router，他们的作用都是类似的，就是感知并屏蔽内部不健康的主机，并对外提供一个始终可用的服务。完成高可用的目的。


另一类技术方案，可以叫一致性协议，如图基于gossip的redis cluster为例：

![rediscluster](/linkimage/raft/rediscluster.jpg)

图片来自 [微服务](https://yizhi.ren/2019/06/25/microservice/) 

这一类方案，也有一个共同点，就是都实现了一种内部节点之间的通信协议，协议能够发现异常节点，并且在内部通过某种机制来容错，不需要依赖外部的角色。 一致性协议的实现高可用的机制，最重要的一点就是半数同意的机制，因此能容忍半数-1的节点宕机。

<!-- more -->

有的人说哨兵类的都是无状态的服务，一致性协议的都是有状态的服务，并不是这样。有状态的服务一样可以用哨兵类的方案, 比如一致性hash的方案就是有状态的.

![consistent_hash_proxy](/linkimage/raft/consistent_hash_proxy.png)

图片基于 [一致性Hash原理与实现](https://www.jianshu.com/p/528ce5cd7e8f)

这偏文章重点关注一致性协议，下面简单列举常见的一致性协议。

## 一致性协议



### gossip

```
来自： https://www.jianshu.com/p/8279d6fd65bb
Gossip 过程是由种子节点发起，当一个种子节点有状态需要更新到网络中的其他节点时，它会随机的选择周围几个节点散播消息，收到消息的节点也会重复该过程，直至最终网络中所有的节点都收到了消息。这个过程可能需要一定的时间，因为不能保证某个时刻所有节点都收到消息，但是理论上最终所有节点都会收到消息，因此它是一个最终一致性协议。
```
![gossip](/linkimage/raft/gossip.gif)

图片来自 [P2P 网络核心技术：Gossip 协议](https://zhuanlan.zhihu.com/p/41228196)

如redis cluster内部使用gossip进行通信，他借助gossip实现高可用的方案如下：
当A节点检测不到B的时候，A会把B的不可用状态通过gossip协议进行传播，此时B只是在A看来主观下线，当半数以上节点都认为B不可用时就认为B真的不可用了，此时B处于客观下线状态，下线状态通过消息继续传播，那么所有节点都会认为B已经不可用。之后B的备节点就会参与选举，经过半数同意后选举成功，新节点接替B节点继续工作。

### paxos
paxos协议提交一项决议需要经过两个阶段，他每经过一个两阶段提交过程，就会在集群中达成一个条目，或者说达成一个一致的意见。多个这样的过程就可以达成多个结果。
整个过程包含prepare和accept两个阶段。

>  prepare过程是A节点广播某个提案即发送prepare请求，如果其他节点接受了就回复promise，否则回复error；
> 这时候A会整理这些回复，如果回复的promise超过一半，那么prepare过程就成功了，可以继续下一个过程。

> 接着他就给这些回复promise的节点广播一个propose消息，如果节点接受，就回复accept，否则回复error；
> 这时候A就再次整理这些回复的accept，如果超过一半就完成了这个协商的过程，A就会把这个结果告诉给所有关注这个结果的人(learner)。

![paxos_stage](/linkimage/raft/paxos_stage.png)

图片来自 [一致性算法 Paxos](https://www.cnblogs.com/Chary/p/13950387.html)

同样这个协议中也穿插着半数同意的条件。

那么为什么要用两个过程而不是一个，是因为：一个提案是一个(编号，值）对，各个节点并没有规定只能给一个提案回复promise，只要编号更大就会回复promise，所以在完成一轮交互前，那些节点可能又转而给别的提案回复了promise，于是这就需要第二轮交互来确保大部分节点并没有给别的提案回复promise。
那第二轮之后会不会那些节点又给别的提案发了promise呢，还是会的(只要prepare的编号更大)，那怎么办呢，办法是加约束：一旦某个节点B给提案X回复了accept，那么他就会记录下他已经投给了X，下次收到一个提案Y的时候，B在回复promise的同时会带上自己已经accept过的提案X的信息，B在看到已经有了accept过的提案了，那么B就会把自己的提案的值改成已经accpet的提案（中的最大值），并继续后面的过程。这样就不会使用B原先自己的提案值了，并且加速了投票结果的收敛。也就是说提出提案的这个节点是不会一直坚持自己的提案的值的，而是会轻易的转变自己的想法。

这个约束满足P2c约束：

>```
>https://zh.wikipedia.org/zh-cn/Paxos%E7%AE%97%E6%B3%95
>P2c：如果一个编号为 n 的提案具有 value v，该提案被提出（issued），那么存在一个多数派，要么他们中所有人都没有接受（accept）编号小于 n 的任何提案，要么他们已经接受（accept）的所有编号小于 n 的提案中编号最大的那个提案具有 value v。
>```

![paxos_flow](/linkimage/raft/paxos_flow.png)

图片来自 [Paxos协议初探](https://www.jianshu.com/p/0ba4d0e03a71)



### raft
raft协议跟paxos不同，paxos一次只能提交一个结果，raft则不同。
raft首先通过一个选举过程选出谁是这个集群的leader，之后所有的更新操作都有leader来发起，leader在发起的同时把操作通过日志的方式源源不断的发给其他节点，leader跟每个节点保持一个连接，因此leader发给每个节点的日志都可以做到有序，同时每个节点收到的日志的进度是不同的。当超过一半的节点都确认收到了某个日志后，这个日志以及之前的所有日志都被认为是已经提交的，已经提交的日志是不可变的，是可以安全的使用的，后面不会再删除或者变更。因此commit后就可以认为这条日志写入成功。

![raft_req_res](/linkimage/raft/raft_req_res.png)

图片来自 [Raft算法 二 如何复制日志](https://yfscfs.gitee.io/post/%E6%9E%81%E5%AE%A2%E6%97%B6%E9%97%B4%E4%B9%8B%E5%88%86%E5%B8%83%E5%BC%8F%E5%8D%8F%E8%AE%AE%E4%B8%8E%E7%AE%97%E6%B3%95%E5%AE%9E%E6%88%98-08-raft%E7%AE%97%E6%B3%95-%E4%BA%8C-%E5%A6%82%E4%BD%95%E5%A4%8D%E5%88%B6%E6%97%A5%E5%BF%97/)

强leader的机制下leader的选举就是一个重要的过程。选举是基于日志的新旧来决定的，拥有更新的日志的节点就能拥有更多的选票，但并不一定是拥有最新的日志的那个成为leader，因为投票的规则就是如果你的日志比我新我就投给你，但是一轮投票中只允许投给一个，先到先得。这样一轮投票中票数总数是有上限的，最多就是每个节点一票。拥有超过一半的票数就可以确保拥有了最多的票数，也就可以成为这一轮的leader。如果都没有达到过半，就超时进入下一轮。


### zab
zab是zooker中用来做一致性保证的协议，他的思路也是先选出leader，然后由leader来做出所有的更新操作，并同步给follower，过程跟raft差不多。
zab的选举过程跟raft有些差异，在一个选举周期内，每个节点可以重复给别的节点投票，只要他收到了来自更优条件的投票请求，更优的条件是指有更大的zxid（由epoch+sequence组成），zxid相等则有更大的服务器id。
同时每个节点会把自己的投票信息广播出去，同时会保存下来其他节点广播过来的投票信息，如果一个节点发现有超过一半的节点赞成了自己的投票，也就是跟自己投的是一样的，那么他就会结束投票，并把自己的状态相应的更新成follower或者是leader。

如下图是第一轮投票的通信情况，3个节点都投给自己，通信中的(x,y,z)表示（本机节点id，投给的节点id，投给的节点的wxid）；方框内（a,b)代表这个节点的投票箱中记录的投票信息a投给了b。

![zab_election](/linkimage/raft/zab_election.png)

图片来自 [实例详解ZooKeeper ZAB协议、分布式锁与领导选举 ](https://www.sohu.com/a/214834823_411876)

所以如果拥有最优条件的leader跟别的节点连通良好的话最后选出来的肯定是他。
那如果连通不好呢，比如网络不畅。比如在刚选出leader的时候，一个更优的节点突然加入。则会导致大家又开始投票，如果大部分节点此时都已经结束这一轮投票了，那么这个新加入的就成不了leader，因为他问一遍后发现大家都已经投给了别人，那他就会认同那个leader，如果大部分节点还没结束投票即还没统计出半数统一的结果，那么最终这个新节点会当上新的leader。等价的场景包括，拥有更优条件的节点网络连接不畅，很晚才跟大家连上；leader挂掉后重启；



下面在重点展开讲一下raft协议细节。




## raft协议

前面大概讲了下，raft是一个强leader的协议，leader负责写入日志，并把日志源源不断传给follower。

下面我们分别从选主、日志复制、安全性、成员变更，日志压缩这几个点来展开了解一下raft的细节。

注：如无特别标注，以下图片均来自 [In Search of an Understandable Consensus Algorithm](https://raft.github.io/raft.pdf)

### 选主

raft集群中每个节点在初始时是平等的，谁都可能成为主，但是最开始时谁都不是主，那是什么呢？是follower。

每个follow会独立的配置一个（一定范围内的）随机的超时值。然后如果在这个超时值内没有收到leader发来的心跳，那么这个follower会变身成为candidate，这是节点的第二种身份，candidate会给别的节点广播选举自己为leader的请求，如果收到[同意]的节点数（包括自己）超过一半，那么candidate就会顺利成为leader，这是节点的第三种身份，成为leader后就会定时发送心跳给其他的节点，这个心跳包有两个作用，一个是传递日志信息，一个是可以抑制其他节点成为leader和candidate。

怎么抑制的呢? 当你处于follower的时候，如果收到了leader的心跳，follower就会继续安心的做一个follower；candidate如果收到leader的心跳，也会继续变回follower。

![raft_states](/linkimage/raft/raft_states.png)

现在看着这个图大概就能明白状态是怎么变化的了。

当一个节点成为leader后，他会拥有几个比历史leader都要更高的term，在之后他当leader的周期内所有的log和心跳都会打上这个term标记，leader的follower们也会记录这个term。那这个term是什么时候调大的呢，就在一个candidate发起选举的时候。每个candidate独立变更term，无需全局唯一。

![raft_term](/linkimage/raft/raft_term.png)

那么可以想象，如果你收到了一个心跳，里面携带了更高的term，那么就代表对方有比自己更新的周期，这个时候自己就会立刻转成follower（如上面状态图文字所描述），即使你是leader，遇到更高term的请求还是要降为follower。

如果一轮选举选不出leader，比如上图的t3，那么就会再选一轮，对应上面状态图中有一个candidate到candidate自己的箭头，这种情况是发生在一个candidate选举中如果没有在一个选举超时周期内达到半数同意，并且又没有leader的心跳收到，那么就会进入新一轮的选举。

那么一个节点到底什么情况下会投票给另一个节点呢？

raft规定一个节点只会投票给拥有比自己更新的日志的节点。更新的日志的定义是：term更大，或者term相等并且index更大。一个candidate在vote请求中会携带自身拥有的最新的那个日志的index和term，收到vote的请求的节点如果觉得请求中的log信息更新，就会投给他，否则不投给他。

那么一个节点的RequestVoteHandler的实现大概如下：

```go
func (self *Raft) RequestVoteHandler(args *RequestVoteArgs, reply *RequestVoteReply) {
    // 当前term不够大
    if (args.Term < self.currentTerm) {
        reply.Term = self.currentTerm
        reply.VoteGranted = false
        return
    }

    // 已经投给了其他节点了
    if args.Term == self.currentTerm &&
        self.votedFor != -1 && 
        self.votedFor != args.CandidateId {
        reply.Term = self.currentTerm
        reply.VoteGranted = false
        return      
    }

    // 更大的term立即成为follower
    if args.Term > self.currentTerm {
        self.convertToFollower(args.Term)
    }

    lastLogIndex := self.lastLogIndex
    lastLogTerm := self.lastLogTerm
    //日志的term不够大
    if (args.LastLogTerm < lastLogTerm) {
        reply.Term = self.currentTerm
        reply.VoteGranted = false
        return  
    }
    
    // 日志的index不够大
    if (args.LastLogTerm ==lastLogTerm) &&
       (args.LastLogIndex < lastLogIndex) {
        reply.Term = rf.currentTerm
        reply.VoteGranted = false
        return
    }

    // 停止超时定时器
    self.resetCandidateTimer()
    self.resetReCandidateTimer()
  
    // 投给他
    self.votedFor = args.CandidateId
    reply.Term = self.currentTerm
    reply.VoteGranted = true
    self.persist()
}


```



同时raft为了加快投票的收敛速度，通过随机化选举超时的时间来错开选举的时间(如果有办法能让日志越新的越早触发就更好了）。在leader出问题后，拥有最小随机值的节点会最先触发选举，随后其他节点就会投票给这个节点，raft规定一个节点在一轮投票中只能投给一个节点，因此只要拿到了一半选票，就可以认为选举成功了。



### 日志复制

在选举出leader之后，后面的过程就是leader源源不断把日志复制给follower的过程了。

我们先来看一下一个节点的内部组成：

![state_machine](/linkimage/raft/state_machine.png)

每个节点都有3部分组成，一个是负责处理一致性协议的，一个是负责存储log的，一个是状态机。

一个写入过程对应的就是图中的1，2，3.

1. client把写入请求发给leader server，server中的一致性模块收到请求。

2. 一致性模块把请求打包成一个log entry，写入本地log store，并把log entry发给follower。

   follower的一致性模块收到log entry后写入他的本地log store，随后返回成功给leader。

3. leader统计到超过一半的节点写入成功后，把这条日志变成commited状态，并交给状态机进行apply log。

4. 第四步并非上图中的4，而是leader在随后的心跳中把commit信息下发下去，follow的一致性模块收到心跳后，发现前面写入log store的日志已经处于commit状态了，就吧log交给状态机进行apply。

可以看到follow apply log的时间会稍微晚于leader。

而读取的过程就是上图中的4了，读取的过程不需要经过一致性模块，读取数据直接从状态机查询结果即可，状态机存储的就是log 按序apply后的一个最终结果。

leader给follower下发log的时候，leader给每个follower分别维护了一个连接+当前follower的进度，所以不同的follow接收日志有快有慢，但是每一个follow接收到的log都是有序的。

![raft_logs](/linkimage/raft/raft_logs.png)

那么如果网络不畅，leader发过去的几个请求乱序了，follower这边怎么能做到不乱序呢？

```go
type AppendEntriesArgs struct {
	Term int
	LeaderId int
	PrevLogIndex int
	PrevLogTerm int
	Entries []Entry
	LeaderCommit int
}
```

就是通过这个结构中的PrevLogIndex和PreLogTerm，follow收到leader下发的log请求后，先判断这个请求的term够不够大, 不够就打回，够了再进行下一步：

~~~go
	if args.Term < self.currentTerm {
    reply.Term = self.currentTerm
    reply.Success = false
    return
	} else {
    // 停止超时定时器
    self.resetCandidateTimer()
    self.resetReCandidateTimer()
    self.convertToFollower(args.Term, args.LeaderId)
	}

~~~

接着follower把本地log store的指针指到PrevLogIndex的位置，然后检查下这个本地log的term跟请求中的term是不是一致，一致的话就遍历Entries并与本地log比较，一旦发现不一致了，就从不一致的地方开始覆盖掉本地的日志。

![log_apped](/linkimage/raft/log_apped.png)

~~~go
	unmatch_index := -1
  // 找出req和local不一致的日志的index
	for req_log_index := range args.Entries {
    localCheckIndex := args.PrevLogIndex + 1 + req_log_index
    if (localCheckIndex >= len(self.log)) || 
      (self.log[localCheckIndex].Term != args.Entries[req_log_index].Term) {
      unmatch_index = req_log_index
      break
    }
  }
	
	if unmatch_index != -1 {
    // 用req的log覆盖本地log
    self.log = append(self.log[:args.PrevLogIndex+1+unmatch_index],
      args.Entries[unmatch_index:]...)
	}

~~~



那么如果term不一致呢？

这时候follower返回一个错误，告知leader这个位置不对：

```go
type AppendEntriesReply struct {
	Term int
	Success bool
	ConflictIndex int
	ConflictTerm int
}
```

leader可以根据自己的实现把PrevLogIndex往前推若干的位置，然后再次下发给follower。



### 安全性

问题一: `日志安全性`。

在讲完选举和日志复制后，最疑惑大家的应该就是日志的安全性，你要怎么确保commit了的log不会被新的leader覆盖掉呢？

有兴趣的可以看完整的证明：

```bash
中英对照：
Suppose the leader for term T (leaderT) commits a logentry from its term, but that log entry is not stored by theleader of some future term. Consider the smallest term U>T whose leader (leaderU) does not store the entry.
假设term T的一个leader commit了一个log，然后存在一个term U的leader，这个leader不存在这个log。我们取U为大于T且不存在这个log的所有term中最小的那个。
下面我们要在这个假设下推导出矛盾来证明不可能存在这种情况。


1. The committed entry must have been absent from leaderU’s log at the time of its election (leaders neverdelete or overwrite entries).
这个committed的log在leaderU选举时一定已经不存在U上了，因为leader不会自己删log，所以不存在leaderU选上leader后自己删掉log的可能性

2. leaderT replicated the entry on a majority of the clus-ter, and leaderU received votes from a majority ofthe cluster. Thus, at least one server (“the voter”)both accepted the entry from leaderTand voted forleaderU. The voter is key toreaching a contradiction.
leaderT把log下发给了大多数，leaderU又得到了大多数的投票，所以至少存在一个节点是同时得到了log也投个了leaderU的，这个节点我们叫他voter，是推导出矛盾的关键。

3. The voter must have accepted the committed entry from leaderT before voting for leaderU; otherwise it would have rejected the AppendEntries request from leaderT(its current term would have been higher thanT).
这个voter在给leaderU投票前一定已经拿到log了，不然如果先投票了的话，voter就会保存下来这个这个term U并拒绝leaderT发过来的log，因为这个log的term太低了。

4. The voter still stored the entry when it voted for leaderU, since every intervening leader contained the entry (by assumption), leaders never remove entries,and followers only remove entries if they conflictwith the leader.
voter在给U投票时一定还是持有着log的，因为我们前面假设了U是第一个比T大且不持有log的leader，因此T->U中间的leader都是持有log的，而leader是不会丢弃log的，follower也不会覆盖跟leader一致的log，只会丢弃跟leader冲突的log（及其后面的log）。所以在给U投票时，一定是持有log的。

5. The voter granted its vote to leaderU, so leaderU’s log must have been as up-to-date as the voter’s. This leads to one of two contradictions.
leaderU得到了voter的投票，那么leaderU的日志一定是新于或者等于voter的日志的。这会带来冲突。

6. First, if the voter and leaderU shared the same last log term, then leaderU’s log must have been at leas tas long as the voter’s, so its log contained every entry in the voter’s log. This is a contradiction, since thevoter contained the committed entry and leaderU was assumed not to.
首先，如果U的最新的日志跟voter的最新日志是同一个term，那么U的日志index一定是大于等于voter的才能得到选票，这于U不存在log的假设不符。

7. Otherwise, leaderU’s last log term must have been larger than the voter’s. Moreover, it was larger thanT, since the voter’s last log term was at least T (it con-tains the committed entry from term T). The earlier leader that created leaderU’s last log entry must have contained the committed entry in its log (by assumption). Then, by the Log Matching Property, leaderU’s log must also contain the committed entry, which is a contradiction.
那么，如果U的最新的日志比voter的最新日志新，说明T到U中间存在别的leader，这时候中间的leader一定是拥有这个log的，因为我们假设了U是大于T且不存在log的最小的U，所以T->U中一定是包含log的。那么U成为leader后不会删除log的，所有U也包含log，这跟假设U不包含log不符。

8. This completes the contradiction. Thus, the leaders of all terms greater than T must contain all entries from term T that are committed in term T.
所以大于termT的周期中一定包含T周期中提交的log。

9. The Log Matching Property guarantees that future leaders will also contain entries that are committed indirectly。
某个log commit后，index小于这个log的日志也被间接提交，这些间接提交的log也一定包含在将来的leader中。
```

简单的证明可以这么理解，因为一个log被提交，说明大于一半的节点都拿到这这条日志；这时候一个节点发起投票，如果他持有的log小于这条log，那么必然会被持有这条log的节点拒绝，无法成为leader。只有拿到这个log的节点才有可能拿到超过一半的投票数。



问题二: `term过大问题`。

不知道你有没有这个疑问，如果集群中一个节点发生了网路隔离，那个这个节点就会发起选举，因为网络隔离，他会一直选举失败，于是一直尝试选举，term一直增大，一段时间后term会很大。

然后这时候网络恢复，那么这个节点的选举请求会被别的节点收到，别的节点看到一个那么大term的请求，就会纷纷觉得自己状态太旧了，纷纷成为follower。可以对照着这个状态图再看看。

![raft_states](/linkimage/raft/raft_states.png)

那么一个疑问是，这个那么大term的节点会成为leader吗，他的term很大，log数也可能很大（如果隔离前他是leader的话）。如果成为了leader，它的日志岂不是跟大家的很不一样？答案是不会成为leader。

如果隔离前是follower，那么现在他的日志数不够多，如果隔离前是leader的话，现在他的日志的term不够大。怎么样都不会成为leader。但是他造成了一波leader选举是肯定了，他让所有节点都接受他这个大term，然后重新选出leader。

解决方案就是抑制term的增加，通过引入prevote阶段。

一个candidate在发起vote之前，先要发起一个prevote，其他节点按照vote相同的条件给出判断是否同意，如果半数以上同意，candidate才把term加1，并发起vote，这样发生网络隔离后，节点只能一直发起prevote而无法增加他的term。



问题三: `破坏者问题`。

我们总是假设每个raft节点都是符合设计的，没有恶意的。那么假设有个节点充满恶意或者程序异常了，总是用一个很大的term来触发选举，那怎么办呢？prevote阻止了一个善意的节点去随意触发选举，但是却没法阻止一个恶意的节点触发选举。

这时候raft引入了一个冷却时间，来避免轻易触发选举。每个follower在收到leader的心跳或者append entries消息时，会记下当前时间，然后在一个较短的时间内不会投票给任何人，只要leader不断有消息发给follower，那么follower就不会投给别人，这样恶意发起投票的就没法扰乱集群。

那么leader收到这样的恶意请求后会怎么样呢？还是会降为follower的，为什么呢，因为如果不降，就无法实现主动的leader抢占或者说切换了。只不过这个行为实际上也就导致了破坏者破坏成功。leader降为follower后，后续不再心跳给follower，必然触发选举。

所以就破坏者这一点来说，目前raft没有能力做到恶意选举的规避，只是做了一定的防御，并没有杜绝。

```c++

        int64_t votable_time = _follower_lease.votable_time_from_now();
        // votable_time为0代表过了冷却时间，大于0代表剩下的冷却时间
        // 对于leader来说votable_time始终是0
        if (request->term() >= _current_term && votable_time == 0) {
            ...
            if (request->term() > _current_term) {
                // 降为follower
                step_down(request->term(), false, status);
            }
        } else {
            // ignore older term
            break;
        }
```
参考braft的实现，可以看到当term足够大的时候，对于follower来说，在冷却时间内是会忽略选举请求的，对于leader则不会，直接降为follower。




问题四：`leader只能commit自己term的日志`。

前面讲了日志分发到大部分就可以commit了，但是并不完全这样，有个条件是leader只能在自己term周期的log分发到了大部分的时候才能commit自己周期内的这个log（和他之前的所有log），不能像这样：统计到前面周期的log达到大部分了就把这部分log提交一下。

![commint_log_term](/linkimage/raft/commint_log_term.png)

我们看上图中的c，其中S1是第四代leader，S5是第三代leader，log2是第二代leader分发下去的，他刚分发3个没来得及commit就挂了。这时候S1发现log2已经分发到了大部分的节点S1S2S3，但是log2不能commit。因此此时如果S1宕机，S5就可能选为leader，因为他的最新日志的term比较大。S5成为leader后就会把日志2都给刷掉，所以log2并不安全，不能提交。

这里本质上是log2是上上代的leader写入的日志，已经隔代了，可能被中间某一代的leader的日志给覆盖掉。

所以leader可以安全的commit的条件是这个写入大部分节点的日志是自己这一代的日志（其实前一代的也是可以的，只要不隔代）。

### 日志压缩

大家在看前面的内容的时候，肯定也想到一个问题，log一直存不是越来越多了嘛，那什么时候能删掉呢？

万一删掉后，有个节点本地log全丢了，不就没办法还原全部日志了吗，那怎么办呢？

答案就是日志压缩：

![log_compaction](/linkimage/raft/log_compaction.png)

上图中原本是1-7这7个日志，可以经过压缩，变成snapshot+日志，snapshot是前面已经提交的1-5这5个日志。

snapshot里面包含两个方面的内容，一个内容就是已经committed的日志经过apply得到的最终结果，还记的前面讲日志复制的时候讲到节点内部的结构，里面有个状态机，这部分数据也就是这个状态机里面的内容。

另一部分内容是snapshot的元信息，元信息记录了snapshot中最后一条log的index和term。这两个信息是做什么用的呢？ 

还记得讲日志复制的时候，leader分发日志的请求和响应的结构：

```go
// request
type AppendEntriesArgs struct {
	Term int
	LeaderId int
	PrevLogIndex int
	PrevLogTerm int
	Entries []Entry
	LeaderCommit int
}
// response
type AppendEntriesReply struct {
	Term int
	Success bool
	ConflictIndex int
	ConflictTerm int
}
```

当follower本地的日志全的时候，就能轻易定位到这个PreLogIndex。当日志变成快照的时候, 就会存在PrevLogIndex已经被包含在快照中的情况，那么这个时候就需要告诉leader我只要快照之后的日志就可以了。

```go
	if args.PrevLogIndex < snapshot.last_included_index {
    reply.Term = self.currentTerm
    reply.Success = false
    reply.ConflictTerm = 0 //ConflictTerm只起辅助作用，帮助leader快速回退PrevLogIndex，可以填0
    reply.ConflictIndex = snapshot.last_included_index + 1
    return
  } else if args.PrevLogIndex == snapshot.last_included_index {
    if args.PrevLogTerm != snapshot.last_included_term {
      // should not happen. request maybe too old
      reply.Term = self.currentTerm
      reply.Success = false
      reply.ConflictTerm = snapshot.last_included_term
      reply.ConflictIndex = snapshot.last_included_index
      return
    }
  }

	// next step...
```

用到了last_included_index和last_included_term，所以是需要保存下来的。

snapshot是每个节点独立保存的，可以根据本地的存储情况，独立决定什么时候做日志压缩。

接下来再来看一个情况，如果这里follower回复了一个ConflictIndex，这时候leader需要把PrevLogIndex往前退，如果PrevLogIndex退到了小于leader本地last_included_index的值，那怎么办，拿不到PrevLogTerm也拿不到某些log了。

那就比较麻烦一点了，leader需要发送一个InstallSnapshot的请求给这个follower，然后follower保存snapshot并更新原来的log。

```go
func (self *Raft) InstallSnapshot(args *InstallSnapshotArgs, reply *InstallSnapshotReply) {
	//...
	if args.LastIncludedIndex > self.lastSnapshotIndex {
	  self.UpdateSnapshot(args)
	  self.UpdateLocalLog(args)
	  self.persister.SaveAllStateAndSnapshot(args)
		
		// 如果新的snapshot的index大于最新apply的log的index
		if self.lastSnapshotIndex > self.lastApplied {
			self.statemachine.NotifySnapshot(args)
			self.commitIndex = Max(self.commitIndex, self.lastSnapshotIndex)
			self.lastApplied = self.lastSnapshotIndex
		} 
	}

	reply.Term = rf.currentTerm
	reply.Success = true
	return

}
```



### 成员变更

集群成员的变更不是一个很有意思的话题，不太会让人感兴趣。只不过这个过程在里面是非常有技术性的一个事情，所以值得提出来讲一讲。

成员变更发生在机器故障需要替换，或者成员副本需要增加和减少的时候。

#### 存在的问题

成员变更过程有一个很严重的技术问题需要解决，在变更过程中可能会存在两个leader。

比如我们现在有1，2，3三台server，准备往里面添加4，5两个节点来扩充，我们给1，2，3中的leader发送一个添加节点D，E的请求，leader把请求通过日志分发给另外两个，当日志被commit之后，1，2，3就开始apply这条日志，apply的结果就是把自己的group成员变成1，2，3，4，5这5个。但是apply的过程并不是同时发生的，不同节点apply的时间点是有先后的。

比如下图中，3先apply了（这时候会发生4和5开始追赶leader日志的过程，但是这个过程这里不重要），3，4，5认为集群有5个节点，然后他们可以因为网络抖动或者网络隔离触发leader选举，他们三个达到了大部分，就会选出一个leader；1和2还没有apply，他们也会因为网络抖动触发选举，他们认为集群有3个节点，然后他们两个达到了大部分，就会选出一个leader，集群就分成了两个，有两个leader了,两个leader还是同一个term的，这是不允许的。

![member_add](/linkimage/raft/member_add.png)

那解决这个问题的方案有两个。

#### 方案一单节点变更
我们看到上面有问题的例子中，是两个节点一起添加，如果一次只添加一个节点就不会有这个问题。我们先一步把4添加进去，再一步把5添加进去。

先向3个中添加4：

![member3_add_1](/linkimage/raft/member3_add_1.png)

图片来自 [分布式-Raft算法(三)如何解决成员变更问题](https://honorjoey.top/2020/07/04/%E5%88%86%E5%B8%83%E5%BC%8F-Raft%E7%AE%97%E6%B3%95%28%E4%B8%89%29-%E5%A6%82%E4%BD%95%E8%A7%A3%E5%86%B3%E6%88%90%E5%91%98%E5%8F%98%E6%9B%B4%E9%97%AE%E9%A2%98/)

可以看到新旧配置要想分别组成两个group，旧配置需要两个节点，新配置需要3个节点，但是总的只有4个节点，所以一定有一个交叉的节点是两边都属于的。那么这个交叉的节点一旦投给了一个新（或旧）就不可能再同一个term的投票中在投给旧（或新）。也就不会出现同一个term存在两个leader的情况了。

接着向4个中添加5：

![member4_add_1](/linkimage/raft/member4_add_1.png)

图片来自 [分布式-Raft算法(三)如何解决成员变更问题](https://honorjoey.top/2020/07/04/%E5%88%86%E5%B8%83%E5%BC%8F-Raft%E7%AE%97%E6%B3%95%28%E4%B8%89%29-%E5%A6%82%E4%BD%95%E8%A7%A3%E5%86%B3%E6%88%90%E5%91%98%E5%8F%98%E6%9B%B4%E9%97%AE%E9%A2%98/)

同样，往4个节点中添加1个，一样会存在一个交叉的节点，这个交叉的节点可以防止集群出现两个相同term的leader。

移除节点的过程可以通过画类似的图来分析，这个单节点变更的过程已经被证明是可以安全的变更集群成员的。这也是工程实践中用的最多的实现，因为他容易理解也容易实现。

#### 方案二：联合共识（joint consensus）
回想上面添加多个节点时出问题的场景，1，2组成了老集群，3，4，5组成了新集群，出现这个问题的本质原因是把这个分布式场景下的配置变更想象成了一个单步完成的过程，事实上，无论你如何安排这个流程，只要是某个节点单步的从旧配置切换到新配置，就一定会出现某个节点先跟新节点组成新集群，而后变更的节点组成旧集群。

我们必须引入一种中间态，这种中间态是新旧集群共同治理的状态。如果把旧集群配置叫做C_old，新配置叫做C_new,那么共同治理的中间态就可以叫做C_old_new.

这个中间态中，集群要想达成一致意见---包括选leader--包括commit日志，都得同时满足新集群和旧集群的commit条件才行。

```bash
	C_old       C_new         Result            C_old_new Pass?
	1 2 3       1 2 3 4 5     1+ 2+ 3- 4- 5-    C_old+ C_new- => FAIL
	1 2 3       1 2 3 4 5     1- 2+ 3- 4+ 5+    C_old- C_new+ => FAIL
	1 2 3       1 2 3 4 5     1+ 2+ 3+ 4- 5-    C_old+ C_new+ => pass
	1 2 3       1 2 3 4 5     1+ 2+ 3- 4+ 5-    C_old+ C_new+ => pass
```

我们可以想象到这个状态是一个很安全的状态，他顶多是让提交一项日志变得困难了，但不会错误的提交一项日志。

所以整个过程如下：

![joint_consensus_steps](/linkimage/raft/joint_consensus_steps.png)

1. leader接收到配置变更的请求，leader把新老配置打包成C_old_new，（这里同样会先有个新节点日志追赶的过程）并分发给所有的节点，包括新老集群的节点，因为共同治理阶段是新老节点都要一起参与的，所以新老节点都要接收这个日志。

2. 随后C_old_new被commit，整个集群就正式进入共同治理的阶段；C_old_new提交后，意味着整个集群再也不可能回到old的状态了。

3. 处于共同治理的集群可以持续任意时间，leader如果因为某些原因在该状态持续时间较长也没什么问题。这期间的leader只会有一个，即便重新选leader也是选出同时被新老集群接受认可的一个leader，这期间的所有日志都是满足新老集群共同的提交条件的。

4. leader把C_new打包成日志存入本地，并广播给新老集群。

5. C_new被commit，整个配置变更过程结束。

下面针对这个过程中的几个细节展开一下：

1. 步骤1和2中，有两个时间点，一个是leader写入本地C_old_new日志t1，一个是leader提交C_old_new日志t2。

t1之前leader commit日志的条件是C_old,这很明显；在t2之后leader commit日志的条件是C_new，这我们也已经知道了。那t1-t2之间呢，t1-t2之间使用的规则也是C_old,因为这中间commit的日志肯定是C_old_new之前的，所以当然应该用C_old的条件；那t2时刻呢，也就是C_old_new本身的commit条件是什么呢？C_old_new被commit的条件就已经得是共同治理的条件了，要新老集群都满足commit条件。为什么呢？原因很简单，如果只满足old的条件，不满足new的条件，这意味着C_old_new在新集群中是不稳定的，是可能被覆盖掉的，如果这个C_old_new日志都还不稳定，那后面基于C_old_new做的决策也就是不可靠的，那我们也就不能确保这个集群进入了共同治理的状态了。

总结就是:

```
t <  t2 => use C_old commit
t >= t2 => use C_new commit
```

2. 步骤2中，如果在C_old_new被commit之前leader挂掉了，那会发生什么呢？有两种情况：

   一种是集群发生选举，一个包含C_old_new的节点赢得了新老集群共同的认可，成为leader，于是整个配置变更过程继续，因为新leader知道现在处于配置变更过程中。C_old_new被commit的工作将由新的leader接手继续推进。

   另一种是不包含C_old_new的节点成为leader，这是怎么发生的呢，比如有1，2，3的旧集群，添加4，5，6，7四个节点，新集群就是1，2，3，4，5，6，7。然后leader是3，3下发C_old_new给4，5，6，7后挂掉，这时候leader选举情况如下：

```bash
          C_old | C_new         |Result               |  C_old ?  C_new Pass? C_old_new?
[old选举]  1 2 3 | 1 2 3 4 5 6 7 |1+ 2+ 3- 4- 5- 6- 7- |  Pass     ----        ----
[new选举]  1 2 3 | 1 2 3 4 5 6 7 |1- 2- 3- 4+ 5+ 6+ 7+ |  Fail     Pass        Fail
	
```

​	这时候1和2还是C_old，那么1，2组成C_old的大多数，就可以在其中选出一个leader出来。4，5，6，7也尝试成为leader，并成为新集群的大多数。但是C_old_new以及其之后的条件必须是新老集群都满足commit（这是我们前面推导出来的安全commit的规则），所以即便新集群的配置下满足选出leader的条件，但是旧集群因为都不认识这些节点也就不会选他们为leader。所以选leader失败。这时候整个集群只有一个leader，leader使用老配置，配置变更失败。但是集群并没有处于混乱状态，没有错误发生。注：这种场景下，4，5，6，7会不停骚扰1，2要求选举，1，2会有一些保护措施来避免骚扰到，这里不展开。

3. 步骤4写入C_new,步骤5 Commit C_new，那么C_new的commit条件是什么呢，是C_old_new还是C_new呢？

   保守一点的话使用C_old_new即可，这是一种稳健的方式。不过也许可以激进一步，跟C_old_new那样，只要已接收C_old_new就使用C_old_new的规则。我们来比较一下。

   

| commit条件 |C_new日志commit成功 | leader挂掉_新leader含C_new | leader挂掉_新leader不含C_new |
|  ----  | ----  | ----  | ----  |
|使用C_old_new | 配置变更成功	 | 继续推进C_new的commit | 从C_old_new状态重新写入C_new|
|使用C_new | 配置变更成功   | 继续推进C_new的commit | 从C_old_new状态重新写入C_new|

可以看到无论使用C_old_new还是C_new效果都是一样的，那么从效率和方案的前后一致性上面来讲，我们规定C_new一旦接收就按照C_new的条件来判定commit，这样似乎更优雅一些。

回顾一下整个过程如下：

![joint_consensus_step](/linkimage/raft/joint_consensus_flow.png)

图片来自 [读Paper——Raft算法解读](http://liuyangming.tech/05-2019/raft.html)



## 参考资料

 [Using HAProxy with the Proxy Protocol to Better Secure Your Database](https://www.haproxy.com/fr/blog/using-haproxy-with-the-proxy-protocol-to-better-secure-your-database/)

[微服务](https://yizhi.ren/2019/06/25/microservice/) 

 [一致性Hash原理与实现](https://www.jianshu.com/p/528ce5cd7e8f)

 [P2P 网络核心技术：Gossip 协议](https://zhuanlan.zhihu.com/p/41228196)

[一致性算法 Paxos](https://www.cnblogs.com/Chary/p/13950387.html)

 [Paxos协议初探](https://www.jianshu.com/p/0ba4d0e03a71)

[Raft算法 二 如何复制日志](https://yfscfs.gitee.io/post/%E6%9E%81%E5%AE%A2%E6%97%B6%E9%97%B4%E4%B9%8B%E5%88%86%E5%B8%83%E5%BC%8F%E5%8D%8F%E8%AE%AE%E4%B8%8E%E7%AE%97%E6%B3%95%E5%AE%9E%E6%88%98-08-raft%E7%AE%97%E6%B3%95-%E4%BA%8C-%E5%A6%82%E4%BD%95%E5%A4%8D%E5%88%B6%E6%97%A5%E5%BF%97/)

[实例详解ZooKeeper ZAB协议、分布式锁与领导选举 ](https://www.sohu.com/a/214834823_411876)

 [In Search of an Understandable Consensus Algorithm](https://raft.github.io/raft.pdf)

[分布式-Raft算法(三)如何解决成员变更问题](https://honorjoey.top/2020/07/04/%E5%88%86%E5%B8%83%E5%BC%8F-Raft%E7%AE%97%E6%B3%95%28%E4%B8%89%29-%E5%A6%82%E4%BD%95%E8%A7%A3%E5%86%B3%E6%88%90%E5%91%98%E5%8F%98%E6%9B%B4%E9%97%AE%E9%A2%98/)

[读Paper——Raft算法解读](http://liuyangming.tech/05-2019/raft.html)

