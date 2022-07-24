---
title: ODR-The One Definition Rule
tags:
  - 西佳佳
categories:
  - 代码
date: 2016-11-14 17:34:46
updated: 2016-11-14 17:34:46
---

## ODR-(One Definition Rule) 下的奇淫异技

### 一行输出引起的..故事
首先看这个终端的输出结果：
```
[root@localhost xxxx]# g++ -o binary binary.cpp libb.a liba.a
[root@localhost xxxx]# ./binary 
1
1
[root@localhost xxxx]# g++ -o binary binary.cpp liba.a libb.a
[root@localhost xxxx]# ./binary 
2
2
[root@localhost xxxx]# cat binary.cpp
#include <iostream>

extern int fna();
extern int fnb();

int main(){
    std::cout << fna() << std::endl;
    std::cout << fnb() << std::endl;

}

```

可以看到我们通过改变两个库的链接顺序，改变了两个函数的返回值。how?
如果你对这个结果并没什么兴趣，你也许对下面的内容也不感兴趣。但是如果你挺有兴趣的话我们就来一起看看。

<!-- more -->

### 小王的猜想
小王同学首先是这么想的，liba 和libb中可能都含有fna和fnb两个函数，链接顺序不同就会调用不同的实现。
但是又一想，不对啊，这么弄不是会报重定义的错误吗？会吗？不会吗？
我们来验证一把，看看同名函数（我使用一个叫common的函数来举例）能不能同时存在并链接成功：
文件结构：
```
               | -->   liba.cpp   |
common.hpp  -> | -->   libb.cpp   | => binary  
                     binary.cpp   |
```
代码：
![code with common](/linkimage/odr/1.png)

结果很遗憾，确实是重定义：
```
[root@localhost xxxx]# g++ -c liba.cpp && ar rcs liba.a liba.o
[root@localhost xxxx]# g++ -c libb.cpp && ar rcs libb.a libb.o
[root@localhost xxxx]# g++ -o binary binary.cpp libb.a liba.a
liba.a(liba.o): In function `common()':
liba.cpp:(.text+0x0): multiple definition of `common()'
libb.a(libb.o):libb.cpp:(.text+0x0): first defined here
collect2: ld returned 1 exit status
[root@localhost xxxx]# 
```

### 小红的不服
小红看了后有一丝不确定，“我觉得他报重定义是因为common函数在两边的实现完全一致，如果不一样，可能，就不会重定义了”。
我们就是要这么严谨，来试一试，我们用宏来控制两边的实现：
![code with common and macro](/linkimage/odr/2.png)

结果依然很遗憾，还是重定义：
```
[root@localhost xxxx]# g++ -c libb.cpp && ar rcs libb.a libb.o
[root@localhost xxxx]# g++ -c liba.cpp && ar rcs liba.a liba.o
[root@localhost xxxx]# g++ -o binary binary.cpp libb.a liba.a
liba.a(liba.o): In function `common()':
liba.cpp:(.text+0x0): multiple definition of `common()'
libb.a(libb.o):libb.cpp:(.text+0x0): first defined here
collect2: ld returned 1 exit status
```

可见编译器只看函数的定义不在意实现，只要定义一致就当做重定义。

### 学霸的愤怒
只考99分就必须大哭的学霸小丁看不下去了，“你们都不知道有模板这个bug吗？”
没错，模板在重定义这件事情上确实是bug般的存在，你可以想一下模板，比如vector。
vector的所有定义（包括实现）都是通过头文件包含进来的，对于cpp，你编译几个就有几个实现，链接成.a后,你有几个.a你就有几个实现。
最后还照样能链接成功。
我们来试试，把common改成模板：
![code with common template](/linkimage/odr/3.png)

```
[root@localhost xxxx]# g++ -c libb.cpp && ar rcs libb.a libb.o
[root@localhost xxxx]# g++ -c liba.cpp && ar rcs liba.a liba.o
[root@localhost xxxx]# g++ -o binary binary.cpp libb.a liba.a
[root@localhost xxxx]# 
```
这次总算是成功了。不过这时候不管怎么换链接顺序，结果必然都是1.

### 柳暗花明
于是我们又想起来不服气的小红，那时我们尝试不同cpp不同的实现失败了。
现在既然在学霸的指点下不再报重定义，那么我们继续用宏来控制他的实现看看，肯定也不会报重定义吧？
或者会不会报一个类似“实现不一致”的错误？毕竟我们从来没有故意把模板做成多个实现过。
没有试过我们不敢乱说：
![code with common template and macro](/linkimage/odr/4.png)
很顺利
```
[root@localhost xxxx]# g++ -c liba.cpp && ar rcs liba.a liba.o
[root@localhost xxxx]# g++ -c libb.cpp && ar rcs libb.a libb.o
[root@localhost xxxx]# g++ -o binary binary.cpp libb.a liba.a
[root@localhost xxxx]#
```
我们继续尝试调换链接顺序
```
[root@localhost xxxx]# g++ -o binary binary.cpp libb.a liba.a
[root@localhost xxxx]# ./binary 
1
1
[root@localhost xxxx]# g++ -o binary binary.cpp liba.a libb.a
[root@localhost xxxx]# ./binary 
2
2
[root@localhost xxxx]# 
```
太棒了！做到了。


### 原理
造成这种现象的原因是同一个函数在不同的库中有多份实现，链接顺序不同的话，最终编译器会选择其中的一个。
这种情况普通函数不会出现，然而对于模板，编译器给了它特权，允许有多份实现。
假如这多个实现不相同，然而他们的定义是一致的，编译器就单纯的认为这是同一个函数，我任选一个就行了（实际上由于该现象未定义，编译器可以自己决定要哪个）。

C++为了避免这种情况，有一个规则：
ODR（One Definition Rule）：types, templates, extern inline functions,可以定义在不同的 translation unit（比如一个lib）中. 但是对于一个给定的实体 每一个定义必须相同.

看到了吧，它说模板可以多个库都有定义（也就有多份实现），但是这每一份必须相同。咦怎么没有提到实现必须一致，模板这种多个定义不就多个实现吗？没有提到！
所以ODR是说模板可以定义在不同的单元中，由此带来的多份实现我不给你报错，让你能够编译通过。但是实现是否相同我不说，所以很遗憾对于实现,我们只能人工得去遵守，编译器说它爱莫能助。它只在乎你的类型。

我们在平时编码时要注意头文件中少用宏来区分实现，可以避免一部分ODR相关的坑。cpp中用宏不当其实也可能，比如DEBUG选项，压栈顺序之类的宏开关。
 






