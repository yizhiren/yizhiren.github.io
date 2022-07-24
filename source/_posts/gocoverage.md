---
title: golang coverage
tags:
  - 狗狼
categories:
  - 代码
date: 2019-06-15 17:34:46
updated: 2019-06-15 17:34:46
---

# Golang Test Coverage

## 简介

本文主要是通过一个详细的例子来讲解golang中集成单元测试和系统测试覆盖率的一般方案。

想当初接手一个毛坯房一般的golang项目，几个go文件，一个build.sh，一个makefile，别的没有了。

写完怎么验证对没对？build通过，然后得部署到环境中，自己构造请求来检查返回值。但是请求是pb格式的，根本无法手工构造，要是json格式的还好弄点。于是我得写个专门的测试程序，写完通过命令行把参数传给这个测试程序，让它构造pb格式的请求并发起请求。随后发现问题，修改问题，再部署上去，这简直是低效到令人发指。

我是个懒人，我不光不想写专门的测试程序，我连部署到环境中都不想部署，毕竟部署到机器上并发送详细测试请求这项工作已经由QA来覆盖了，即使很多团队没有QA，这项工作也应该是要集成到持续集成+持续部署的系统中，不需要每开发一个feature就部署到环境中来进行调试。

所以首先我实现了单元测试的集成，从此无需部署无需专门的测试程序就可以测试功能的正确性。随着测试代码量的增加，我希望有个地方可以统计我哪些代码测到了，哪些没测到，于是我集成了单元测试的覆盖率。为了查看单元测试+系统测试的总体的测试覆盖情况，随后我们又集成了系统测试的覆盖率。为了查看每次提交新代码的覆盖率，随后又集成了增量覆盖率。

最终项目实现了完整的持续集成+持续部署+覆盖率集成。

<!-- more -->

## 最简http server

为了说明测试覆盖率的实现方法，我决定使用一个最简的http服务器来演示。

```bash
coverage_demo/
└── src
    ├── biz
    │   └── biz.go
    ├── lib
    │   └── lib.go
    ├── main.go
    └── Makefile
```

`Makefile` =>

```makefile

ROOT_PATH=$(CURDIR)/../
GOPATH:=$(ROOT_PATH)
export GOPATH

all: format main test

main: 
	go build -o binary

test:
	@echo "TEST TODO"

format:
	gofmt -l -w -s ./

.PHONY: all main test format 


```

`main.go`

```go
package main

import (
	"biz"
	"fmt"
	"net/http"
)

func serverHandler(w http.ResponseWriter, r *http.Request) {
	w.Write([]byte(biz.GetRandomPair()))
}

func runHttpServer() {
	http.HandleFunc("/randompair", serverHandler)
	e := http.ListenAndServe(":9999", nil)
	if e != nil {
		fmt.Println(e)
	}

}

func main() {
	fmt.Println("start server")
	runHttpServer()
	fmt.Println("stop server")
}

```

`biz.go`

```go
package biz

import (
	"fmt"
	"lib"
)

func formatTwoNumber(a, b int) string {
	return fmt.Sprintf("%d-%d\n", a, b)
}

func GetRandomPair() string {
	return formatTwoNumber(lib.GetRandomNumber(), lib.GetRandomNumber())
}


```

`lib.go`

```go
package lib

import (
	"math/rand"
	"time"
)

func GetRandomNumber() int {
	rand.Seed(time.Now().UnixNano())
	return rand.Int()
}

```

这个程序已经是极度简单了，main.go中启动一个http server，注册一个handler，返回一对随机数

简单演示如下

```bash
# 这里启动服务器
➜  coverage_demo cd src
➜  src make
gofmt -l -w -s ./
go build -o binary
TEST TODO
➜  src ./binary
start server
```

```bash
# 这里发起请求
➜  code curl "http://127.0.0.1:9999/randompair"
375982783208422764-1904058377716247975
➜  code curl "http://127.0.0.1:9999/randompair"
5121049171811524864-6535242855443174820
➜  code curl "http://127.0.0.1:9999/randompair"
5569808671870965927-2761778896038562647
```



## 单元测试覆盖率

### 支持单元测试

接下来我们来支持单元测试，首先创建test文件。

```
coverage_demo/
└── src
    ├── binary
    ├── biz
    │   ├── biz.go
    │   └── biz_test.go
    ├── lib
    │   ├── lib.go
    │   └── lib_test.go
    ├── main.go
    └── Makefile
```

我们创建了两个test文件，biz_test.go和lib_test.go.

`biz_test.go`

```go
package biz

import (
	"testing"
)

func TestGetRandomPair(t *testing.T) {
	str := formatTwoNumber(11, 22)
	if str == "11-22\n" {
		t.Log("formatTwoNumber pass")
	} else {
		t.Error("formatTwoNumber fail")
	}
}

```

`lib_test.go`

```go
package lib

import (
	"testing"
)

func TestGetRandomNumber(t *testing.T) {
	if GetRandomNumber() >= 0 {
		t.Log("GetRandomNumber pass")
	} else {
		t.Error("GetRandomNumber fail")
	}
}

```

同时Makefile中增加test项

```makefile

ROOT_PATH=$(CURDIR)/../
GOPATH:=$(ROOT_PATH)
export GOPATH

all: format main test

main: 
	go build -o binary

test:
	go test -v ./...

format:
	gofmt -l -w -s ./

.PHONY: all main test format 


```

注意go中测试文件的固定形式是`xxx_test.go`.测试用例的固定形式是`func TestXxxx(t *testing.T) `。

有的同学可能不喜欢test文件和源码文件放在一起显得很乱，包括我也不喜欢，但是go推荐这么做，包括golang自身的源码中也是这么混合放的，并且这么放是有实实在在的好处的，那就是可以调用包里面的未导出函数，所以就这么放好了。如果你把所有test文件组织到单独的目录，那么你就调用不到原来包里面的未导出函数，也就不能直接测试他们了。

我们来演示下测试效果

```bash
[root@8bb4497f8518 src]# make test
go test -v ./...
?   	_/code/tmp/coverage_demo/src	[no test files]
=== RUN   TestGetRandomPair
--- PASS: TestGetRandomPair (0.00s)
	biz_test.go:10: formatTwoNumber pass
PASS
ok  	biz	0.009s
=== RUN   TestGetRandomNumber
--- PASS: TestGetRandomNumber (0.00s)
	lib_test.go:9: GetRandomNumber pass
PASS
ok  	lib	0.014s
```

可以看到测试都通过了，那测试没过的样式是怎么样的呢？我稍微改点判断条件，

```go
func TestGetRandomNumber(t *testing.T) {
	//if GetRandomNumber() >= 0 {
	if GetRandomNumber() < 0 {
		t.Log("GetRandomNumber pass")
	} else {
		t.Error("GetRandomNumber fail")
	}
}
```

```bash
[root@8bb4497f8518 src]# make test
go test -v ./...
?   	_/code/tmp/coverage_demo/src	[no test files]
=== RUN   TestGetRandomPair
--- PASS: TestGetRandomPair (0.00s)
	biz_test.go:10: formatTwoNumber pass
PASS
ok  	biz	0.016s
=== RUN   TestGetRandomNumber
--- FAIL: TestGetRandomNumber (0.00s)
	lib_test.go:11: GetRandomNumber fail
FAIL
FAIL	lib	0.019s
make: *** [test] Error 1
```

### 单元测试覆盖率

接下来我们来支持覆盖率。我们首先把makefile中test项修改下，目的是在跑测试case的时候把覆盖信息输出到文件中。

```
PWDSLASH:=$(shell pwd|sed 's/\//\\\//g')

test:
	go test -v -covermode=count -coverprofile=coverage.out -coverpkg ./... ./...
	@#workaround:https://github.com/golang/go/issues/22430
	@sed -i "s/_${PWDSLASH}/./g" coverage.out
	@go tool cover -html=coverage.out -o coverage.html
	@go tool cover -func=coverage.out -o coverage.txt
	@tail -n 1 coverage.txt | awk '{print $$1,$$3}'
	
```

我来解释下这些指令：

go test指令中新增了covermode, coverprofile, coverpkg 三个参数，covermode可以设置3个值

```
		set: 只包含某一行是否被执行。
		count: 某一行被执行过多少次
		atomic: 同count，但是用于并发的场景
```

一般就是设置成count，可以统计代码行被执行了几次。coverprofile就是设置覆盖信息的输出文件，覆盖信息包含了哪些行被执行以及执行了几次的信息。coverpkg是列举出要统计覆盖率的包，./...代表当前目录下的所有包，含递归的。

sed指令是对输出的coverage.out文件进行一些处理，把里面当前目录处理成`.`，详细可直接到注释中的url去看。

`go tool cover -html`是根据覆盖信息文件来生成html形式的详细的可视化的页面。

`go tool cover -func`是根据覆盖信息文件来生成基于函数纬度的文本形式的可读的覆盖信息。

由于-func的生成信息的最后一行包含了总的覆盖率值，所以我们tail来输出。

现在我们执行`make test`试试

```bash
[root@8bb4497f8518 src]# make test
go test -v -covermode=count -coverprofile=coverage.out -coverpkg ./... ./...
?   	_/code/tmp/coverage_demo/src	[no test files]
=== RUN   TestGetRandomPair
--- PASS: TestGetRandomPair (0.00s)
	biz_test.go:10: formatTwoNumber pass
PASS
coverage: 8.3% of statements in ./...
ok  	biz	0.009s	coverage: 8.3% of statements in ./...
=== RUN   TestGetRandomNumber
--- PASS: TestGetRandomNumber (0.00s)
	lib_test.go:9: GetRandomNumber pass
PASS
coverage: 16.7% of statements in ./...
ok  	lib	0.010s	coverage: 16.7% of statements in ./...
total: 25.0%
```

我们看到最后一行显示总的覆盖率是25%。

我们来看看coverage.txt和coverage.html分别是什么。

coverage.txt我们就cat出来看

```
[root@8bb4497f8518 src]# cat coverage.txt
./main.go:9:	serverHandler	0.0%
./main.go:13:	runHttpServer	0.0%
./main.go:22:	main		0.0%
biz/biz.go:8:	formatTwoNumber	100.0%
biz/biz.go:12:	GetRandomPair	0.0%
lib/lib.go:8:	GetRandomNumber	100.0%
total:		(statements)	25.0%
```

coverage.html我们打开浏览器看

![coveragehtml](/linkimage/gocoverage/coveragehtml.png)

注意如果你的程序只运行go1.10及以上的版本，那么可以跳过下面`低版本go的覆盖率`这个小节，免得受到干扰，如果你的程序还在运行低版本go，那么往下看。

### 低版本go的覆盖率

刚才我们是在go1.10版本上得到的结果，如果我们用低版本的go来试试，那么在make test的时候就会报错。

```
[root@8bb4497f8518 src]# gvm use go1.6
Now using version go1.6
[root@8bb4497f8518 src]# make test
go test -v -covermode=count -coverprofile=coverage.out -coverpkg ./... ./...
cannot use test profile flag with multiple packages
make: *** [test] Error 1
```

它的意思是当你输出覆盖信息的时候你就不能对所有子目录进行测试，也就是最后一个./...是不允许的。

你可以执行
`go test -v -covermode=count -coverprofile=coverage.out -coverpkg ./... ./lib`，
但是不能执行
`go test -v -covermode=count -coverprofile=coverage.out -coverpkg ./... ./lib ./biz`
也不能执行
`go test -v -covermode=count -coverprofile=coverage.out -coverpkg ./... ./...`，
显然这对我们来说是不满足的，我们肯定是想要每个目录的覆盖率信息的。

#### 方案一

方案一是使用shell脚本遍历子目录并分别执行go test,然后再把生成的覆盖信息合并。

我们创建一个coverage.sh文件

```shell
# 脚本来自 http://singlecool.com/2017/06/11/golang-test/
set -e

profile="coverage.out"
mergecover="merge_cover"
mode="count"

for package in $(go list ./...|grep -v src); do
    coverfile="$(echo $package | tr / -).cover"
    go test -covermode="$mode" -coverprofile="$coverfile" -coverpkg=./... "$package"
done
go test -covermode="$mode" -coverprofile=current.cover -coverpkg=./... ./

grep -h -v "^mode:" *.cover | sort > $mergecover

echo "mode: $mode" > $profile
current=""
count=0
while read line; do
    block=$(echo $line | cut -d ' ' -f1-2)
    num=$(echo $line | cut -d ' ' -f3)
    if [ "$current" == "" ]; then
        current=$block
        count=$num
    elif [ "$block" == "$current" ]; then
        count=$(($count + $num))
    else
        echo $current $count >> $profile
        current=$block
        count=$num
    fi
done < $mergecover

if [ "$current" != "" ]; then
    echo $current $count >> $profile
fi


```

然后修改makefile

```makefile
testlow:
	sh coverage.sh
	@sed -i "s/_${PWDSLASH}/./g" coverage.out
	@go tool cover -html=coverage.out -o coverage.html
	@go tool cover -func=coverage.out -o coverage.txt
	@tail -n 1 coverage.txt | awk '{print $$1,$$3}'
```

make testlow

```bash
[root@8bb4497f8518 src]# make testlow
sh coverage.sh
warning: no packages being tested depend on _/code/tmp/coverage_demo/src
ok  	biz	0.020s	coverage: 8.3% of statements in ./...
warning: no packages being tested depend on _/code/tmp/coverage_demo/src
warning: no packages being tested depend on biz
ok  	lib	0.015s	coverage: 16.7% of statements in ./...
?   	_/code/tmp/coverage_demo/src	[no test files]
total: 25.0%
```

可以看到总覆盖率也是25%。这种方案是比较推荐的。

#### 方案二

我们也可以把所有测试文件集中到一个独立的目录，比如tests目录中，然后把待测源码中的函数尽量导出，方便测试。

```
coverage_demo/
└── src
    ├── biz
    │   └── biz.go
    ├── lib
    │   └── lib.go
    ├── main.go
    ├── Makefile
    └── tests
        ├── biz_test.go
        └── lib_test.go
```

修改makefile如下

```
testlow:
	go test -v -covermode=count -coverprofile=coverage.out -coverpkg ./... ./tests
	@sed -i "s/_${PWDSLASH}/./g" coverage.out
	@go tool cover -html=coverage.out -o coverage.html
	@go tool cover -func=coverage.out -o coverage.txt
	@tail -n 1 coverage.txt | awk '{print $$1,$$3}'
```



执行meke testlow, 结果25%，正确。

```
[root@8bb4497f8518 src]# make testlow
go test -v -covermode=count -coverprofile=coverage.out -coverpkg ./... ./tests
warning: no packages being tested depend on _/code/tmp/coverage_demo/src
warning: no packages being tested depend on biz
warning: no packages being tested depend on lib
=== RUN   TestGetRandomPair
--- PASS: TestGetRandomPair (0.00s)
	biz_test.go:11: formatTwoNumber pass
=== RUN   TestGetRandomNumber
--- PASS: TestGetRandomNumber (0.00s)
	lib_test.go:10: GetRandomNumber pass
PASS
coverage: 25.0% of statements in ./...
ok  	tests	0.021s
total: 25.0%
```

同时，把测试文件集中放到tests目录在高版本的go中结果也正确。

### 方案总结
我们可以看到，如果你的程序在go1.10及以上，那么支持单元测试覆盖率的目录结构如下, 这种结构方便测试未导出函数。
```
coverage_demo/
└── src
    ├── binary
    ├── biz
    │   ├── biz.go
    │   └── biz_test.go
    ├── lib
    │   ├── lib.go
    │   └── lib_test.go
    ├── main.go
    └── Makefile
```
测试命令是
```
make test
```
如果你的版本在go1.10以下，为了保持能够测试未导出函数的优越性，我们依旧保持上面的结构，只是新增一个coverage.sh文件。
```
coverage_demo/
└── src
    ├── biz
    │   ├── biz.go
    │   └── biz_test.go
    ├── coverage.sh
    ├── lib
    │   ├── lib.go
    │   └── lib_test.go
    ├── main.go
    └── Makefile
```
测试命令是
```
make testlow
```
而不管你的go版本如何，你的makefile可以写得兼容go的不同版本，只需要根据go版本高低选择不同的make命令就可以了
```

ROOT_PATH=$(CURDIR)/../
GOPATH:=$(ROOT_PATH)
export GOPATH

all: format main test

main: 
	go build -o binary

PWDSLASH:=$(shell pwd|sed 's/\//\\\//g')

test:
	go test -v -covermode=count -coverprofile=coverage.out -coverpkg ./... ./...
	@#workaround:https://github.com/golang/go/issues/22430
	@sed -i "s/_${PWDSLASH}/./g" coverage.out
	@go tool cover -html=coverage.out -o coverage.html
	@go tool cover -func=coverage.out -o coverage.txt
	@tail -n 1 coverage.txt | awk '{print $$1,$$3}'

testlow:
	sh coverage.sh
	@sed -i "s/_${PWDSLASH}/./g" coverage.out
	@go tool cover -html=coverage.out -o coverage.html
	@go tool cover -func=coverage.out -o coverage.txt
	@tail -n 1 coverage.txt | awk '{print $$1,$$3}'

format:
	gofmt -l -w -s ./

.PHONY: all main test testlow format 


```

## 系统测试覆盖率

你的程序已经完美支持单元测试及其覆盖率统计，当然多半你的系统也已经接入持续集成和持续部署系统了，这时候光光看单元测试的覆盖率已经不够了，我们需要看单元测试+系统测试总的测试覆盖率，毕竟单看单元测试只能看你写代码自测做的怎么样，而看总体的覆盖率才能看出这个系统总的测试完备程度。

对前面低版本go覆盖率数据的合并操作中我们可以看出覆盖率是可以进行人为合并的，因此，单元测试和系统测试的覆盖率数据我们也会采用分别生成，然后人为合并的方式。

同时为了避免再次引入coverage.sh中的脚本代码，我们后面的操作是基于go1.10来进行的，避免引入外部脚本增加复杂性。同时这之后的代码将不再保证兼容go1.10以下的版本。



### 如何收集系统测试的覆盖率数据

系统测试意味着我们要把编译出来的程序部署到机器上，然后发起请求，让程序动态生成覆盖数据，然后我们拿来分析。

按照其他语言的经验，我猜测是在go build中添加编译参数使得编译出来的程序能够生成覆盖率信息。但是我错了，go的解决方案在go test中，而且方案相当的隐晦。

我们知道go test一执行，程序就刷刷刷的把测试用例都跑完了，根本没有机会部署程序。我们来看看`go test --help`

```
	-c
	    Compile the test binary to pkg.test but do not run it
	    (where pkg is the last element of the package's import path).
	    The file name can be changed with the -o flag.
```

可以发现-c参数的作用是编译出一个test文件，但是不执行他。

我们要利用的正是这个参数，其实它没有说明的一个知识点是，如果当前目录不存在xx_test.go文件，则不生成这个test文件；而当你用-c编译出test文件并尝试执行它的时候，它并不会向平常那样刷刷刷的跑所有case，相反它只会启动当前目录下的test case，也就是如果你在src目录下生成了test文件，稍后执行它时只会启动当前目录下的xx_test.go文件当中的case。

那么为了让test文件可以向正常程序那样启动服务提供服务，我们就必须向正常程序那样启动main函数！

所以我们的方案呼之欲出了：

在当前目录下创建一个main_test.go文件，在main_test.go中创建一个唯一的TestCase(不是唯一的其实也问题不大，但是建议唯一，结构更清晰)，在这个唯一的TestCase中启动main函数。

```go
// test_main.go
package main

import (
	"testing"
)

func TestMain(t *testing.T) {
	main()
}

```

但是如果这么写的话，你在调用不带-c的测试命令时，不就挂在这里走不下去了吗，所以我们想个办法就是通过传递命令行参数，我们在-c编译出来并启动执行时，传入一个特定的参数，检测到参数才启动main函数，这样正常的跑单元测试时就不会被挂起在这里了。

修改后的main_test.go如下

```go
package main

import (
	"testing"
)

var systemTest *bool

func init() {
	systemTest = flag.Bool("SystemTest", false, "Set to true when running system tests")
}

func TestMain(t *testing.T) {
	if *systemTest {
		main()
	}
}
```

同时在makefile中新增指令,

```
test:
	go test -v -covermode=count -coverprofile=coverage.out -coverpkg ./... ./...
	@#workaround:https://github.com/golang/go/issues/22430
	@sed -i "s/_${PWDSLASH}/./g" coverage.out
	@go tool cover -html=coverage.out -o coverage.html
	@go tool cover -func=coverage.out -o coverage.txt
	@tail -n 1 coverage.txt | awk '{print $$1,$$3}'
	go test -c -o binary.test -covermode=count -coverpkg ./...
```

新增了`go test -c -o binary.test -covermode=count -coverpkg ./...`这一行.

现在我们来编译并且执行试试

```
# 这里生成binary.test文件，且正常case没有被block
[root@8bb4497f8518 src]# make test
go test -v -covermode=count -coverprofile=coverage.out -coverpkg ./... ./...
=== RUN   TestMain
--- PASS: TestMain (0.00s)
PASS
# 省略
total: 25.0%
go test -c -o binary.test -covermode=count -coverpkg ./...

# 测试不带SystemTest时
[root@8bb4497f8518 src]# ./binary.test
PASS
coverage: 0.0% of statements in ./...

# 测试带SystemTest时
[root@8bb4497f8518 src]# ./binary.test -SystemTest=true
start server
```

可以看到当我们带着SystemTest=true参数运行binary.test时，http server成功启动了。

现在如果我们到另一个窗口发起请求，我们能不能得到我们想要的覆盖率信息呢，答案是否定的，我们还差关键的两步。

第一此时./binary.test还不知道要把覆盖率信息输出到哪里，因此我们要在启动binary.test时候把文件名传给它`./binary.test -SystemTest=true -test.coverprofile=system.out`.注意是`test.coverprofile`不是`coverprofile`, 比go test时多一个test.的前缀

第二，binary.test有个缺点是不会实时生成coverage信息，而是在binary.test正常退出时候才生成，因此第二步就是在跑完系统测试的case之后要手动发送信号让binary.test退出。注意要正常退出，所以kill -9是不行的。

第一步好说我们把参数加上就可以了：

```
[root@8bb4497f8518 src]# ./binary.test -SystemTest=true -test.coverprofile=system.out
start server

```

接下来我们来实现第二步

### 如何优雅退出服务

通常情况下，我们的httpserver会一直存在，直到进程意外挂掉，或者被运维程序杀掉。

而现在我们不得不实现一个主动退出http server的机制了。

为了主动退出httpserver，我们必须拿到httpserver的实例，然后调用他的shutdown接口。

所以第一步就是改造，把`e := http.ListenAndServe(":9999", nil)`改成

```
server := &Server{Addr: ":9999", Handler: nil}
e := server.ListenAndServe()
```



第二步就是监听signal，当接收到指定信号的signal的时候就调用server.shutdown接口，由于ListenAndServe会阻塞，所以监听的动作需要在server实例创建后，ListenAndServe调用前。

```
server := &Server{Addr: ":9999", Handler: nil}
go handleExitSignal(server)  //会阻塞所以新建goroutine
e := server.ListenAndServe()
```

随后handleExitSignal线程陷入阻塞等待信号量，主线程陷入阻塞等待ListenAndServe返回。

当退出信号到来时，server.shutdown在handleExitSignal线程中被调用。随后主线程和handleExitSignal线程之间通过channel完成一次完美的同步，并退出。

![graceful exit](/linkimage/gocoverage/gracefulexit.png)

所有代码都在main.go中，详细请看注释

```
package main

import (
	"biz"
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
)

// gracefully exit http server
var done = make(chan bool, 1)      // 用于同步main线程和handleExitSignal线程
var quit = make(chan os.Signal, 1) // 用于接收信号量

func handleExitSignal(s *http.Server) {
	// 监听下面两个信号量
	signal.Notify(quit, syscall.SIGTERM) // kill
	signal.Notify(quit, syscall.SIGINT)  // ctrl + c
	// 阻塞等待信号量
	<-quit

	// 关闭server，引起ListenAndServe函数返回
	if err := s.Shutdown(context.Background()); err != nil {
		fmt.Printf("ShutDown Error: %v", err)
	}
	// 通知主线程handleExitSignal结束了
	close(done)
}

func serverHandler(w http.ResponseWriter, r *http.Request) {
	w.Write([]byte(biz.GetRandomPair()))
}

func runHttpServer() {
	http.HandleFunc("/randompair", serverHandler)

	server := &http.Server{Addr: ":9999", Handler: nil}
	go handleExitSignal(server)
	e := server.ListenAndServe()

	if e != nil {
		if http.ErrServerClosed == e {
			fmt.Println("server closed")
		} else {
			fmt.Println("server error")
			os.Exit(1)
		}
	}

	// 等待handleExitSignal完成
	<-done
}

func main() {
	fmt.Println("start server")
	runHttpServer()
	fmt.Println("stop server")
}

```



### 合并覆盖率文件

随着main.go的代码量增大，现在我们在来执行make test看看

```
[root@8bb4497f8518 src]# make test
...省略
total: 12.5%
go test -c -o binary.test -covermode=count -coverpkg ./...
```

可以看到覆盖率下降了。

下面我们来尝试生成system.out并与coverage.out合并。

```
# 请求http server，使产生新的覆盖
[root@8bb4497f8518 src]# curl "http://127.0.0.1:9999/randompair"
2819885537999553053-223459348605777169
```

```
# 找到pid
[root@8bb4497f8518 src]# ps -ef | grep binary.test
root      5182     1  0 01:51 pts/0    00:00:00 ./binary.test -SystemTest=true -test.coverprofile=system.out
root      5194     1  0 01:52 pts/0    00:00:00 grep --color=auto binary.test
```

```
# kill it
[root@8bb4497f8518 src]# kill 5182

```

```
# server closed gracefully
[root@8bb4497f8518 src]# server closed
stop server
PASS
coverage: 87.5% of statements in ./...
```

这里要特别注意，在发送完kill等待server退出时要适当的等待若干秒，比如10秒，不要立即往后面的步骤走，因为对于大项目，代码量大，binary.test在输出覆盖率信息时需要的耗时较长，如果不等待的话，你拿到的覆盖率信息就是残缺的。等待足够时间之后，我们往下走，来合并覆盖率文件。

为了方便合成，我们修改makefile

```
mergecoverage:
	@echo 'mode: count' > total.out
	@tail -q -n +2 coverage.out >> total.out
	@tail -q -n +2 system.out >> total.out
	@sed -i "s/_${PWDSLASH}/./g" total.out
	@go tool cover -html=total.out -o total.html
	@go tool cover -func=total.out -o total.txt
	@tail -n 1 total.txt | awk '{print $$1,$$3}'
```

然后make mergecoverage

```
[root@8bb4497f8518 src]# make mergecoverage
total: 87.5%
```

查看文本形式的函数覆盖信息

```
[root@8bb4497f8518 src]# cat total.txt
./main.go:17:	handleExitSignal	83.3%
./main.go:32:	serverHandler		100.0%
./main.go:36:	runHttpServer		80.0%
./main.go:56:	main			100.0%
biz/biz.go:8:	formatTwoNumber		100.0%
biz/biz.go:12:	GetRandomPair		100.0%
lib/lib.go:8:	GetRandomNumber		100.0%
total:		(statements)		87.5%
```

查看html形式的覆盖信息

可以看到前面单元测试没覆盖到的这次覆盖到了

![total cov biz](/linkimage/gocoverage/totalcovbiz.png)

可以看到main.go中大部分都覆盖到了

![total cov main](/linkimage/gocoverage/totalcovmain.png)



## 增量覆盖率

随着业务进展，代码质量的把关变得越来越严，每一轮的需求实现都需要控制质量。其中代码的测试覆盖率作为基础且重要的一环被引入需求实现的流程中。这其中跟之前不同之处在于，这里要统计的是新增代码的测试覆盖率，所以我们就来想办法实现他。

### 结构化增量信息

增量信息获取可以使用git diff来实现，假如我们最新一次的提交hash值是newCommitHash, 则获取增量信息的指令是`git diff master newCommitHash`.这个命令输出如下内容(摘自golang源码的一段diff)

```
diff --git a/AUTHORS b/AUTHORS
index e861bfc..8b8105b 100644
--- a/AUTHORS
+++ b/AUTHORS
@@ -2,6 +2,10 @@
 # This file is distinct from the CONTRIBUTORS files.
 # See the latter for an explanation.

+# Since Go 1.11, this file is not actively maintained.
+# To be included, send a change adding the individual or
+# company who owns a contribution's copyright.
+
 # Names should be added to this file as one of
 #     Organization's name
 #     Individual's name <submission email address>
@@ -10,26 +14,35 @@
...省略
```

git diff会输出多段内容，每段内容以diff开头。diff下一行是commit信息，再后两行是参与对比的来自修改前和修改后的两个文件名。再后面是多个以@@起始的位于同个文件内的修改片段，`@@ -2,6 +2,10 @@`这段内容的意思是紧随其后列举的代码行是修改前的第2行开始的连续6行，以及修改后的第2行开始的连续10行。再下面紧随其后列举的就是具体的代码行了，空格开始的表示没变化的代码行，减号开头的表示修改前的代码行，加号开头的表示修改后的代码行。

因此我们通过解析git diff的内容就可以知晓具体修改的内容所在的位置，我们可以定义一个数据结构

```
# 伪码
struct Diff{
  modifyFiles map<string, ModifyFile>
}

struct ModifyFile{
  modifyLines []int
}
```

这样一个Diff实例就可以表示这一次的全量修改信息，Diff结构包含一个表，表的key是文件名，value是ModifyFile结构，每个ModifyFile结构表示这个文件中所有的修改行。这个结构解析出来后面备用。

### 结构化覆盖信息

覆盖信息其实我们前面已经拿到了，在`系统测试覆盖率`那一节我们已经拿到了全量覆盖信息total.out，里面包含了单元测试和系统测试的覆盖信息总和。total.out里面的格式是这样的

```
mode: count
lib/lib.go:8.28,11.2 2 0
./main.go:17.39,25.57 4 0
./main.go:29.2,29.13 1 0
...省略
```

第一行是固定格式的，后面的每一行都是如下格式的信息

`name.go:line.column,line.column numberOfStatements count`

即

`文件名:起始行.第几列,结束行.第几列 有效代码行数 覆盖次数`

我们通过解析total.out文件可以解析出工程中所有文件的覆盖信息。我们可以定义一个数据结构

```
# 伪码
struct Coverage{
  covFiles []CovFile
}

struct CovFile{
  filename string
  segments []CovSegment
}

struct CovSegment{
  startLine int
  endLine int
  origCovString string
}
```

一个Coverage结构表示整个工程的覆盖信息，包含一个CovFile数组，一个CovFile表示一个文件的覆盖信息。CovFile结构包含一个CovSegment数组，一个CovSegment包含一个代码块（若干行连续的代码），CovSegment包含原始的覆盖数据`name.go:line.column,line.column numberOfStatements count`, 以及解析出来的起始行号，终止行号。



### 筛选增量的覆盖信息

有了前面的结构化增量数据和结构化覆盖信息，我们就可以从全量的覆盖信息中挑选出增量代码所对应的覆盖信息。

```
# 伪码
echo "mode: count" > newCodeCoverage.out
for covFile in coverage
  filename = covFile.filename
  newCodeInFile = diff.modifyFiles[filename]
  for covSegment in covFile.segments
    for codeLine in newCodeInFile.modifyLines
      if codeLine >= covSegment.startLine && codeLine <= covSegment.endLine then
        echo covSegment.origCovString >> newCodeCoverage.out
        break innerFor
      endif
    endfor
  endfor
endfor
```

随后执行

```
	go tool cover -html=newCodeCoverage.out -o addcoverage.html
	go tool cover -func=newCodeCoverage.out -o addcoverage.txt
```

我们就得到了增量覆盖率结果。





## 源码包下载

实例中的源码下载：[coverage_demo](/linkimage/gocoverage/coverage_demo.zip)



## 参考

[Go多个pkg的单元测试覆盖率](http://singlecool.com/2017/06/11/golang-test/)

[-coverprofile with relative path uses wrong file name](https://github.com/golang/go/issues/22430)

[Code Coverage for your Golang System Tests](https://www.elastic.co/cn/blog/code-coverage-for-your-golang-system-tests)

[Go webserver with gracefull shutdown](https://marcofranssen.nl/go-webserver-with-gracefull-shutdown/)