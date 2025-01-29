---
title: 线性代数的本质
mathjax: true
tags:
  - 矩阵
categories:
  - 算法
date: 2025-01-29 12:00:00
updated: 2025-01-29 12:00:00
---

## 线性代数的本质
### 建立几何直观
我们在学校学习了如何进行矩阵运算, 熟练进行矩阵计算是基本功,但是你是否思考过, 为什么矩阵运算要这么定义, 矩阵运算是否有更加本质的意义.
对矩阵运算的算术意义的理解让我们能熟练使用矩阵工具来解决实际问题, 但是如果缺乏对计算的几何意义的理解, 当你要进一步深入解决问题的时候, 就会缺失问题解决的效率和灵活性.
打个比方, sin(x)的计算公式如下:
$$
sin(x) = x - \frac{x^{3}}{3!} + \frac{x^{5}}{5!}  - \frac{x^{7}}{7!}  + ... + (-1)^{n-1}\frac{x^{2n-1}}{2n-1!}
$$
于是任何x值,我们都能通过选择适当的n值来计算sin值.  如果我给你一个角度30度, 对应的弧度就是(𝝿/6)约等于0.5236, 于是你可以代入sin(x)的计算公式, `sin(0.5236)=0.5236 - 0.0239 + 0.000328...`, 结果约等于0.5. 这一切都符合预期.
但是如果我们知道sin(x)的几何意义: 在直角三角形中，一个锐角 ∠ A 的正弦定义为它的对边与斜边的比值，也就是：
$$
sin(θ) = \frac{a}{c}
$$
那么我们很容易通过绘制一个直角三角形并测量出sin()的值, 同时我们也很容易产生记忆, 30度角的sin值为0.5.这一切是建立在我们对计算公式产生几何关联的基础上,这种关联拓展了我们的解体思路,也加速我们的计算过程.
这种知识特性适用于各个方面, 他的层级结构如下:

![knowledge_level](/linkimage/matrix/knowledge_level.png)

(来自[线性代数的本质-序言](https://www.bilibili.com/video/BV1ys411472E),可右键复制链接并粘帖到地址栏,直接点击无法打开)

如果我们能掌握矩阵运算跟几何结构的关联, 那么就会对运算形成几,何直观, 更好的掌握和使用他.

<!-- more -->

### 向量

向量有多种理解形式,对于程序员来说, 向量是中括号内的有序数字列表, 是跟列表类似的一个概念;

对于物理学专业的人来说, 向量是空间中的箭头, 由方向和长度决定其唯一性;

这两种视角都可以理解, 并且是彼此一一对应互相可转换表达. 

![vector-on-coordinate](/linkimage/matrix/vector-on-coordinate.png)

(来自[线性代数的本质-向量究竟是什么](https://www.bilibili.com/video/BV1ys411472E?p=2),可右键复制链接并粘帖到地址栏,本节其他截图也来源于此)

因此我们可以把向量视作一种工具, 用于把一堆数字列表可视化, 也便于把空间问题和图形问题转成计算机能处理的运算.

而数学专业的人来说, 向量只需要满足加法运算和数乘运算的的运算规律即可, 满足相加和数乘的基本运算规律的就可以视为向量.数学中向量使用起点位于源点的箭头来表示.

向量运算满足的基本规律如下:
$$
\begin{bmatrix} a \\ c \end{bmatrix} + \begin{bmatrix} b \\ d \end{bmatrix} = \begin{bmatrix} a+c \\ b+d \end{bmatrix}
$$

$$
n \begin{bmatrix} a \\ c \end{bmatrix} = \begin{bmatrix} n*a \\ n*c \end{bmatrix}
$$

比如:
$$
\begin{bmatrix} 1 \\ 2 \end{bmatrix} + \begin{bmatrix} 3 \\ -1 \end{bmatrix} = \begin{bmatrix} 4 \\ 1 \end{bmatrix}
$$

$$
2 \begin{bmatrix} 3 \\ 1 \end{bmatrix} = \begin{bmatrix} 6 \\ 2 \end{bmatrix}
$$

在坐标系中表示的话如下:

![vector_multi](/linkimage/matrix/vector_multi.png)

![vector_multi](/linkimage/matrix/vector_add.png)





### 向量空间

描述向量时, 依赖对基向量的定义.比如 $\begin{bmatrix} 3 \\ 2 \end{bmatrix}$可以认为是3 $\begin{bmatrix} 1 \\ 0 \end{bmatrix}$ + 2 $\begin{bmatrix} 0 \\ 1 \end{bmatrix}$计算得到. 这其中$\begin{bmatrix} 1 \\ 0 \end{bmatrix}$和$\begin{bmatrix} 0 \\ 1 \end{bmatrix}$就称为基向量, 如果把基向量命名成i和j,  那么ai + bj就称为i和j的线性组合. 便于记忆为什么叫线性组合, 可以这么理解: 单独改变a或者b所形成的箭头终点呈一条直线.
我们把i和j的全部线性组合构成的集合叫向量空间, 这个例子中向量空间是一个二维平面, 基向量更多或者更少的情况下, 向量空间可能会是空间,也可能会是直线,甚至是点.
抽出基向量的概念,是为了表示向量空间是跟选取的基向量高度相关的, 比如基向量是$\begin{bmatrix} 1 \\ 0 \end{bmatrix}$和$\begin{bmatrix} 0 \\ 1 \end{bmatrix}$的话3i+2j => 3 $\begin{bmatrix} 1 \\ 0 \end{bmatrix}$ + 2 $\begin{bmatrix} 0 \\ 1 \end{bmatrix}$ => $\begin{bmatrix} 3 \\ 2 \end{bmatrix}$, 如果基向量是$\begin{bmatrix} 1 \\ 2 \end{bmatrix}$和$\begin{bmatrix} 2 \\ -1 \end{bmatrix}$的话3i+2j => 3 $\begin{bmatrix} 1 \\ 2 \end{bmatrix}$ + 2 $\begin{bmatrix} 2 \\ -1 \end{bmatrix}$ => $\begin{bmatrix} 3 \\ 6 \end{bmatrix}$ + $\begin{bmatrix} 4 \\ -2 \end{bmatrix}$ => $\begin{bmatrix} 7 \\ 4 \end{bmatrix}$.
也就是相同的a和b在不同的基向量下得到不同的向量, a和b全部的组合形成的向量空间自然也可能会有不同.之所以说可能, 是因为构成的全量空间有可能相同也可能不同.


### 线性相关:
如果 $\vec{u} = a\vec{v} + b\vec{w}$,  那么说明$\vec{u}$和$\vec{v}$,$\vec{w}$线性相关.这种情况下$\vec{u}$的存在没有扩大$\vec{v}$和$\vec{w}$所在的向量空间.这很容易证明, 因为$\vec{v}$,$\vec{w}$ 都可以通过a$\vec{i}$+b$\vec{j}$构成, 显然$\vec{u}$也是满足a$\vec{i}$+b$\vec{j}$的形式的.
反之任何的a和b下,$\vec{u}$ != $a\vec{v} + b\vec{w}$则说明$\vec{u}$和$\vec{v}$,$\vec{w}$线性无关.
在一个给定空间中, 基向量的线性组合能够形成这个空间. 而彼此线性无关的任意一对/一组向量, 都可以是这个空间的基向量. 彼此线性无关的意思是,任何一个向量都不能通过其他几个基向量经过线性组合获得, 否则,这个基向量就是无意义的,他没有提供空间的扩展, 是无意义的.

### 线性变换
向量空间可以经过变化来实现对空间的拉伸倾斜或者翻转, 变换的方式有很多中, 其中单纯纯粹的一种变换是: 保持原点不变, 原来空间中的任意直线变换后还是直线, 这种变换就叫线性变换. 换个描述:保持原点不变且网格线平行且等距分布的变换叫线性变换.由于向量空间中向量都是基向量的线性组合, 因此向量空间的变换本质上就是基向量的转换,引起的所有基向量的线性组合的转换. 下图展示了向量空间线性变换的结果:

![base_transform](/linkimage/matrix/base_transform.png)

(来自[矩阵与线性变换 ](https://www.bilibili.com/video/BV1ys411472E?p=4)可右键复制链接并粘帖到地址栏,直接点击无法打开)

上图变换显示了基向量从$\begin{bmatrix} 1 \\ 0 \end{bmatrix}$和$\begin{bmatrix} 0 \\ 1 \end{bmatrix}$,变换到$\begin{bmatrix} 3 \\ 1 \end{bmatrix}$和$\begin{bmatrix} 1 \\ 2 \end{bmatrix}$的过程.
假设原来的基向量是$\begin{bmatrix} 1 \\ 0 \end{bmatrix}$和$\begin{bmatrix} 0 \\ 1 \end{bmatrix}$ 原来的向量是$\begin{bmatrix} x \\ y \end{bmatrix}$(本质是x $\begin{bmatrix} 1 \\ 0 \end{bmatrix}$+y $\begin{bmatrix} 0 \\ 1 \end{bmatrix}$), 而线性变换后新的基向量是$\begin{bmatrix} 3 \\ 1 \end{bmatrix}$,$\begin{bmatrix} 1 \\ 2 \end{bmatrix}$ 那么新的向量就是x $\begin{bmatrix} 3 \\ 1 \end{bmatrix}$+y $\begin{bmatrix} 1 \\ 2 \end{bmatrix}$ => $\begin{bmatrix} 3x+y \\ 1x+2y \end{bmatrix}$.

于是我们可以定义一个计算公式 $\begin{bmatrix} 3 & 1 \\\ 1 & 2 \end{bmatrix}$ $\begin{bmatrix} x \\ y \end{bmatrix}$ = x $\begin{bmatrix} 3 \\ 1 \end{bmatrix}$+y $\begin{bmatrix} 1 \\ 2 \end{bmatrix}$ = $\begin{bmatrix} 3x+y \\ 1x+2y \end{bmatrix}$

用更加一般的公式就是:
$$
\begin{bmatrix} a & b \\ c & d \end{bmatrix} \begin{bmatrix} x \\ y \end{bmatrix} = x \begin{bmatrix} a \\ c \end{bmatrix} + y \begin{bmatrix} b \\ d \end{bmatrix} = \begin{bmatrix} ax+by \\ cx+dy \end{bmatrix}
$$
这里我们发现,我们可以用矩阵乘法来表示向量空间中某个向量的线性变换,其中左侧矩阵表示变换后的基向量的组合, 右侧向量代表原来空间中的向量. 得到的结果就是变换后的新向量.



### 矩阵乘法

上面我们已经发现矩阵乘以向量的意义, 他本质是对向量进行线性变换.我们也可以来看看矩阵乘矩阵的定义.

如果对向量连续做两次线性变换先m1变换再m2变换:`[m2]([m1][vec])`, 他应当等价于一次总的线性变换:`[m][vec]`.
因此我们可以定义矩阵乘法: `[m2][m1] = [m]`. 我们来推理一下m的值.   
$$
m1=\begin{bmatrix} a1 & b1 \\ c1 & d1 \end{bmatrix} 
$$

$$
m2=\begin{bmatrix} a2 & b2 \\ c2 & d2 \end{bmatrix} 
$$
假设m1和m2定义如上, `[m2]([m1][vec])`的作用等价与把$\begin{bmatrix} 1 \\ 0 \end{bmatrix}$先转到$\begin{bmatrix} a1 \\ c1 \end{bmatrix}$, 再把$\begin{bmatrix} a1 \\ c1 \end{bmatrix}$做一次线性变换m2,结果就是$\begin{bmatrix} 1 \\ 0 \end{bmatrix}$最终的基向量.同样再把$\begin{bmatrix} 0 \\ 1 \end{bmatrix}$转成$\begin{bmatrix} b1 \\ d1 \end{bmatrix}$, 再对$\begin{bmatrix} b1 \\ d1 \end{bmatrix}$做一次线性转换m2,结果就是$\begin{bmatrix} 0 \\ 1 \end{bmatrix}$最终的基向量.也就是说:
$$
\begin{bmatrix} a2 & b2 \\ c2 & d2 \end{bmatrix} 
\begin{bmatrix} a1 & b1 \\ c1 & d1 \end{bmatrix} 
=
\begin{bmatrix}
\begin{bmatrix} a2 & b2 \\ c2 & d2 \end{bmatrix}
\begin{bmatrix} a1 \\ c1 \end{bmatrix} 
\begin{bmatrix} a2 & b2 \\ c2 & d2 \end{bmatrix}
\begin{bmatrix} b1 \\ d1 \end{bmatrix}
\end{bmatrix} 
=
\begin{bmatrix}
\begin{bmatrix} a1*a2 + c1*b2 \\ a1*c2 + c1*d2 \end{bmatrix}
\begin{bmatrix} b1*a2 + d1*b2 \\ b1*c2 + d1*d2 \end{bmatrix}
\end{bmatrix} 
=
\begin{bmatrix}
a1*a2 + c1*b2 & b1*a2 + d1*b2 \\
a1*c2 + c1*d2 & b1*c2 + d1*d2
\end{bmatrix}
$$
去掉中间过程, 我们就得出了矩阵乘法的计算公式:
$$
\begin{bmatrix} a2 & b2 \\ c2 & d2 \end{bmatrix} 
\begin{bmatrix} a1 & b1 \\ c1 & d1 \end{bmatrix} 
=
\begin{bmatrix}
a1*a2 + c1*b2 & b1*a2 + d1*b2 \\
a1*c2 + c1*d2 & b1*c2 + d1*d2
\end{bmatrix}
$$

有了矩阵乘法的定义, 我们来看看矩阵乘法的是否满足交换率.
`[m2][m1] ? [m1][m2]` 这二者是否想等呢? 因为我们已经知道了矩阵乘法等价于线性变换, 那么我们就来比较下先做m1和先做m2这两个是否有差别.
假设m1是一个x轴不变, y轴右转45度的操作, m2是x轴和y轴逆时针转90度的操作.下面两个图, 上面一个是先执行m1再执行m2, 下面一个是先执行m2再执行m1, 可见上下两个结果是不一样的. 于是我们可以得出`[m2][m1] != [m1][m2]`.

![transform_diff_seq](/linkimage/matrix/transform_diff_seq.png)

再来看矩阵乘法是否满足结合率, `[m3]([m2][m1]) ? ([m3].[m2]).[m1]`, 由于使用这两种方式他们的转换顺序都是m1再m2再m3, 因此矩阵乘法是满足结合率的.

### 行列式
行列式定义为变换后空间缩放的比例, 即原先为1的块,变换后形成的几何体变成多大, 如果是负数就表示翻转了, 如果是0就表示空间变成0了.公式为:
$$
det(\begin{bmatrix} a & b \\ c & d \end{bmatrix}) = ad-bc
$$
计算公式推导如下:

![det_formula](/linkimage/matrix/det_formula.png)

(来自[行列式](https://www.bilibili.com/video/BV1ys411472E?p=7),可右键复制链接并粘帖到地址栏,直接点击无法打开)

这是二维情况的计算公式, 3维和多维的行列式计算公式不太直观.

### 线性方程式

什么样的方程式是线性方程式,像下面的这种方程就是线性方程式,公式中不能有指数运算, 变量相乘等奇怪的运算.

```
a1.x + b1.y + c1.z = v1
a2.x + b2.y + c2.z = v2
a3.x + b3.y + c3.z = v3
```

当我们将方程式整理成如上的统一格式的时候,我们发现, 这个公式正好可以用矩阵乘法的方式来表示:
$$
\begin{bmatrix} a1 & b1 & c1 \\ a2 & b2 & c2 \\ a3 & b3 & c3 \end{bmatrix} \begin{bmatrix} x \\ y \\ z \end{bmatrix} = \begin{bmatrix} v1 \\ v2 \\ v3 \end{bmatrix}
$$
也就是说求解问题的解的过程,相当于是寻找一个向量, 对其做线性变换后,结果等于给出的已知向量.简化后的方程式如下:
$$
A\vec{x} = \vec{v}
$$
解法就是左右两边都左乘一个A的逆矩阵`A'`,逆矩阵的的意思是`A'A`等于啥都不做, 如果是二维空间,`A'A`=$\begin{bmatrix} 1 & 0  \\ 0 & 1 \end{bmatrix}$. 左乘一个`A'`之后:
$$
A'A\vec{x} = A'\vec{v}
$$
即
$$
\vec{x} = A'\vec{v}
$$
通常逆矩阵可以由计算机来计算得到,不需要去手工计算逆矩阵.

但是逆矩阵不一定存在,当A的行列式为0的时候, 意味着经过A转换之后, 空间维度降低了, 如果有逆矩阵, 那就意味着要把一个点扩展成一条线, 或者要把一条线扩展成一个面, 这是做不到的, 函数是不具有从1个输入到多个输出的功能的, 因此当行列式为0的时候,逆矩阵是不存在的(解还是可以存在的).

我们这里有一个专门的名词叫'秩'来形容转换后的空间的维度, 秩为1表示一条线, 秩为2代表平面, 秩为3代表3维空间.
一个矩阵的所有可能的转换结果称为列空间, 包括空间压缩为0的情况. 如果转换后的秩与矩阵的维度相同,就称为满秩. 为什么叫列空间, 可以这么记忆,  变换形成的空间就是所有可能的变换结果.


