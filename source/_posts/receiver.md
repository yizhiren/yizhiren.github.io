---
title: strange golang receiver
tags:
  - 狗狼
categories:
  - 代码
date: 2019-05-23 17:34:46
updated: 2019-05-23 17:34:46
---

# strange golang receiver



## 对象receiver

receiver是什么呢，一句话来解释的话约等于this指针。 
用过c++的同学我们可以来这么来理解。



### 理解c++中的this指针

```c++
class Meta {
public:
	string getName(){
		return this->name;
	}
	string name;
};
```

这个类的成员函数getName中调用了this指针，可是this指针没有定义过呢，哪来的呢？

答案是编译器加的，由于可执行文件中并不存在对象这种概念，但是存在函数的概念，所以编译器就必须把对象的调用转成函数的调用。

编译器是这么做的，他把string getName();这个成员函数转换成string getName(Meta* this);

看到了吧，编译器通过增加一个this参数来吧对象传递到成员函数中去，this指针就这么来了。



### golang的'this'指针

我们看到c++中this是隐式提供的，golang则选择了显式的提供this指针，提供的形式就是receiver。

```
func (receiver) funcName(inputParameters...) (outputParameters...){
	//
}
```
<!-- more -->
按理说receiver也应该是一个指针吧，是的他可以是指针，比如

```go
type Meta struct {
	name string
}

func (this *Meta) getName() string {
	return this.name
}

```

本来这就完了，能跟c++对上了，偏偏他又支持非指针的形式。这就麻烦起来了，能同时用吗？差别是什么？我该用哪个？三脸懵逼。



###  差异解析

先看能不能同时用

```go
package main


type Person struct {

}

func (p Person) commapi() {

}

func (p *Person) commapi() {

}

func main() {
	
}

/**
./sameapi.go:12:6: method redeclared: Person.commapi
	method(Person) func()
	method(*Person) func()
**/

```

报重定义错误，所以不能同时定义的，也就是说明receiver的类型不影响函数的定义，这两个算是同一个函数。那么我们可以猜测了，这两种形式其实是一样的，否则就是只在调用时对调用方有要求或者有差别。我们来验证下调用时有没有差别---能不能调以及是否传入的是同一个对象。

```go
package main

import "fmt"
import "unsafe"

type Person struct {
}

func (this Person) ObjectReceiver() {
	fmt.Printf("ObjectReceiver Get:\t%p\n", &this)
}

func (this *Person) PointerReceiver() {
    fmt.Printf("PointerReceiver Get:\t%p\n", this)
}


func callingTest(){
  fmt.Printf("sizeof Persion: %d\n",  unsafe.Sizeof(Person{}))

  fmt.Println("Object Calling")
  obj := Person{}
  fmt.Printf("origin: \t\t%p\n", &obj)
  obj.ObjectReceiver()
  obj.PointerReceiver()

  fmt.Println("Pointer Calling")
  ptr := &Person{}
  fmt.Printf("origin: \t\t%p\n", ptr)
  ptr.ObjectReceiver()
  ptr.PointerReceiver()	
}


func main() {
	callingTest()
}


/**
sizeof Persion: 0
Object Calling
origin: 		0x545f18
ObjectReceiver Get:	0x545f18
PointerReceiver Get:	0x545f18
Pointer Calling
origin: 		0x545f18
ObjectReceiver Get:	0x545f18
PointerReceiver Get:	0x545f18
**/
```

我们看到，object调用object的receiver、object调用pointer的receiver、pointer调用object的receiver、pointer调用pointer的receiver得到的this指针都是同一个地址。所以我们得出结论，对象形式的receiver和指针形式的receiver没有任何差别，都是传递这个对象(对象本身或者其地址)进到函数中。

结论对吗？？我们注意看`sizeof Persion: 0` ,对象的大小是0，所以即使对象发生了对象新建也还是可能在同一个地址的，不能说明问题。我们再来试一个对象大小非0的试试。

```go
package main

import "fmt"
import "unsafe"

type Person struct {
	any int
}

func (this Person) ObjectReceiver() {
	fmt.Printf("ObjectReceiver Get:\t%p\n", &this)
}

func (this *Person) PointerReceiver() {
    fmt.Printf("PointerReceiver Get:\t%p\n", this)
}


func callingTest(){
  fmt.Printf("sizeof Persion: %d\n",  unsafe.Sizeof(Person{}))

  fmt.Println("Object Calling")
  obj := Person{}
  fmt.Printf("origin: \t\t%p\n", &obj)
  obj.ObjectReceiver()
  obj.PointerReceiver()

  fmt.Println("Pointer Calling")
  ptr := &Person{}
  fmt.Printf("origin: \t\t%p\n", ptr)
  ptr.ObjectReceiver()
  ptr.PointerReceiver()	
}


func main() {
	callingTest()
}

/**
sizeof Persion: 8
Object Calling
origin: 		0xc42008a020
ObjectReceiver Get:	0xc42008a028
PointerReceiver Get:	0xc42008a020
Pointer Calling
origin: 		0xc42008a030
ObjectReceiver Get:	0xc42008a038
PointerReceiver Get:	0xc42008a030
**/
```

看到了吗，结果不一样了，所以上面的结论是错误的。我们来分析下这里发生了什么。

可以看到调用PointerReceiver的函数时，进到函数的对象如论如何都是原始对象(或其地址)，也就是没有对象被新建。而调用ObjectReceiver的函数时，对象都是新建的，类似于值传递，发生了对象的复制，复制之后的内容跟原对象是一样的（浅拷贝），这个我就不贴验证浅拷贝的代码了。



所以前面三脸懵逼的结论是：

同名的PointerReceiver和ObjectReceiver不能重复定义；

ObjectReceiver调用采用值传递会新建对象副本(浅拷贝)，PointerReceiver不会新建副本，并且支持交叉调用，object可以调用PointerReceiver， pointer也可以调用ObjectReceiver；

当你希望函数调用不能改变当前对象，且不介意新建副本的开销，那么选择Object作为Receiver，其他都选择Pointer作为Receiver。



### 匪夷所思

当我们已经沉浸在结论中陶醉欣喜时，新的测试让我们发出了Waht?的呐喊。我们对上面的代码稍作修改：

```go
package main

import "fmt"
import "unsafe"

type Person struct {
	any int
}

func (this Person) ObjectReceiver() {
	fmt.Printf("ObjectReceiver Get:\t%p\n", &this)
}

func (this *Person) PointerReceiver() {
    fmt.Printf("PointerReceiver Get:\t%p\n", this)
}


func callingTest(){
  fmt.Printf("sizeof Persion: %d\n",  unsafe.Sizeof(Person{}))

  fmt.Println("Object Calling")
  obj := Person{}
  fmt.Printf("origin: \t\t%p\n", &obj)
  (Person).ObjectReceiver(obj)
  //(Person).PointerReceiver(obj)

  fmt.Println("Pointer Calling")
  ptr := &Person{}
  fmt.Printf("origin: \t\t%p\n", ptr)
  (*Person).ObjectReceiver(ptr)
  (*Person).PointerReceiver(ptr)
}


func main() {
	callingTest()
}


/***
sizeof Persion: 8
Object Calling
origin: 		0xc42008a020
ObjectReceiver Get:	0xc42008a028
Pointer Calling
origin: 		0xc42008a030
ObjectReceiver Get:	0xc42008a038
PointerReceiver Get:	0xc42008a030
***/
```

我们首先跟之前一样定义了两个函数

`func (this Person) ObjectReceiver()`和

`func (this *Person) PointerReceiver()`,

接着我们分别尝试调用

`(Person).ObjectReceiver(obj)`, 

`(Person).PointerReceiver(obj)`,

 `(*Person).ObjectReceiver(ptr)`, 

`(*Person).PointerReceiver(ptr)`

(怎么样，没见过这么调用的吧，是不是很神奇)，神奇归神奇，这才是golang函数调用更本质的方式，叫做方法表达式（method expression）。
`(Person).ObjectReceiver(obj)` 形式上等价于 `obj.ObjectReceiver()`.

`(Person).PointerReceiver(obj)` 形式上等价于 `obj.PointerReceiver()`.

`(*Person).ObjectReceiver(ptr)` 形式上等价于 `ptr.ObjectReceiver()`.

`(*Person).PointerReceiver(ptr)` 形式上等价于`ptr.PointerReceiver()`.

我们发现，我们只定义了两种形式，但是我们却可以成功调用四中形式中的三种形式(其中`(Person).PointerReceiver(obj)`无法编译通过)。 也就是只有`obj.PointerReceiver()`的时候是失败的。但是根据我们上面好不容易得出的结论，这四种形式的调用应该都是没问题的呀。这又是为什么呢？



### 真相大白

这里面是编译器在起作用，当我们定义了`func (this Person) ObjectReceiver()`的函数的时候，编译器就同时为我们生成了`func (*Person).ObjectReceiver()`的形式。当我们定义了`func (this *Person) PointerReceiver()`的时候，编译器却没有为我们定义`func (this Person) PointerReceiver()`的形式。

这就是使用方法表达式的时候，无法通过object调用PointerReceiver的原因，因为没有定义这个形式的函数。

那为什么前面测试的时候用普通的调用方式却是可以通过object调用PointerReceiver的呢？

我前面提到方法表达式是一种更本质的函数调用方式，因此，编译器实际上是会把你的普通调用方式转换成方法表达式的，而为了照顾到我们平常经常使用到的用法，编译器在看到object.PointerReceiver()的时候就把它转换成(&object).PointerReceiver()或者说是转换成了(*Person).PointerReceiver(&object)的形式。

编译器虽然为我们做了这种转换，但是他本质上是不同意这种用法的，除了这种直接的调用方式，别的调用方式下都是不会自动做转换的，比如方法表达式下不做转换，再比如通过接口调用也不会转换(其实还没到调用那一步，赋值那一步就因为没有自动生成对应的函数形式而报错)， 如下：

```go
package main

import "fmt"

type speaker interface {
	speak()
}

type Person struct {

}

// 注意receiver类型
func (this *Person) speak() {
	fmt.Println("it work")
}


func main() {
	// 注意_speak类型
	var _speaker speaker = Person{}
	_speaker.speak()
}

/**
./untitled.go:21:6: cannot use Person literal (type Person) as type speaker in assignment:
	Person does not implement speaker (speak method has pointer receiver)
**/
```



那么为什么golang要禁止通过object调用PointerReceiver的呢，通过pointer调用ObjectReceiver为什么不一起禁了。

这要从函数定义的目的说起，当你定义了函数`func (this Person) ObjectReceiver()`的时候，你是希望这个函数不会修改调用方那个对象的。那么如果`func (*Person).ObjectReceiver()`也不会修改调用方那个对象，golang自动生成这种形式就没什么风险，就可以生成。我们可以猜测这个函数的实现是

```go
func (this *Person).ObjectReceiver() {
	(Person).ObjectReceiver(*this)
}
```

当我们使用`(*Person).ObjectReceiver(ptr)`调用的时候，ptr传给this指针，不发生对象拷贝，接着执行`(Person).ObjectReceiver(*this)`，这个也就是我们定义的函数`func (this Person) ObjectReceiver()`。我们知道`(Person).ObjectReceiver(*this)`其实就是`(*this).ObjectReceiver()`的方法表达式形式，会发生对象拷贝。因此自动生成这种形式是等价的，没有副作用，都是会产生一次对象拷贝，不会修改调用方那个对象本身。

同样当你定义了函数`func (this *Person) PointerReceiver()`,你是希望函数可以修改调用方那个对象的，如果`func (Person).PointerReceiver()`也会修改调用方那个对象，golang自动生成这种形式就没什么风险，就可以生成。我们可以猜测这个函数的实现是

```go
func (this Person).PointerReceiver() {
	(*Person).PointerReceiver(&this)
}
```

当我们使用`(Person).PointerReceiver(obj)`调用的时候,obj传给this，发生一次对象拷贝，然后执行`(*Person).PointerReceiver(&this)`, 这个也就是我们定义的函数`func (this *Person) PointerReceiver()`。我们知道`(*Person).PointerReceiver(&this)`其实就是(&this).PointerReceiver()，不发生对象拷贝。因此自动生成的这种形式总共发生一次对象拷贝，造成的结果就是这个函数修改的是副本的数据，修改不了调用方的那个对象。也就是不等价。

所以golang不会自动为`func (this *Person) PointerReceiver()`生成`func (Person).PointerReceiver()`。



我又是怎么知道这么高深的原理呢，请看官网的解释：

```
来自 https://golang.org/doc/effective_go.html#pointers_vs_values

The rule about pointers vs. values for receivers is that value methods can be invoked on pointers and values, but pointer methods can only be invoked on pointers.

This rule arises because pointer methods can modify the receiver; invoking them on a value would cause the method to receive a copy of the value, so any modifications would be discarded. The language therefore disallows this mistake. There is a handy exception, though. When the value is addressable, the language takes care of the common case of invoking a pointer method on a value by inserting the address operator automatically. 
```


