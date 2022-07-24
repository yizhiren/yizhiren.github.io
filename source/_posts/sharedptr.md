---
title: shared_ptr 之shared_from_this
tags:
  - 西佳佳
categories:
  - 代码
date: 2016-11-14 17:34:46
updated: 2016-11-14 17:34:46
---

# shared_ptr 之shared_from_this

## 简介
shared_ptr包含在头文件< memory >中，它被用于共享某个指针的场景下智能管理指针的生命周期。
怎么个智能法：当没人再用这个指针的时候释放指针，看起来很像GC对不对，不过比GC及时，shared_ptr是一旦没人用了立即释放，而GC是会等等看，看情况再来释放。

首先来看一个典型的用法：
```c++
void simple(){
	std::shared_ptr<int> sp(new int(0));
	std::shared_ptr<int> sp2 = sp;	
}

```

可以看出两点，一个是shared_ptr是可以赋值给别的变量的，不需要像unique_ptr那样通过move来赋值，因为shared_ptr不是独占指针而是共享，所以赋值是很平常的操作。 二是你不需要去手动释放该指针，new出来的变量会在最后一个相关联的shared_ptr消失时被释放，也就是在simple函数退出时，sp和sp2相继被销毁，于是new出来的变量也紧接着被释放，没有后顾之忧。

再来看一个错误的用法：
```c++
void fail(){
	int * p=new int(0);
	std::shared_ptr<int> sp(p);
	std::shared_ptr<int> sp2(p);	
}

```
<!-- more -->

这里p被送到两个shared_ptr中，是否也是没有后顾之忧呢，并不是。为啥？上个例子中sp和sp2是有关联的，所以最后一个负责释放new的变量。而这里sp和sp2是没有关联的，他们并不知道对方的存在，因此sp和sp2会争相去释放p指针，导致重复释放。所以要注意，一个裸指针只能用来初始化一个shared_ptr，就好比你只能嫁给一个男人，然后结婚后可以生出一堆的孩子，但是你不能同时嫁给两个人，这两个男人一定会撕逼的。你只能与你的丈夫儿子共享，不能共享给多个丈夫，程序也是有伦理的！


## shared_from_this使用场景
终于要说到这个点上了, 来看使用场景

```c++
class Widget;
std::vector<std::shared_ptr<Widget> > processedWidgets;

class Widget {
public:
 void process(){
 	processedWidgets.emplace_back(this);
 }

};

int main(int argc, char** argv) {
	Widget * p=new Widget();
	processedWidgets.emplace_back(p);
	p->process();

	return 0;
}

```

这个使用场景的关键是如果一个类的成员函数需要产生一个持有自身的shared_ptr该怎么办，在这个例子中我们使用了processedWidgets.emplace_back(this); 把this指针传给shared_ptr来构造一个shared_ptr对象。
也就是在	p->process(); 之后vector中应该就有两个shared_ptr了。那这么做有没有问题呢？

你应该没有忘记前面说的嫁给多个男人的问题吧，这里犯了同样的问题，processedWidgets.emplace_back(this);是一个新嫁男人的行为，调用多次就嫁多次，最后造成重复释放this的问题。

所以我们的代码要改，而且必须使用enable_shared_from_this这个类：
```c++
class Widget;
std::vector<std::shared_ptr<Widget> > processedWidgets;

// 继承enable_shared_from_this
class Widget :public std::enable_shared_from_this<Widget>{
public:
 void process(){
	 // 调用shared_from_this
 	processedWidgets.emplace_back(shared_from_this());
 }

};

int main(int argc, char** argv) {
	Widget * p=new Widget();
	processedWidgets.emplace_back(p);
	p->process();

	return 0;
}

```

我们通过继承enable_shared_from_this这个类，继承后就拥有了shared_from_this接口，调用它就可以获取与自身关联的shared_ptr.
那么为什么继承了它就能得到呢，怎么实现的呢？


## shared_from_this实现原理
秘密在shared_ptr的构造函数中，这句话意味着，要shared_from_this返回你要的东西，必须先调用shared_ptr，在我们的例子中processedWidgets.emplace_back(p);这句话会调用shared_ptr的构造函数完成秘密任务。否则shared_from_this会抛出异常。

这个秘密是，我用伪码表示：
```
shared_ptr(TP* tp){
    if(tp instanceOf enable_shared_from_this){
         save_shared_ptr_info_into(tp->weak_ptr_obj)
    }
}

shared_ptr enable_shared_from_this::shared_from_this(){
    return  get_shared_ptr_from_info(weak_ptr_obj);
}

```
也就是在构造函数中判断这个指针是否是继承了enable_shared_from_this这个类，如果继承了就保存信息到enable_shared_from_this的某个成员中（这个成员是weak_ptr类型的，能够通过它反过来得到shared_ptr），这样shared_from_this函数就能过通过这个weak_ptr来得到shared_ptr了，weak_ptr是一种类似shared_ptr但是不会增加shared_ptr包含的指针的引用计数值的一种类，又扯出了引用计数这个名词，不想展开，总之weak_ptr能够保存shared_ptr的信息并反过来得到shared_ptr。

## shared_from_this的黑科技
but！然而 instanceOf 这个功能在java中存在，在C++中却闻所未闻，于是C++只能通过它的黑科技来实现这个功能了。
我们来看代码

```c++
   
   template<typename _Tp1>
   explicit __shared_ptr(_Tp1* __p)
        : _M_ptr(__p), _M_refcount(__p)
	{
	 //......
	  __enable_shared_from_this_helper(_M_refcount, __p, __p);
	}
```

```c++
  template<_Lock_policy _Lp, typename _Tp1, typename _Tp2>
  void
  __enable_shared_from_this_helper(const __shared_count<_Lp>&,
				     const __enable_shared_from_this<_Tp1,
				     _Lp>*, const _Tp2*) noexcept;


  template<typename _Tp1, typename _Tp2>
  void
  __enable_shared_from_this_helper(const __shared_count<>&,
				     const enable_shared_from_this<_Tp1>*,
				     const _Tp2*) noexcept;

  template<_Lock_policy _Lp>
  inline void
  __enable_shared_from_this_helper(const __shared_count<_Lp>&, ...) noexcept
    { }
```

注意看保存shared_ptr到weak_ptr的函数就是这个\__enable_shared_from_this_helper.在shared_ptr的构造函数中它会去调用这个函数，然而他并没有判断是否继承enable_shared_from_this啊？
我们首先来看\__enable_shared_from_this_helper这个函数被重载了3个，构造函数中到底调用的是哪一个呢？
我们来看shared_ptr的构造函数需要吃一个裸指针，这个裸指针被传给__enable_shared_from_this_helper函数，那我们是不是能够根据这个裸指针来决定调用哪个函数呢？ 答案是肯定的。

```
  如果裸指针继承了__enable_shared_from_this，那么调用第一个
  如果裸指针继承了enable_shared_from_this，那么调用第二个
  如果裸指针没有继承前面两个，那么调用第三个
```

我们看到第三个函数的实现是空的，也就是说如果没有继承，那么就啥也不做，不保存任何信息，符合我们的预期。
如果继承了enable_shared_from_this，调用的第二个函数的实现我不贴了，大概就是保存信息到enable_shared_from_this对象的内部。
那么__enable_shared_from_this是啥？加了连个下划线有什么差别吗？

## 下划线版本的share_ptr
如果你是个很细心的人，你会看到上面share_ptr的构造函数中函数名是__shared_ptr 而不是shared_ptr，也有多出两个下划线。
所以这样就有4个类了
```
__shared_ptr
__enable_shared_from_this
shared_ptr，
enable_shared_from_this
```
他们的关系是什么？

答案是，没有下划线的是有下划线的一个特化版本，比如__shared_ptr包含两个模板参数，第二个参数是_Lock_policy.
```
    // 由于第二个模板参数有默认类型，所以可以不指定
    template<typename _Tp, _Lock_policy _Lp = __default_lock_policy>
    class __shared_ptr;

```
Lock_policy是关于是否采用原子操作来加减引用计数值，又提到引用计数了。总之_Lock_policy就是设置是否采用原子操作，原子操作可以确保多线程环境下得线程安全。
没有下划线的shared_ptr采用的是默认的Lock_policy，这种策略是在多线程环境下（链接了pthread.a）采用原子操作，非多线程环境下采用非原子操作，因为是单线程，肯定不会有资源竞争，所以采用非原子操作可减小不必要的开销。

那么你要问了，说的这么智能那还要这个Lock_policy干嘛，始终采用这个默认的锁策略就好了，这个模板参数可以不用了！
当我带着这个问题到sof上搜索后发现，其实还是有一些人不想用这个智能的策略的，比如虽然我链接了pthread.a但是我能够手工确保我的变量使用不会被多线程访问，所以我还是想用非原子操作的版本。

这个时候shared_ptr就提供了这个带下划线的版本，这个类不是标准推荐的用法，但是算是一种hack，能够满足这么要求。
同时记住，带下划线和不带下划线的版本之间是无法互相传递的（标准不推荐这么做所以自然不给你这个转换），所以这种非标准用法没有可移植性，如果你这么用了你和别人代码将没有互操作性。
那为什么不推荐用却还保留着呢，这是因为还是有小部分人是希望开放锁策略给给shared_ptr的，gcc保留着应该是防止，一旦开放锁策略的人越来越多它能够轻松把实现切换过去。

下面这一段是能够通过编译的使用下划线版本share_ptr的简单例子：

```c++
class Widget: public std::__enable_shared_from_this<Widget,std::__default_lock_policy>
{
public:
	std::__shared_ptr<Widget,std::__default_lock_policy> xxx(){
		return shared_from_this();
	}
};
int main(int argc, char** argv) {
    std::__shared_ptr<Widget,std::__default_lock_policy> sp(new Widget());
    sp->xxx();
    return 0;
}
```

## shared_from_this在多重赋值下的行为

在前面我们就看到一个裸指针只能赋值给一个shared_ptr, 否则会有多重赋值的问题， 所以我们在探讨shared_from_this的返回值时，对于返回的内容是很确定的，或者抛出异常，或者返回一个正常值，而因为该裸指针只赋值给一个shared_ptr，那么返回的正常值一定是与该shared_ptr关联的，也就是能增加该shared_ptr的引用计数的，我又提到了引用计数。引用计数其实就是记录这个裸指针被几个shared_ptr对象所共享，但是对于初始化给多个shared_ptr的异常场景，由于多个初始化的shared_ptr彼此独立，引用计数也是彼此独立的，不会互相干扰。
那么不知道你有没有产生这个疑问，反正我是很有疑问的： 在裸指针被初始化给多个shared_ptr的异常场景下，shared_from_this返回的对象将会增加哪个shared_ptr的引用计数呢？ 对于这种未定义的行为通常答案是由编译器决定。不过我们还是可以试试看他的结果。

```c++

class Widget: public std::enable_shared_from_this<Widget>
{
public:
	std::shared_ptr<Widget> xxx(){
		return shared_from_this();
	}
};
int main(int argc, char** argv) {
	Widget *p = new Widget();
	std::shared_ptr<Widget> one1(p);
	std::shared_ptr<Widget> one2(one1);
	std::shared_ptr<Widget> one3(one1);
	std::cout << one1.use_count() << std::endl;  //3
	
	std::shared_ptr<Widget> two1(p);
	std::cout << two1.use_count() << std::endl;  //1	
	
	
	std::shared_ptr<Widget> guess = p->xxx();
	std::cout << one1.use_count() << std::endl;  //3
	std::cout << two1.use_count() << std::endl;  //2
	std::cout << guess.use_count() << std::endl;  //2

	return 0;  // crash at end
}

```

这段代码的行为我已经注释了，可以看出裸指针通过shared_from_this返回的对象与最近一个初始化的share_ptr相关联。







