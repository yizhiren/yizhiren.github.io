---
title: auto_ptr 特性和源码解析
tags:
  - 西佳佳
categories:
  - 代码
date: 2016-11-14 17:34:46
updated: 2016-11-14 17:34:46
---


## C++ 中 auto-ptr 特性和源码解析

### 简介

std::auto_ptr 包含在头文件 < memory > 中，它被用来实现对动态分配对象的自动释放。如：

```c++
      void test(){
            int*p=new int(0);
            auto_ptr<int> ap(p);
      }
```


这段代码不会造成内存泄漏，因为在ap这个对象结束生命周期时，其包含的p会被自动释放。这几乎已经是auto_ptr的全部作用了，但是还有一些小秘密，下面结合它的代码看看他的实现，挖挖它的内涵。

<!-- more -->

### 重复释放问题

由于auto_ptr在不同实例间没有关联，因此多个实例得到同一份指针将引起重复释放问题。

```c++
      int*p=new int(0);
      auto_ptr<int>ap1(p);
      auto_ptr<int>ap2(p);
```

### 与指针的隐式转换

auto_ptr< Type >与 Type*指针间的隐式转换是不存在的。
首先指针转到auto_ptr是通过这个接口：

```c++      
      typedef _Tp element_type;
      
      explicit
      auto_ptr(element_type* __p = 0) throw() : _M_ptr(__p) { }
```

注意到explicit这个关键字，有了这个关键字于是下面的代码是通不过的，因为他没有显式的调用构造函数，与explicit违背。

```c++
      int*p=new int(0);
      auto_ptr<int>ap1 = p;
```

而必须通过

```c++
      int*p=new int(0);
      auto_ptr<int>ap1 = auto_ptr<int>(p);
      或者
      auto_ptr<int>ap1(p);
```

这么做的目的只可能是为了防止误用，防止在这个变量是auto_ptr还是指针上傻傻分不清。

再一个从auto_ptr< Type >转到Type*的时候使用的是get()接口，而无法隐式转过去。


### 指针和取值操作

下面这个例子，如果我们对ap进行(\*ap)和ap->f()操作，结果与(\*p)和p->f()是否一样呢？

```c++
      ClassABC *p=new ClassABC();
      auto_ptr<ClassABC>ap(p);
```

我们可以通过auto_ptr的源码来知道答案， 她重载了这两个操作符，使得其操作效果和直接指针的效果是一样的：

```c++
      operator*() const throw() 
      {
	     return *_M_ptr; 
      }

      element_type*
      operator->() const throw() 
      {
	     return _M_ptr; 
      }
```

### 特殊构造函数的特殊意义
我们知道拷贝构造和赋值构造函数的定义一般是：

```c++
      ClassABC(const ClassABC& c);
      ClassABC&
      operator=(const ClassABC& c);
```

他们的参数都是const类型的，但是auto_ptr却不是const类型的，原因是什么呢？

```c++
      auto_ptr(auto_ptr& __a) throw() : _M_ptr(__a.release()) { }
      auto_ptr&
      operator=(auto_ptr& __a) throw()
      {
	     reset(__a.release());
	     return *this;
      }
```

 涉及到一个控制权的问题，auto_ptr假设只有一个实例是持有这个指针的，否则必然导致重复释放，所以当把一个auto_ptr实例赋值给另一个auto_ptr实例时：

```c++
      int*p=new int(0);
      auto_ptr<int>ap1(p);
      auto_ptr<int>ap2(ap1);
```

前者（ap1）的实例必须放弃这个指针(p)而把它交给后者(ap2)。而这个放弃的操作必然会修改该实例(ap1)内部数据，于是它不能是const类型，只能是非const类型的。而非const的参数类型不能接收的有，一个是const类型的，还有一个是临时变量。

```c++
	 // 这是接收临时变量的两个例子
     auto_ptr<int>ap1=auto_ptr<int>(new int(0));
     auto_ptr<int>ap2(auto_ptr<int>(new int(0)));
```

要接收const类型没办法实现。但是接收临时变量还是有办法的，看下面：


### auto_ptr_ref类

于是牛人想出了一个方案来支持临时变量的赋值。Bill Gibbons和Greg Colvin创造性地提出了auto_ptr_ref类，解决了无法传递临时变量的问题。

思路是这样的，注意推导过程：

```
为了接收 auto_ptr<TYPE>类型的临时变量，我可以选择的形参有const auto_ptr<TYPE>&或者auto_ptr<TYPE>& 或者auto_ptr<TYPE> 3种参数类型。
1. const auto_ptr<TYPE>&因为不支持修改而排除； 
2. auto_ptr<TYPE>&支持修改，但是对临时变量只能const引用，不能直接引用，而const引用刚才已经排除了，所以这也不行；
3. auto_ptr<TYPE>呢，编译器说这么定义不行，你可以试试。这会导致逻辑上的死循环，假如你要使用临时变量A0来构造B，由于形参不是引用类型，所以你必须从A0拷贝一份A1传入B，于是你又陷入如何从临时变量A0生成临时的变量A1，从A0到A1和从A0到B的问题依然是同一个。
```

于是我们只能新创建一个类叫做auto_ptr_ref< TYPE >。 然后给auto_ptr增加新的构造函数：

```c++
    auto_ptr(auto_ptr_ref<TYPE> __ref)
```

然后你应该猜到了，我们再给auto\_ptr增加新的类型转换函数，支持转换到auto_ptr_ref< TYPE >。
```c++
    template<typename _Tp1>
        operator auto_ptr_ref<_Tp1>()
```

好了大功告成，临时变量auto_ptr< TYPE >先转成auto_ptr_ref< TYPE >，auto_ptr_ref< TYPE >再传到构造函数中，有了这个auto_ptr_ref类，下面的代码已经可以编过了，如果刚才前面小节中，你去试了发现明明能编过我却说不行，请不要奇怪。

```c++
     auto_ptr<int>ap1=auto_ptr<int>(new int(0));
     auto_ptr<int>ap1(auto_ptr<int>(new int(0)));
```

但是对于const类型的实参还是没法运作的，因为operator auto_ptr_ref< _Tp1 >()是非const的，const对象调不到这个成员函数。


### 不同指针实例间的赋值
假如我们有两个实例，这两个实例的对应指针是不同的，那么我们能对他们进行赋值吗？

```c++
      //关键代码就是对_M_ptr这个变量进行了赋值。
      //template<typename _Tp>
      //_Tp* _M_ptr;
      //所以_M_ptr就是指针类型的变量。

      template<typename _Tp1>
        auto_ptr(auto_ptr<_Tp1>& __a) throw() : _M_ptr(__a.release()) { }

      template<typename _Tp1>
        auto_ptr&
        operator=(auto_ptr<_Tp1>& __a) throw()
        {
	       reset(__a.release()); //
	       return *this;
	 } 

      //其中reset的实现如下
      void
      reset(element_type* __p = 0) throw()
      {
	     if (__p != _M_ptr)
	     {
	       delete _M_ptr;
	       _M_ptr = __p;
	     }
      }
```

可以看出A=B这样的表达式中，只要B对应的指针类型能够赋值给A对应的指针类型，那么这个赋值就是可行的。比如父子类之间。

```c++
	 SON *pson = NULL;
     auto_ptr<SON> ap1(pson);
     auto_ptr<FATHER> ap2(ap1);
```

而反过来把FATHER赋给SON就会报错了。



### 命运
说了这么多，好像很高级的样子，但是std::auto_ptr在最新的c++11标准草案中被std::unique_ptr取代。主要原因是auto_ptr在进行赋值时默默进行着控制权转移，而这个动作容易导致对失去控制权的实例的错误使用。一个特别的例子是把auto_ptr放到容器中时。下偏讲unique_ptr时讲。



     
