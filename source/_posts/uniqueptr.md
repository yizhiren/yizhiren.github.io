---
title: unique_ptr 特性和源码解析
tags:
  - 西佳佳
categories:
  - 代码
date: 2016-11-14 17:34:46
updated: 2016-11-14 17:34:46
---

## C++ 中 unique-ptr 特性和源码解析

### 简介
std::unique_ptr 包含在头文件< memory > 中，它被用来实现对动态分配对象的自动释放。

这是一个在auto_ptr基础上发展并取代auto_ptr的类，所以它具有auto_ptr的自动释放特性以及独占控制权的特性，可以参考我之前关于auto_ptr的文章。最简单的用法如下：

```c++
      void test(){
            int*p=new int(0);
            unique_ptr<int> ap(p);
      }
```

那么为什么unique_ptr要诞生来取代auto_ptr呢，首先为什么不是修改auto_ptr而要另起炉灶呢，这主要是不希望用一种静默的方式来修改它，从而使得你忽略了auto_ptr已经不是当初的auto_ptr了，以此来避免隐含bug而你却没意识到。

另一个方面是unique_ptr比auto_ptr好在哪里， unique_ptr的出现是为了解决auto_ptr的两个问题，一个是静默的控制权转移问题，一个是不支持数组问题。

<!-- more -->

### 显式的控制权转移
控制权转移的问题看下面auto_ptr的例子，在例子中，ap1将控制权转移给了ap2,此时ap1中的指针已经是0，是无效地址。

假如你不清楚auto_ptr的特性，你试着去操作ap1比如 ap1->inertValue++  ，这将导致致命的错误。

```c++
      int*p=new int(0);
      auto_ptr<int>ap1(p);
      auto_ptr<int>ap2(ap1);
      //或者
      auto_ptr<int>ap2 = ap1;
```

涉及到两个函数：

```c++
      auto_ptr(auto_ptr& __a) throw() : _M_ptr(__a.release()) { }
      auto_ptr&
      operator=(auto_ptr& __a) throw()
      {
          reset(__a.release());
          return *this;
      }
```

那么unique_ptr就想着避免这种情况，于是它直接把这两个函数删掉了。。。

取而代之的是两个非常类似的函数：（等下，你标题说的显式转移怎么没说？  等下，先转移个话题，后面会转回来）

```c++
	//只是把 unique_ptr& __u 变成了unique_ptr&& __u而已嘛，
	//咦？ &&是啥意思？
	unique_ptr(unique_ptr&& __u)

	unique_ptr&
    operator=(unique_ptr&& __u)

```

这里你会发现他的参数类型不再是“引用”而是“引用引用”，有啥区别？  这个&&不同于引用类型&也不是逻辑与，而是一种新的类型，也是c++11引入的，叫做右值引用，也就是说这个参数类型必须是个右值。

```
    这里插一段，右值时什么？我们在auto_ptr时遇到过，那时右值以临时变量的身份出现。
	只是那时没这么叫他，那时也没有右值引用这么个符号出现
	
	简单点说，右值就是用完就会消失，你没法取到它地址的东西
	比如
	string left = string("1123");
	
	这里left是个左值，因为我们能取到其地址，它也存在下来了没有消失，
	而string("1123")是个临时存在的，用完即消失的变量，我们根本取不到他的地址，所以它是右值。
	或者更简单点， 右值 ≈ 临时变量 。
```

那么为什么要支持临时变量作为构造参数呢，再回想一下auto_ptr中的关于auto_ptr_ref的例子。

```c++
     auto_ptr<int>ap1=auto_ptr<int>(new int(0));
     auto_ptr<int>ap2(auto_ptr<int>(new int(0)));
```

auto\_ptr为了实现上面这种传递方式，特意创造出了一个辅助类auto_ptr_ref，这个类从不出现在一线的代码中。可见这是一种hack，一种workaround。

那么到了unique_ptr中为了继续支持这种用法同时抛弃这种hack的方式，就使用了一个新的类型，右值引用，把参数类型进行高度的限制。这样下面的代码就依然是可以通过的：

```c++
     unique_ptr<int>ap1=unique_ptr<int>(new int(0));
     unique_ptr<int>ap2(unique_ptr<int>(new int(0)));
```

好了，介绍了unique_ptr如何禁止控制权转移，那么如果我就是想转移呢，你为什么不让我转移？ 那就来看下它的显式转移方式吧（我说了我会转回来的吧）。

c++11又通过产生新玩意来支持你的这种需求，它想出了一个std::move函数，可以把你的变量转成右值，只是属性上变成右值，并没有进行值的拷贝。于是控制权转移的代码如下：

```c++
     unique_ptr<int>ap1(new int(0));
     unique_ptr<int>ap2(std::move(ap1));
     //或者
     unique_ptr<int>ap2 = std::move(ap1);
```

这样一番折腾的好处是什么呢，是这么一折腾你就记住了，你这个ap1的控制权已经交出去了，可不能记错了啊！ 看到新的函数越来越多，隐约感到c++已经向着体量臃肿的路上一去不复返了。奔跑吧~~

### 支持数组

unique\_ptr是如何来支持数组类型的指针呢， 它是通过模板类的数组特化来实现的，也就是他首先实现了一个通用指针的版本，随后又再实现一个针对数组类型的版本，特化版本的实现优先级更高，所以如果构造时传入的参数是数组类型，就会走数组的特化版本。

```c++
     /// unique_ptr for single objects.
     template <typename _Tp, typename _Dp = default_delete<_Tp> >
     class unique_ptr
     {
         ...
     }

     /// unique_ptr for array objects 
     template<typename _Tp, typename _Dp>
     class unique_ptr<_Tp[], _Dp>
     {
           ...  
     }
```


以及特化版的deletor


```c++
  template<typename _Tp>
  struct default_delete
  {
    ...
    operator()(_Tp* __ptr) const
    {
       delete __ptr;
    }
  };


  template<typename _Tp>
  struct default_delete<_Tp[]>
  {
    ...
    operator()(_Tp* __ptr) const
    {
       delete[] __ptr;
    }
  };
```

### 不得不提的容器
我们比较一下下面三段代码，语法没什么问题，但是只有第三段可以编过。

```c++
    // compile fail
    vector< auto_ptr<int> > vec;
    auto_ptr<int> abc(new int(0));	
    vec.push_back(abc);	
```

```c++
    // compile fail
    vector< unique_ptr<int> > vec;
    unique_ptr<int> abc(new int(0));	
    vec.push_back(abc);	
```

```c++
    // compile pass
    vector< unique_ptr<int> > vec;
    unique_ptr<int> abc(new int(0));	
    vec.push_back(std::move(abc));	
```

首先看第一段auto_ptr为什么编不过，失败的代码为vec.push_back(abc);

为什么失败，我们可以猜测push_back的代码：

```c++
      void
      push_back(const value_type& __x)
      {
	      // 通过 __x 构造一个新的value_type ，然后推到队列中
	  }
	  
```

然而我们知道auto_ptr是没法通过const 类型的变量来构造对象,他只能接受非const的，所以这个代码无法编译。

```c++
      auto_ptr&
      operator=(auto_ptr& __a) throw()
      {
	     reset(__a.release());
	     return *this;
      }
```

再来看第二段为什么失败，原因也简单，auto_ptr是无法接受非const的，但是unique_ptr是const以及非const都无法接受，所以更加无法编过。

然后第三段为什么编过了呢，第三段传给push_back的是一个经过move函数处理的右值，右值我们知道是可以被push_back(const value_type& __x)这个接口接收的，但是接收后肯定还是编不过和第二段就一样了。

那么为什么却编译通过了呢。通过翻看stl_vector.h的代码我们找到了答案：

```c++

    #if __cplusplus >= 201103L
      void
      push_back(value_type&& __x)
      { emplace_back(std::move(__x)); }

    #endif

```

原来vector在c++11后新增了push_back(value_type&& __x)这个专门接收右值的接口，编译器发现那个const参数的接口走不通就走了这个右值参数的接口。我们可以看到这个新接口中，入参一直都是以右值来传递下去的，保证他能被正确构造。

但这其实完全是move + vector + (Type&&)这三者共同完成的工作，并不属于unique_ptr改造auto_ptr的工作。很多文章都说这是unique_ptr优于auto_ptr的部分，我觉得其实不是。我在devcpp中增加-std=c++11编译参数后试过，不管unique_ptr还是auto_ptr，只要使用move函数处理，都能成功推入vector。


### 总结

unique_ptr 通过不定义相关构造函数来阻止控制权的隐式转移，即阻止变量赋值；通过两个新的c++11特性，包括std::move和右值引用类型，来实现右值（≈临时变量）的控制权转移，即临时变量可以赋值；又通过模版特化的方式来提供auto_ptr所不支持的数组指针，即可以接受数组指针做构造参数。 



	 
