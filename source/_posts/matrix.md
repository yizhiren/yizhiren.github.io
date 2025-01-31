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

而数学专业的人来说, 向量只需要满足加法运算和数乘运算的的运算规律即可, 满足相加和数乘的基本运算规律的就可以视为向量.几何中向量使用起点位于源点的箭头来表示.

向量运算满足的基本规律如下:
$$
\begin{bmatrix} a \\ c \end{bmatrix} + \begin{bmatrix} b \\ d \end{bmatrix} = \begin{bmatrix} a+b \\ c+d \end{bmatrix}
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

描述向量时, 依赖对基向量的定义.比如 $\begin{bmatrix} 3 \\ 2 \end{bmatrix}$可以认为是3 $\begin{bmatrix} 1 \\ 0 \end{bmatrix}$ + 2 $\begin{bmatrix} 0 \\ 1 \end{bmatrix}$计算得到. 这其中$\begin{bmatrix} 1 \\ 0 \end{bmatrix}$和$\begin{bmatrix} 0 \\ 1 \end{bmatrix}$就称为基向量, 如果把基向量命名成$\vec{i}$和$\vec{j}$,  那么a$\vec{i}$ + b$\vec{j}$就称为$\vec{i}$和$\vec{j}$的线性组合. 便于记忆为什么叫线性组合, 可以这么理解: 单独改变a或者b所形成的箭头终点呈一条直线.
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
解法就是左右两边都左乘一个A的逆矩阵$A^{-1}$,逆矩阵的的意思是$A^{-1}A$等于啥都不做, 如果是二维空间,$A^{-1}A$=$\begin{bmatrix} 1 & 0  \\ 0 & 1 \end{bmatrix}$. 左乘一个$A^{-1}$之后:
$$
A^{-1}A\vec{x} = A^{-1}\vec{v}
$$
即
$$
\vec{x} = A^{-1}\vec{v}
$$
通常逆矩阵可以由计算机来计算得到,不需要去手工计算逆矩阵.

但是逆矩阵不一定存在,当A的行列式为0的时候, 意味着经过A转换之后, 空间维度降低了, 如果有逆矩阵, 那就意味着要把一个点扩展成一条线, 或者要把一条线扩展成一个面, 这是做不到的, 函数是不具有从1个输入到多个输出的功能的, 因此当行列式为0的时候,逆矩阵是不存在的.
不过,即使行列式为0, 逆矩阵不存在, 方程的解还是可以存在的.比如这个就无解:
```
2x + 2y = 2
3x + 3y = 4
```
比如这个就有任意多解:
```
2x + 2y = 2
3x + 3y = 3
```
从几何角度来说, 某个线性变换把二维空间压缩到一根线, 那么当等号右侧的目标向量正好在这根线上, 我们就可以有任意多解都可以达成这一个压缩效果. 但是当等号右侧的目标向量不在这根压缩后的线上的时候, 我们入论如何都达不到这个压缩效果, 因此无解.

![func_solution](/linkimage/matrix/func_solution.png)



我们这里有一个专门的名词叫`秩`来形容转换后的空间的维度, 秩为1表示一条线, 秩为2代表平面, 秩为3代表3维空间.
一个矩阵的所有可能的转换结果称为列空间, 包括空间压缩为0的情况. 如果转换后的秩与矩阵的维度相同,就称为满秩. 为什么叫列空间, 可以这么记忆,  矩阵的每一列都表示基向量, 基向量变换形成的空间就是所有可能的变换结果.



### 非立方矩阵
如果是线性独立的基向量, 显然matrix应该是NxN的行数列数相等. 那么对于那些行数和列数不相同的矩阵,他们又有什么几何上的意义呢?
如果行数大于列数:
$$
\begin{bmatrix} a & b \\ c & d \\ e & f \end{bmatrix}
$$
这样的矩阵可以理解成3维空间中的一个2维平面上的一组基向量, 其列空间就是一个3维空间上的2维平面.他的几何意义是二维空间在三维平面上的映射.

如果行数小于列数:
$$
\begin{bmatrix} a & b & c \\ d & e & f \end{bmatrix}
$$

这样的矩阵可以理解成原3维空间中的一组基向量投影在一个2维平面上, 其列空间也是2维平面.他的几何意义是三维空间在二维平面上的映射. 这样的一组基向量,显然彼此是会存在线性相关的.

### 点积
两个向量的点积, 计算公式如下:
$$
\begin{bmatrix} a \\ b \\ c \end{bmatrix} . \begin{bmatrix} d \\ e \\ f \end{bmatrix} = ad + be + cf
$$
碰巧等于
$$
\begin{bmatrix} a & b & c \end{bmatrix} \begin{bmatrix} d \\ e \\ f \end{bmatrix} =  ad + be + cf
$$
也就是说两个向量的点积, 正好等于把其中一个向量看成是线性变换, 变换到一维的直线上.因为点积是满足交换率的,所以说可以把其中任意一个看成是线性变换.
由于线性变换是变换到一条直线上,$\begin{bmatrix} a & b & c \end{bmatrix}$ 就相当于空间中这条直线上的一个向量.我们再把$\begin{bmatrix} a & b & c \end{bmatrix}$变换成 $len * \begin{bmatrix} a0 & b0 & c0 \end{bmatrix}$, 也就是变成长度乘以单位向量的形式.
$$
\begin{bmatrix} a & b & c \end{bmatrix} \begin{bmatrix} d \\ e \\ f \end{bmatrix} = len*\begin{bmatrix} a0 & b0 & c0 \end{bmatrix} \begin{bmatrix} d \\ e \\ f \end{bmatrix}
$$
同时$\begin{bmatrix} a0 & b0 & c0 \end{bmatrix} \begin{bmatrix} d \\ e \\ f \end{bmatrix}$又等于是$\begin{bmatrix} d \\ e \\ f \end{bmatrix}$在$\begin{bmatrix} a0 & b0 & c0 \end{bmatrix}$上的投影长度.
因此$\begin{bmatrix} a & b & c \end{bmatrix} \begin{bmatrix} d \\ e \\ f \end{bmatrix}$等于是$\begin{bmatrix} a & b & c \end{bmatrix}$的长度乘以$\begin{bmatrix} d \\ e \\ f \end{bmatrix}$在$\begin{bmatrix} a & b & c \end{bmatrix}$上的长度.
向量点积的这种巧合性,即向量点积等于一维矩阵和向量的乘积,称为对偶性,其概念比较接近巧合性.当然对偶性不止于此, 这只是对偶性的一个体现之处.

$\begin{bmatrix} a0 & b0 & c0 \end{bmatrix} \begin{bmatrix} d \\ e \\ f \end{bmatrix}$等于是$\begin{bmatrix} d \\ e \\ f \end{bmatrix}$在$\begin{bmatrix} a0 & b0 & c0 \end{bmatrix}$上的投影长度, 这一点单独证明:
假设我们有一个二维空间中的单位向量$\vec{u}$, 我们试图找到一个线性变换, 变换的结果是得到任意向量在$\vec{u}$上的投影. 由我们的一些前置经验知道,我们本质上只要知道基向量的投影变换,也就知道了任意向量的投影变换.  我们作一个辅助图:

![vec_projection](/linkimage/matrix/vec_projection.png)

图中$\vec{i}$长度是1, $\vec{u}$长度也是1,他的向量值是$\begin{bmatrix} a0 \\ b0 \end{bmatrix}$.因此$\vec{i}$在$\vec{u}$上的投影长度应该是等于$\vec{u}$在$\vec{i}$上的投影长度. 而$\vec{u}$在$\vec{i}$上的长度等于`a0`, 因此$\vec{i}$投影到$\vec{u}$上也是`a0`, 同理$\vec{j}$投影到$\vec{u}$上是`b0`, 由此我们可以得出任意向量到$\vec{u}$的投影变换就是$\begin{bmatrix} a0 & b0 \end{bmatrix}$. 因此$\begin{bmatrix} a0 & b0 \end{bmatrix} \begin{bmatrix} d \\ e  \end{bmatrix}$ 就是$\begin{bmatrix} d \\ e  \end{bmatrix}$在$\begin{bmatrix} a0 & b0 \end{bmatrix}$上的投影长度. 拓展到3维, 也就证明了$\begin{bmatrix} a0 & b0 & c0 \end{bmatrix} \begin{bmatrix} d \\ e \\ f \end{bmatrix}$等于是$\begin{bmatrix} d \\ e \\ f \end{bmatrix}$在$\begin{bmatrix} a0 & b0 & c0 \end{bmatrix}$上的投影长度.

### 叉积
如果我们给出两个向量$\vec{v}$和$\vec{w}$, 定义$\vec{v}$ X $\vec{w}$结果为与$\vec{v}$和$\vec{w}$的平面垂直, 而长度为$\vec{v}$和$\vec{w}$组成的矩形面积,这样的一个向量.
垂直的向量有两个方向, 满足右手定律的方向的这个定为叉积的方向.

![cross_multi_right_hand_rule](/linkimage/matrix/cross_multi_right_hand_rule.png)

(来自[叉积的标准介绍](https://www.bilibili.com/video/BV1ys411472E?p=11),可右键复制链接并粘帖到地址栏,直接点击无法打开)

另外$\vec{v}$和$\vec{w}$组成的矩形面积,正是前面提过的行列式的值.

![cross_multi_right_hand_rule](/linkimage/matrix/det_xy.png)

(来自[叉积的标准介绍](https://www.bilibili.com/video/BV1ys411472E?p=11),可右键复制链接并粘帖到地址栏,直接点击无法打开)

叉积的计算公式可以如此来推导:

假设$\vec{v}=\begin{bmatrix} v1 \\ v2 \\ v3 \end{bmatrix}$, $\vec{w}=\begin{bmatrix} w1 \\ w2 \\ w3 \end{bmatrix}$, 那么我们可以定义这样一个计算行列式的方程:
$$
f(\begin{bmatrix} x \\ y \\ x \end{bmatrix}) = det(\begin{bmatrix} x & v1 & w1 \\ y & v2 & w2 \\ z & v3 & w3 \end{bmatrix})
$$
这个函数的参数是一个任意向量$\begin{bmatrix} x \\ y \\ x \end{bmatrix}$, 函数值则是该任意向量与$\vec{v}$和$\vec{w}$组成的立方体体积,也就是行列式值.
因为函数结果是一个值, 所以我们可以想象, 存在这样一个线性变换$\begin{bmatrix} p1 & p2 & p3 \end{bmatrix}$的函数解, 满足:
$$
\begin{bmatrix} p1 & p2 & p3 \end{bmatrix} \begin{bmatrix} x \\ y \\ x \end{bmatrix} = det(\begin{bmatrix} x & v1 & w1 \\ y & v2 & w2 \\ z & v3 & w3 \end{bmatrix})
$$
而因对偶性:
$$
\begin{bmatrix} p1 & p2 & p3 \end{bmatrix} \begin{bmatrix} x \\ y \\ x \end{bmatrix} = \begin{bmatrix} p1 \\ p2 \\ p3 \end{bmatrix} . \begin{bmatrix} x \\ y \\ x \end{bmatrix}
$$
同时$\begin{bmatrix} p1 \\ p2 \\ p3 \end{bmatrix} . \begin{bmatrix} x \\ y \\ x \end{bmatrix}$又有一个几何意义就是一个向量在另一个向量上的投影乘以后者这个向量的长度.所以这就意味着, 这个函数的右侧是3个向量构成的立方体的体积, 左侧是一个向量在另一个上的投影乘以后者的长度. 我们来画个示意图:
![volume_on_calc_cross](/linkimage/matrix/volume_on_calc_cross.png)
(来自[以线性变换的眼光看叉积](https://www.bilibili.com/video/BV1ys411472E?p=12),可右键复制链接并粘帖到地址栏,直接点击无法打开)
上图中灰色箭头就是矩形的高, 那么我们可以容易想到,$\begin{bmatrix} p1 \\ p2 \\ p3 \end{bmatrix}$向量就是一个方向与灰色箭头一致,长度是底下矩形面积的这样一个向量. 这个向量正好就是我们要求的叉积!

我们回头看刚才的等式, 
$$
\begin{bmatrix} p1 \\ p2 \\ p3 \end{bmatrix} . \begin{bmatrix} x \\ y \\ x \end{bmatrix} = det(\begin{bmatrix} x & v1 & w1 \\ y & v2 & w2 \\ z & v3 & w3 \end{bmatrix})
$$
我们通过展开公式可以得出p1,p2,p3的值, 这也就是叉积的计算公式:
```
p1 = v2w3-v3w2
p2 = v3w1-v1w3
p3 = v1w2-v2w1
```
![cross_calc_value](/linkimage/matrix/cross_calc_value.png)
实际计算的时候会施加一个小技巧, 会把x替换成$\vec{i}$,把y替换成$\vec{j}$, 把z替换成$\vec{k}$, 这时候直接展开det公式就直接得到了叉积$\vec{i}(v2w3-v3w2) + \vec{j}(v3w1-v1w3) + \vec{k}(v1w2-v2w1)$, 这个技巧不好说明确的意义, 但是是有效的.
![cross_calc_value](/linkimage/matrix/cross_with_base.png)

### 基变换
前面我们讲到一个矩阵乘以一个向量, 其几何意义是把这个向量做一个线性变换, 再进一步说, 是因为基向量做了一个线性变换, 所以其空间中的每一个向量都应该做一个相同比例的变换.
现在我们换一个思路, 以坐标系的角度来思考这个线性变换的问题.我们左乘一个矩阵, 等价于坐标系发生了拉伸变换, 拉伸变换后的新坐标系就是矩阵中的列.
![base_change](/linkimage/matrix/base_change.png)
比如上图左乘一个矩阵$\begin{bmatrix} 2 & -1 \\ 1 & 1 \end{bmatrix}$, 可以理解成坐标系拉伸变换, 新的坐标系的基向量是$\begin{bmatrix} 2 \\ 1 \end{bmatrix}$和$\begin{bmatrix}  -1 \\ 1 \end{bmatrix}$.这时候拉伸变换前的坐标系中的向量也跟着一起发生了等比例的拉伸变换. 又因为我们知道新坐标系的基向量在旧坐标系下是$\begin{bmatrix} 2 & -1 \\ 1 & 1 \end{bmatrix}$, 所以等比例地,新坐标系下的任意变量在旧坐标系下就是$\begin{bmatrix} 2 & -1 \\ 1 & 1 \end{bmatrix}$乘以该向量.
也就是说矩阵乘以向量, 有另一个几何意义,就是把`以矩阵的列作为基向量的坐标系`下的向量转成默认坐标系下的向量. 是对同一向量的不同视角的改变.

![transform_meaning](/linkimage/matrix/transform_meaning.png)

(来自[基变换](https://www.bilibili.com/video/BV1ys411472E?p=13),可右键复制链接并粘帖到地址栏,直接点击无法打开)

总结来说,左乘一个矩阵, 一方面相当于我们对默认网格做了拉伸,变成一个自定义的网格.另一方面相当于是把新网格下的坐标值转成默认坐标系下的坐标值.我们可以得出一个公式(下标表示视角):
$$
\begin{bmatrix} M \end{bmatrix}_d \vec{V}_M = \vec{V}_d
$$
即M坐标系下的向量$\vec{V}$,左乘默认视角下的M坐标系矩阵, 结果就是默认视角下的向量$\vec{V}_d$.
同理我们可以通过逆矩阵来得到相反的结果:
$$
\vec{V}_M = \begin{bmatrix} M \end{bmatrix}_d^{-1} \vec{V}_d
$$
即在知道默认坐标系下的向量以及M坐标系基向量组成的矩阵, 我们就可以求出M的逆矩阵, 进而求出M坐标系下的向量, 也就是把默认坐标系视角的向量转成M坐标系视角的向量.

下面有坐标系视角转换引出的问题, 假如我们有一个A视角下的向量$\vec{V}_A$, 现在要对向量做一次默认视角下的线性变换$\begin{bmatrix} M \end{bmatrix}_d$, 那么转换后A视角下的向量值会是多少呢? 答案是:
$$
\begin{bmatrix} A \end{bmatrix}_d^{-1} \begin{bmatrix} M \end{bmatrix}_d \begin{bmatrix} A \end{bmatrix}_d \vec{V}_A
$$
计算顺序从右往左,也就是先转成默认视角的向量, 再执行线性变换, 再转回A视角.这个过程很合乎逻辑合乎我们的思路.
所以我们可以得出把线性变换前后用A的逆矩阵和矩阵包裹之后,就是A视角下的线性变换公式.
$$
\begin{bmatrix} A \end{bmatrix}_d^{-1} \begin{bmatrix} M \end{bmatrix}_d \begin{bmatrix} A \end{bmatrix}_d
$$

### 特征值和特征向量
什么是特征向量, 当某次线性变换中,某个直线上的向量变换后还是在这条直线上, 那么直线上的向量就是特征向量.

![feature_vector_def](/linkimage/matrix/feature_vector_def.png)

(来自[特征向量和特征值](https://www.bilibili.com/video/BV1ys411472E?p=14),可右键复制链接并粘帖到地址栏,直接点击无法打开)

比如上图线性变换为$\begin{bmatrix} 3 & 1 \\ 0 & 2 \end{bmatrix}$, 其中的黄色的斜线上的那些向量就是特征向量. 而转换后把向量拉长或者压缩的比例就是特征值, 大于1表示拉长,小于1表示压缩, 大于0表示方向不变, 小于0表示方向相反. 在空间中我们可以把特征向量所在直线看成是变换的旋转轴.

![feature_vector_axis](/linkimage/matrix/feature_vector_axis.png)

特征值和特征向量的推导过程大致如下, 首先根据定义:
$$
A\vec{V} = \lambda\vec{V}
$$
随后
$$
A\vec{V} = \lambda\vec{V} = (\lambda I)\vec{V}
$$
$$
A\vec{V} - (\lambda I)\vec{V} = \vec{0}
$$
$$
(A - \lambda I)\vec{V} = \vec{0}
$$
其中`I`表示元向量,比如$\begin{bmatrix} 1 & 0 \\ 0 & 1  \end{bmatrix}$, 因此更加直观的来展开看的话(以2维空间为例):
$$
(A - \lambda I)\vec{V} = \begin{bmatrix} a-\lambda & b \\ c & d-\lambda \end{bmatrix}\vec{V} = \vec{0}
$$
这个公式的意思是同一直线上的向量经过$\begin{bmatrix} a-\lambda & b \\ c & d-\lambda \end{bmatrix}$转换后都是0向量,也就是这个方向上的向量都被压缩成了0向量, 那么唯一可能的就是$\begin{bmatrix} a-\lambda & b \\ c & d-\lambda \end{bmatrix}$的行列式值$det(\begin{bmatrix} a-\lambda & b \\ c & d-\lambda \end{bmatrix})$为0.即$(a-\lambda)(d-\lambda) - bc = 0$ 这里可以求出$\lambda$的值,无解的话表示不存在特征向量.求出值后,$\lambda$就是一个已知值, 这时候代入公式,再把$\vec{V}$展开成x和y:
$$
\begin{bmatrix} a-\lambda & b \\ c & d-\lambda \end{bmatrix} \begin{bmatrix} x \\ y \end{bmatrix} = \vec{0}
$$
由于`a/b/c/d/λ`都是已知值, 因此就可以得到x/y之间的线性关系.
显然如果此时$a-\lambda$,b,c,$d-\lambda$都是0, 这里的x/y就可以有任意多的解, 也就存在任意多的特征向量.

下图这个例子展示了A等于$\begin{bmatrix} 2 & 2 \\ 1 & 3 \end{bmatrix}$的情况下求出特征值$\lambda$值为1. 以及求得的特征向量所在直线为`x+2y = 0`(图中没画出).
![feature_vector_to_line](/linkimage/matrix/feature_vector_to_line.png)

如果我们能找到一组线性无关的特征向量,他们构成的向量空间与原空间一致, 那么这组特征向量就同时是这个空间的基向量, 我们叫他特征基.
假如特征基构成的矩阵叫[M],特征基对应的线性变换是A, 那么根据前面基变换的经验$A^{-1}[M]A$就是[M]在A坐标系统视角下的对应变换$[M]_A$.我们可以确定的是$[M]_A$一定是一个对角矩阵,只有对角矩阵的每个基都是特征向量,比如:
![diagonal_matrix](/linkimage/matrix/diagonal_matrix.png)
这个性质可以给我们带来一些计算上的帮助, 假如你要执行$[M]^{100}$, 那么我们可以先$A^{-1}[M]A$计算出$[M]_A$, 然后执行($[M]_A)^{100}$, 再执行左乘$A$转换回默认视角. 这样绕一大圈的好处是因为对角矩阵乘法的计算比较简单.
$$
\begin{bmatrix} a & 0 & 0 \\ 0 & b & 0 \\ 0 & 0 & c \end{bmatrix} ^ {100} \begin{bmatrix} x \\ y \\ z \end{bmatrix} = \begin{bmatrix} a^{100}x \\ b^{100}y \\ c^{100}z \end{bmatrix}
$$
补充一个简单说明,对角矩阵的每个基都是特征向量. 高维的不好证明, 二维的可以简单证明:
对角矩阵如下:
$$
\begin{bmatrix} a & 0 \\ 0 & b \end{bmatrix}
$$
求解$\lambda$的公式如下:
$$
\begin{bmatrix} (a-\lambda) & 0 \\ 0 & (b-\lambda) \end{bmatrix} \begin{bmatrix} x \\ y \end{bmatrix} = 0
$$
所以我们可以用$(a - \lambda) (b-\lambda)-0=0$ 来计算$\lambda$. 随后根据求出的$\lambda$代回公式, 可得方程:
$$
(a-\lambda) x = 0
$$
$$
(b-\lambda) y = 0
$$
很容易可知`x=0`和`y=0`是两个解, 就在基向量上, 得到证明.

### 抽象向量
前面最开始提到数学上向量的定义的时候讲过:
```
而数学专业的人来说, 向量只需要满足加法运算和数乘运算的的运算规律即可, 满足相加和数乘的基本运算规律的就可以视为向量.几何中向量使用起点位于源点的箭头来表示.
```
这表示向量的定义是抽象的,箭头,矩阵,函数,一切皆可以是向量.

![every_vector](/linkimage/matrix/every_vector.png)

(来自[抽象向量空间](https://www.bilibili.com/video/BV1ys411472E?p=15),可右键复制链接并粘帖到地址栏,直接点击无法打开)

只要满足这几条规律就行:

![rule_of_vector](/linkimage/matrix/rule_of_vector.png)

(来自[抽象向量空间](https://www.bilibili.com/video/BV1ys411472E?p=15),可右键复制链接并粘帖到地址栏,直接点击无法打开)
