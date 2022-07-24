---
title: Epoll Level Trigger
tags:
- 西佳佳
categories:
- 代码
date: 2017-04-09 17:34:46
updated: 2017-04-09 17:34:46
---


## epoll 中level trigger的检验

### 简介

在我们通过网络搜索的时候，关于epoll的水平触发的解释通常是这样的：

水平触发：只要缓冲区还有数据，内核就还会通知用户。用户如果第一次读取数据没读完，即使没有任何新的操作触发，还是可以继续通过epoll_wait来获取事件。

这段解释水平触发的话应该来说是没有错的，然而这段话并不总是如你所想的，说这句话的人不会告诉你什么场景满足什么场景是不满足的。我就是要说一个你一定以为满足，实际上却不满足的场景。

我们先来看成立的情况：

<!-- more -->

### Work Good

首先tcpservcer启动
```
root@localhost]# ./tcp
[epoll thread create. sock = 3]
```

接着client启动并发送字符串
```
[root@localhost reuseport]# ./tcpclient 
send 12345...
```

接着server 的epoll由于水平触发，被触发多次，每次接收两个字符
```
[epoll awake. event sock = 3]
[ACCEPT SOCKET 5]=====================
[epoll awake. event sock = 5]
recv 2 byte[12] from sock 5
[epoll awake. event sock = 5]
recv 2 byte[34] from sock 5
[epoll awake. event sock = 5]
recv 1 byte[5] from sock 5
```

可以看到一切都按照预期的进行着，水平触发在没有接受完的时候就可以一直被触发。

#### Code
```
//tcp.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <sys/epoll.h>
#include <pthread.h>



int createServerSocket()
{
    int sock = socket(PF_INET, SOCK_STREAM, 0);
    assert(sock > 0);
    return sock;    
}

void bindSocket(int _socket, int _port)
{
    struct sockaddr_in     servaddr;
    memset(&servaddr, 0, sizeof(servaddr));
    servaddr.sin_family = AF_INET;
    servaddr.sin_addr.s_addr = htonl(INADDR_ANY);
    servaddr.sin_port = htons(_port);
    
    int ret = bind(_socket, (struct sockaddr*)&servaddr, sizeof(servaddr));
    assert(ret == 0);
}


void make_socket_addr_reuse (int _socket)
{

    int optval = 1;
    int ret1 = setsockopt(_socket, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval));
    int ret2 = setsockopt(_socket, SOL_SOCKET, SO_REUSEPORT, &optval, sizeof(optval));

    assert(ret1 == 0);
    assert(ret2 == 0);


}

void listenSocket(int _socket)
{
    listen(_socket,5);
}


void make_socket_non_blocking (int _socket)
{
  int flags = fcntl (_socket, F_GETFL, 0);
  assert(flags != -1);

  flags |= O_NONBLOCK;
  int ret = fcntl (_socket, F_SETFL, flags);
  assert(ret == 0);

  
}


int createEpoll(int _size)
{
    int epollfd = epoll_create(_size);
    assert(epollfd > 0);
}

void epollClear(int _epoll, int fd)
{
    int ret = epoll_ctl(_epoll, EPOLL_CTL_DEL, fd, NULL);
    assert(0 == ret);   
}

void epollAddET(int _epoll, int fd, int mask)
{
    struct epoll_event epEvent;
    memset(&epEvent, 0,sizeof(epEvent));
    epEvent.data.fd = fd;
    epEvent.events = mask | EPOLLET;
    
    int ret = epoll_ctl(_epoll, EPOLL_CTL_ADD, fd, &epEvent);
    assert(0 == ret);
}

void epollAddLT(int _epoll, int fd, int mask)
{
        struct epoll_event epEvent;
        memset(&epEvent, 0,sizeof(epEvent));
        epEvent.data.fd = fd;
        epEvent.events = mask;

        int ret = epoll_ctl(_epoll, EPOLL_CTL_ADD, fd, &epEvent);
        assert(0 == ret);
}

int epollwait(int _epoll, struct epoll_event *events, int _maxEvents)
{
    
    int ret = epoll_wait(_epoll, events, _maxEvents, -1);
    assert(ret > 0);
    
    return ret;
}



void handleClientSock(int _epollfd, int clientSock)
{
    char recv_buffer[2]="";
    int bytes = read(clientSock, recv_buffer, sizeof(recv_buffer));
    printf("recv %d byte[%s] from sock %d\n", bytes,recv_buffer, clientSock);
    if(bytes <= 0){
        //printf("close sock %d\n", clientSock);
        epollClear(_epollfd, clientSock);
        close(clientSock);
        printf("[CLOSE SOCKET %d]=====================\n",clientSock);
    }   
}

void handleAcceptSock(int _epollfd, int serverSock)
{
    struct sockaddr_in client_addr;
    socklen_t client_len = sizeof(client_addr);
    int client = accept(serverSock, (struct sockaddr *)&client_addr, &client_len);

    assert(client > 0);
    epollAddLT(_epollfd, client, EPOLLIN);
    printf("[ACCEPT SOCKET %d]=====================\n",client);
}

void* masterThreadBody(void *arg)
{
    int epollfd = createEpoll(100);
    int tcpsocket = (int)arg;
    printf("[epoll thread create. sock = %d]\n", tcpsocket);
    epollAddET(epollfd, tcpsocket, EPOLLIN);
    
    struct epoll_event fired_events[100];
    while(1)
    {
        int eventCount = epollwait(epollfd, fired_events, 100);
        assert(eventCount > 0);
        
        int i=0;
        for(;i<eventCount;i++)
        {
            printf("[epoll awake. event sock = %d]\n", fired_events[i].data.fd);
            if(fired_events[i].data.fd == tcpsocket){
                handleAcceptSock(epollfd,fired_events[i].data.fd);
            }else{
                handleClientSock(epollfd,fired_events[i].data.fd);
            }
        }


    }
    
    return NULL;
}

pthread_t createMasterThread(int tcpSock)
{
    pthread_t tid;
    int ret = pthread_create(&tid,NULL,masterThreadBody,(void*)tcpSock);
    assert(ret == 0);
    
    return tid;
}


int main(int argc, char** argv)
{
    int sock = createServerSocket();
    make_socket_addr_reuse(sock);
    bindSocket(sock, 666);
    listenSocket(sock);
    pthread_t tid = createMasterThread(sock);
    
    pthread_join(tid, NULL);
    
}

```


```
//tcpclient.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <sys/epoll.h>
#include <pthread.h>



int createServerSocket()
{
    int sock = socket(PF_INET, SOCK_STREAM, 0);
    assert(sock > 0);
    return sock;    
}

void make_socket_addr_reuse (int _socket)
{

    int optval = 1;
    int ret1 = setsockopt(_socket, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval));
    int ret2 = setsockopt(_socket, SOL_SOCKET, SO_REUSEPORT, &optval, sizeof(optval));

    assert(ret1 == 0);
    assert(ret2 == 0);


}

void bindSocket(int _socket, int _port)
{
    struct sockaddr_in     servaddr;
    memset(&servaddr, 0, sizeof(servaddr));
    servaddr.sin_family = AF_INET;
    servaddr.sin_addr.s_addr = htonl(INADDR_ANY);
    servaddr.sin_port = htons(_port);
    int ret = bind(_socket, (struct sockaddr*)&servaddr, sizeof(servaddr));
    assert(ret == 0);
}

void connectSocket(int _socket, int _port)
{
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");
    addr.sin_port = htons(_port);

    int ret = connect(_socket,(struct sockaddr*)&addr,sizeof(addr));
    if(ret==-1){
        printf("connet ret=%d,errno=%d:%s\n",ret,errno,strerror(errno));
    }
    assert(ret == 0);
}



void work()
{
    int sock = createServerSocket();
    make_socket_addr_reuse(sock);   
    bindSocket(sock, 777);
    connectSocket(sock,666);

    write(sock,"12345",5);
    printf("send 12345...\n");
    sleep(30);
    close(sock);
}
    
int main(int argc, char** argv)
{
    work();
}

```


### Work Fail
我们现在可以来看这个失败的情况了，这个情况就是大名鼎鼎的UDP。

首先udp server启动
```
[root@localhost reuseport]# ./udp
[epoll thread create. sock = 3]
```

接着udp client发送字符串
```
[root@localhost]# ./udpclient 
sendto 12345...
```

接着udp server接收到数据，一次接收两个字节，按照预期，将触发3次来接收。
```
[epoll thread awake. sock = 3]
recv 2 byte[12] from sock 3
```
但是它只触发了一次，你是不是怀疑我设置成了边缘触发了，为了验证，我把用来接收的数据的函数直接return，或者把接收的长度设为0，发现就会一直触发，可见水平触发参数设置是成功的。

所以对于UDP，你只有一次机会去接收数据，这丛它数据报的名字上我们可以方便来理解，一个数据报只能接收一次。

这就是我这篇文章重点要说的话：

水平触发在TCP通信中只要没接收完就会一直被触发，在UDP通信中不会！
记住，UDP不会！
这个结论并不能推翻前面的定义，因为UDP之所以不会多次触发是因为一次read之后缓冲区数据确实就不存在了。



#### Code
```
//udp.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <sys/epoll.h>
#include <pthread.h>



int createServerSocket()
{
    int sock = socket(AF_INET,SOCK_DGRAM,0);
    assert(sock > 0);
    return sock;    
}

void bindSocket(int _socket, int _port)
{
    struct sockaddr_in     servaddr;
    memset(&servaddr, 0, sizeof(servaddr));
    servaddr.sin_family = AF_INET;
    servaddr.sin_addr.s_addr = htonl(INADDR_ANY);
    servaddr.sin_port = htons(_port);
    
    int ret = bind(_socket, (struct sockaddr*)&servaddr, sizeof(servaddr));
    assert(ret == 0);
}


void make_socket_addr_reuse (int _socket)
{

    int optval = 1;
    int ret1 = setsockopt(_socket, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval));
    int ret2 = setsockopt(_socket, SOL_SOCKET, SO_REUSEPORT, &optval, sizeof(optval));

    assert(ret1 == 0);
    assert(ret2 == 0);


}

void make_socket_non_blocking (int _socket)
{
  int flags = fcntl (_socket, F_GETFL, 0);
  assert(flags != -1);

  flags |= O_NONBLOCK;
  int ret = fcntl (_socket, F_SETFL, flags);
  assert(ret == 0);

  
}


int createEpoll(int _size)
{
    int epollfd = epoll_create(_size);
    assert(epollfd > 0);
}

void epollClear(int _epoll, int fd)
{
    int ret = epoll_ctl(_epoll, EPOLL_CTL_DEL, fd, NULL);
    assert(0 == ret);   
}

void epollAddET(int _epoll, int fd, int mask)
{
    struct epoll_event epEvent;
    memset(&epEvent, 0,sizeof(epEvent));
    epEvent.data.fd = fd;
    epEvent.events = mask | EPOLLET;
    
    int ret = epoll_ctl(_epoll, EPOLL_CTL_ADD, fd, &epEvent);
    assert(0 == ret);
}

void epollAddLT(int _epoll, int fd, int mask)
{
        struct epoll_event epEvent;
        memset(&epEvent, 0,sizeof(epEvent));
        epEvent.data.fd = fd;
        epEvent.events = mask;

        int ret = epoll_ctl(_epoll, EPOLL_CTL_ADD, fd, &epEvent);
        assert(0 == ret);
}

int epollwait(int _epoll, struct epoll_event *events, int _maxEvents)
{
    
    int ret = epoll_wait(_epoll, events, _maxEvents, -1);
    assert(ret > 0);
    
    return ret;
}



void handleClientSock(int _epollfd, int clientSock)
{
    char recv_buffer[2]="";
    int bytes = read(clientSock, recv_buffer, sizeof(recv_buffer));
    printf("recv %d byte[%s] from sock %d\n", bytes,recv_buffer, clientSock);
    if(bytes <= 0){
        //printf("close sock %d\n", clientSock);
        epollClear(_epollfd, clientSock);
        close(clientSock);
        //printf("[CLOSE SOCKET]=====================\n");
    }   
}

void* masterThreadBody(void *arg)
{
    int epollfd = createEpoll(100);
    int udpsocket = (int)arg;
    printf("[epoll thread create. sock = %d]\n", udpsocket);
    epollAddLT(epollfd, udpsocket, EPOLLIN);
    
    struct epoll_event fired_events[100];
    while(1)
    {
        int eventCount = epollwait(epollfd, fired_events, 100);
        assert(eventCount > 0);
        
        int i=0;
        for(;i<eventCount;i++)
        {
                printf("[epoll thread awake. sock = %d]\n", fired_events[i].data.fd);
                handleClientSock(epollfd,fired_events[i].data.fd);
        }


    }
    
    return NULL;
}

pthread_t createMasterThread(int udpSock)
{
    pthread_t tid;
    int ret = pthread_create(&tid,NULL,masterThreadBody,(void*)udpSock);
    assert(ret == 0);
    
    return tid;
}


int main(int argc, char** argv)
{
    int sock = createServerSocket();
    make_socket_addr_reuse(sock);
    bindSocket(sock, 666);
    pthread_t tid = createMasterThread(sock);

    pthread_join(tid, NULL);
    
}

```

```
//udpclient.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <sys/epoll.h>
#include <string.h>



int createServerSocket()
{
    int sock = socket(AF_INET,SOCK_DGRAM,0);
    assert(sock > 0);
    return sock;    
}

void work()
{
    int sock = createServerSocket();
    
    struct sockaddr_in serverAddress;
    serverAddress.sin_family = AF_INET;
    serverAddress.sin_port = htons(666);
    serverAddress.sin_addr.s_addr = inet_addr("127.0.0.1");
    int ret = sendto(sock, "12345", 5, 0, (struct sockaddr *)&serverAddress, sizeof(serverAddress));
    printf("sendto 12345...\n");
    sleep(30);
    close(sock);
}
    
int main(int argc, char** argv)
{
    work();
}
```


这些代码也可以给看到的人做一个例子。






















