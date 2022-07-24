---
title: Byte order of bitfield
tags:
  - 网络
categories:
  - 代码
date: 2016-11-14 17:34:46
updated: 2016-11-14 17:34:46
---

## 位域的字节序

### 问题的起源
今天阅读到ip头结构体，看到前面两个字段用到了宏，可以看到这两个字段在大小端（大/小字节序）情况下的顺序是不同的。
于是有一个疑问，为什么其他字段可以不管大小端，唯独这两个字段要关注大小端。

```
//IP头部，总长度20字节   
typedef struct _ip_hdr  
{  
    #if LITTLE_ENDIAN   
    unsigned char ihl:4;     //首部长度   
    unsigned char version:4, //版本    
    #else   
    unsigned char version:4, //版本   
    unsigned char ihl:4;     //首部长度   
    #endif   
    unsigned char tos;       //服务类型   
    unsigned short tot_len;  //总长度   
    unsigned short id;       //标志   
    unsigned short frag_off; //分片偏移   
    unsigned char ttl;       //生存时间   
    unsigned char protocol;  //协议   
    unsigned short chk_sum;  //检验和   
    struct in_addr srcaddr;  //源IP地址   
    struct in_addr dstaddr;  //目的IP地址   
}ip_hdr;
```

<!-- more -->

### 网络传输的过程
网络传输中，由于网络两端的设备并不知道对方是什么字节序，所以接收端就无法知晓应该按照大端还是小端来还原数据。
于是网络协议就规定，传输过程一律采用大端的方式传输，网络两端的设备可以在大端和本地字节序之间转换。
比如小端与小端之间的通信过程:
```
[本地：小端->大端]<-- 网络  -->[大端->小端：远端]
```

由于有了上面这个过程，我们在写代码的时候可以无需关注字节序问题，只要按照这个过程转换一遍准没错。
假设我本地变量是0x12345678,本地是小端结构，所以12是高内存位，78是低内存位。
发送前经过转换成大端结构，于是78换到高内存位，12换到低内存位，值为0x78563412.
咦？怎么不是0x87654321。这里要注意了，不是0x87654321.
不管是ntohl还是htonl都是按字节为单位逆转顺序的，78和12分别是一整个字节，所以是不会被换成87和21的。

然后0x78563412被传到远端，远端是小端，又把78换到低内存位：0x12345678。
假如远端是大端，大端转到大端是个空操作，于是78还是高内存位，12还是低内存位；在大端的系统中，低内存位代表高位值，于是值也是0x12345678.
```
[本地：0x12345678->0x78563412]<-- 0x78563412  -->[0x78563412->0x12345678：远端]
```

### 总结规律
通过上面传输过程的回顾，我们再结合我们自己的编码经验，可以总结发现：
2字节的数据通过ntohs和htons来转换字节序。
4字节的数据通过ntohl和htonl来转换字节序。
字节序的最小单位是1个字节，也就是说1个字节的数据无需转换。
一个字节的数据不论在哪种字节序的系统下都会解析成一样的值。

我们在看ip头的结构体：

```
//IP头部，总长度20字节   
typedef struct _ip_hdr  
{  
    #if LITTLE_ENDIAN   
    unsigned char ihl:4;     //首部长度   
    unsigned char version:4, //版本    
    #else   
    unsigned char version:4, //版本   
    unsigned char ihl:4;     //首部长度   
    #endif   
    unsigned char tos;       //服务类型   
    unsigned short tot_len;  //总长度   
    unsigned short id;       //标志   
    unsigned short frag_off; //分片偏移   
    unsigned char ttl;       //生存时间   
    unsigned char protocol;  //协议   
    unsigned short chk_sum;  //检验和   
    struct in_addr srcaddr;  //源IP地址   
    struct in_addr dstaddr;  //目的IP地址   
}ip_hdr;
```
我们可以看出这个结构中除了char型的数据不需要转换，其他数据都要经过htonx/ntohx转换。
然而不管需不需要转换，都无需改变字段定义的顺序啊？

### 规律之外
我们虽然总结了规律，但是规律却没法描述位域字段。什么叫位域，也就是变量后面跟上冒号接数字表示这个变量占几个比特位的这种字段，比如：
unsigned char ihl:4   这表示ihl只占用了4个比特位。
这种字段我们是怎么来处理大小端的呢？

实际上这种比特位的字段的规律可以类比：
多个位域字段   -> 类比到 -> 多字节
最小单位字节   -> 类比到 -> 最小单位为一个位域字段

也就是把一个位域字段想成一个字节，多个位域字段想成一个多字节变量。
比如:
```
struct Example{
	unsigned char ihl:4;     //首部长度   
	unsigned char version:4, //版本  
} example;
example.ihl=1;
example.version=2;
// 当我们赋值完后可以想象成example = 0x version,ihl  即 example = 0x21
// 对于位域的bit数不是4的也一样规律，
// 那么example在小端系统上的内存排列是
//  bit: | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
//         0   0   1   0 , 0   0   0   1
// 在大端系统上的排列是
//  bit: | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
//         0   0   0   1 , 0   0   1   0
//
```

这个类比是关键的原理，是导致我们为什么用宏来区分字段顺序的关键！

由于有以上的类比，为了接收端能够正确还原数据，我们也需要这个过程：
```
[本地：小端->大端]<-- 网络  -->[大端->小端：远端]
比如本地的一个值是0x21,比如上面的example,我们希望的传输过程：
[本地：0010,0001->0001,0010]<-- 0001,0010  -->[0001,0010->0010,0001：远端]
```

然而由于位域并不固定几个比特位，所以遗憾的是系统没法提供基于位域的大小端转换函数。
所以我们实际上是无法完成大端<->小端之间的转换的。这可怎么办？

### 解决方案
所以我们只有一个办法，手动保证在网络两端都是大端（或者小端）的内存结构，这样两边都不转换也能保证值不变。
于是我们可以想到利用宏来判断，下面这段定义，我们可以看到，作者的目的是把ihl作为内存的低4位，version作为高4位。
```
    #if LITTLE_ENDIAN   
    unsigned char ihl:4;     //首部长度   
    unsigned char version:4, //版本    
    #else   
    unsigned char version:4, //版本   
    unsigned char ihl:4;     //首部长度   
    #endif   
```
如果是小端系统，ihl定义在前，由上面的example可以得知，小端先定义的处于低内存位，ihl是处于低内存位的。
如果是大端系统，version定义在前，由上面example得知，大端先定义的位于高内存位，version定义在高内存位，ihl就在低内存位，于是ihl无论如何都在低内存位了。

### 另一种记忆方法
对于位域字段如何确定他们的内存排列，除了按照上面的分析，把一个位域字段想成一个字节，多个位域字段想成一个多字节变量外，还有一种记忆方法。

对于多个位域字段，你可以认为系统总是从上往下依次把他们从低内存向高内存排列过去。当然这指的是小端。
大端则相反，总是把他们从上往下从高内存向低内存排列，但是一个字段是作为一个整体，不做拆分或者转换。

```

#include <stdio.h>
#include <memory.h>

struct WORD{
        unsigned short bit1:4;
        unsigned short bit2:9;
        unsigned short bit3:3;
};


int main()
{
        WORD word;
        memset(&word,0,sizeof(word));

        // 111,100000001,0001  => 7,257,1
        unsigned short low16bit=0xF011;
        memcpy(&word,&low16bit,sizeof(low16bit));

        printf("size:%d,bit1:%d,bit2:%d,bit3:%d\n",sizeof(word),word.bit1,word.bit2,word.bit3);
}

// size:2,bit1:1,bit2:257,bit3:7

```

这是小端的结果，大端是不同的。
我们还可以看到当4+9+3==16,正好是16的倍数的时候，字段是紧凑排列的。不是16倍数时候就不一定紧凑了。


```
#include <stdio.h>
#include <memory.h>

struct WORD{
        unsigned short bit1:4;
        unsigned short bit2:9;
        unsigned short bit3:11;
};


int main()
{
        WORD word;
        memset(&word,0,sizeof(word));

        // 111,100000001,0001
        unsigned short low16bit=0xF011;
        memcpy(&word,&low16bit,sizeof(low16bit));

         //0000,0000,0000,0010
         unsigned short high16bit=0x2;
         memcpy((char*)(&word)+2,&high16bit,sizeof(high16bit));

        printf("size:%d,bit1:%d,bit2:%d,bit3:%d\n",sizeof(word),word.bit1,word.bit2,word.bit3);
}

// size:4,bit1:1,bit2:257,bit3:2

```
我们看到4+9+11==24，但是sizeof是4，而且可以看到bit3并没有紧跟着bit2而是被安排到了一个新的字节当中去。




