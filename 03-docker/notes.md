Docker Phase 1：Container、Network、Volume

学习目标

理解 Docker 不只是运行容器，而是理解：

Container + Network + Volume

三者共同组成一个可运行的应用环境。

---

Part 1 Container 与 Process

核心认知

容器本质上不是虚拟机。

容器本质：

受隔离控制的Linux进程

Docker负责：

- Namespace隔离
- 文件系统隔离
- 网络隔离
- 资源限制

应用最终仍然以进程形式运行在宿主机内核上。

---

实验验证

启动Nginx：

docker run -d --name nginx-test nginx

查看容器进程：

docker top nginx-test

查看宿主机进程：

ps aux | grep nginx

查看容器PID：

docker inspect nginx-test | grep Pid

发现：

docker top中的PID
=
宿主机中的PID

证明：

容器进程
实际上就是宿主机进程

只是被Docker进行了隔离。

---

我的错误理解

最开始认为：

容器是独立于宿主机存在的特殊实体

后来理解：

容器本质仍然是宿主机进程

Docker只是提供隔离环境。

类似：

动物园中的老虎
仍然是老虎
只是生活在隔离区域

---

Part 2 Network 与 Docker DNS

核心认知

Compose启动后：

每个服务
=
一个DNS记录

例如：

services:
  redis:

自动产生：

redis

DNS名称。

---

API代码：

redis.Redis(host="redis")

这里：

redis

不是IP。

而是Docker DNS解析结果。

---

网络关系

Browser
    ↓
Nginx
    ↓
API
    ↓
Redis / MySQL

请求逐层转发。

---

我的错误理解

开始时认为：

Redis能通信
只是因为Compose知道它的位置

后面修正为：

Docker Network
+
Docker DNS
共同完成服务发现

---

排障经验

当服务访问失败时：

优先检查：

docker compose ps
docker compose logs
docker network ls
docker inspect

而不是直接重建容器。

---

Part 3 Volume

核心认知

容器负责运行。

Volume负责存储。

Container
=
计算层

Volume
=
数据层

---

无Volume实验

Compose：

services:
  mysql:
    image: mysql:8

创建：

CREATE DATABASE srelab;

虽然数据存在。

但是：

docker compose down
docker compose up -d

后数据消失。

原因：

数据保存在容器可写层

容器删除后一起消失。

---

添加Volume

Compose：

services:
  mysql:
    volumes:
      - mysql_data:/var/lib/mysql

volumes:
  mysql_data:

此时：

docker compose down
docker compose up -d

数据仍然保留。

---

down 与 down -v

普通：

docker compose down

删除：

容器
网络

保留：

Volume

---

危险操作：

docker compose down -v

删除：

容器
网络
Volume

结果：

数据库数据全部丢失

---

我的错误理解

开始认为：

容器停止导致数据丢失

后来理解：

数据丢失原因是容器可写层被删除

而不是MySQL停止。

---

本阶段排障模型

以后遇到Docker问题：

1 配置是否正确
2 容器是否启动
3 端口是否监听
4 日志是否报错
5 网络是否可达
6 DNS是否正确
7 数据是否持久化

流程：

观察现象
↓
收集证据
↓
缩小范围
↓
验证假设
↓
记录结论

不要：

删除容器
重建容器
祈祷恢复

---


Lab04 总结

实验目标

使用 Dockerfile 构建自定义 Nginx 镜像，并返回自定义网页内容。


---

文件结构

labs04-dockerfile/
├── Dockerfile
└── index.html


---

Dockerfile

FROM nginx

COPY index.html /usr/share/nginx/html/index.html


---

构建镜像

docker build -t fei-nginx:v1 .

注意：

.

表示：

Build Context（构建上下文）

Docker 会把当前目录发送给 Docker Engine。


---

启动容器

docker run -d \
--name fei-web \
-p 8080:80 \
fei-nginx:v1


---

验证

curl localhost:8080

成功返回自定义网页内容。


---

本实验掌握

FROM

指定基础镜像

FROM nginx


---

COPY

复制宿主机文件到镜像内部

COPY index.html /usr/share/nginx/html/index.html

注意：

目标路径是：

镜像内部路径

不是宿主机路径。


---

docker build

作用：

Dockerfile
    ↓
Image


---

docker run

作用：

Image
    ↓
Container


---

本实验犯过的错误

错误1

docker build -t fei-nginx:v1

报错：

requires 1 argument

原因：

未指定 Build Context。

正确：

docker build -t fei-nginx:v1 .


---

错误2

错误理解 COPY

曾写：

COPY index.html /~/sre-lab/...

问题：

Dockerfile 操作的是：

镜像内部文件系统

不是宿主机目录。


---

错误3

混淆 Python Dockerfile 与 Nginx Dockerfile

曾写：

RUN pip install ...
COPY app.py .
CMD ["nginx","app.py"]

问题：

当前镜像目标是：

Nginx返回静态网页

不涉及 Python 应用。

# Docker / Compose 阶段总结（05–06）

## 1. 学习目标

本阶段从 Docker 镜像构建（Dockerfile）过渡到多容器系统（Compose + Stack），目标是理解：

- 容器如何组成完整系统
- 服务之间如何通信
- 微服务基础架构结构
- SRE视角下的排障方法

---

## 2. 05 Dockerfile 阶段

### 2.1 核心内容

- FROM / COPY / RUN / CMD 基础
- 镜像构建流程
- nginx镜像定制

### 2.2 实践结果

成功构建自定义 nginx 镜像并部署静态页面

```bash
docker build -t fei-nginx:v1 .
docker run -p 8080:80 fei-nginx:v1

2.3 常见错误

build 参数缺失（忘记 .）

COPY 路径错误

CMD 使用错误


2.4 经验总结

Dockerfile 是“构建环境”，不是运行环境

路径是构建上下文决定的



---

3. 06 Compose / Stack 阶段

3.1 架构理解

系统由以下组件构成：

Nginx（入口）

API（业务逻辑）

Redis（缓存）

MySQL（数据存储）


形成完整链路：

用户 → Nginx → API → Redis/MySQL


---

3.2 核心能力

docker compose 启动多服务

service DNS 通信

container network 自动管理

volume 数据持久化（部分实验）



---

3.3 实际问题与错误

1. YAML 缩进错误

service 结构写错

ports 拼写错误（prots）


2. API 运行错误

Python 语法错误导致容器退出


3. 端口冲突

host port 已被占用（80/8080）


4. nginx 未配置反向代理

访问 redis/mysql 返回 404



---

3.4 排障方法

标准 SRE 排障流程：

1. docker compose ps


2. docker logs <container>


3. curl / health check


4. ss -tlnp 检查端口


5. docker network inspect




---

3.5 核心经验

“Up” ≠ 正常运行

容器只是进程，不等于服务可用

DNS（service name）是容器通信关键

大部分问题来自 YAML / 应用，而不是 Docker 本身



---

4. 关键成长

本阶段完成：

从单容器 → 多服务系统

从运行 → 联调

从 docker 命令 → 系统思维
=============Docker 生产级编排（07-10 阶段）====================
一、 核心技术骨架与知识网络
从单机容器到工业级集群，整个 07-10 阶段的核心在于建立可观测性（Observability）、特权最小化安全控制与自我修复能力。
1. 技术栈知识图谱
·	阶段：07-Network
o	核心技术点：双网络隔离架构
o	它的底层 Linux 内核机制/物理本质：Linux Bridge（虚拟网桥）+ Veth Pair（虚拟网线）
o	生产设计终极目的：东西向流量隔离：前端（Nginx）无法直接访问和连接核心数据库（DB），实现最小特权安全。
·	阶段：08-Security
o	核心技术点：Deploy 资源硬红线
o	它的底层 Linux 内核机制/物理本质：Linux Cgroups（控制组）
o	生产设计终极目的：防御性运维：限制单个容器的 CPU 和内存，防止因开发代码问题（如死循环或内存泄漏）拖垮整台物理服务器。
·	阶段：09-Production
o	核心技术点：Healthcheck 状态探针
o	它的底层 Linux 内核机制/物理本质：定时在容器内执行指定测试指令（如 curl 或 admin-ping）
o	生产设计终极目的：从进程级依赖升级为健康度依赖：解决“容器进程已启动，但内部微服务尚未初始化完成”的启动时序问题。
·	阶段：10-Final
o	核心技术点：环境变量与数据锚定
o	它的底层 Linux 内核机制/物理本质：Host-Volume 映射 + .env 隔离
o	生产设计终极目的：前后端信息差解耦：密码等敏感信息不硬编码进代码；通过 Volume 保证容器停止后数据不丢失。
二、 那些年踩过的钢丝：经典问题场景与排障口诀
这些问题是你在实践过程中积累的宝贵经验，也是区分“基础运维”和“顶级 SRE”的关键所在。
❌ 坑一：文件与目录类型混淆（Not a directory 报错）
·	现象：执行 cd labs09-Production命令时提示“Not a directory”，或 Docker 报错“Are you trying to mount a directory onto a file (or vice-versa)?”。
·	根源：
1.	使用 nano、vim、echo 等文本工具时，因操作疏忽将应创建为文件夹的路径误设为文件名，导致创建了同名的普通文本文件，从而无法进入该目录。
2.	在 YAML 文件中定义了挂载文件（如 nginx/default.conf），但宿主机上该文件不存在。Docker 的默认机制会在宿主机上自动创建一个同名文件夹，导致文件类型不匹配，容器启动后立即退出。
·	SRE 避坑铁律：启动 Docker 前，需确保宿主机的所有配置文件已存在，且必须通过 touch 命令明确其为文件类型。 排查时使用 ls -l（或 ll）命令查看文件最左侧第一个字母，“d”表示目录，“-”表示文件。
❌ 坑二：高级变量冲突幽灵（invalid variable name 报错）
·	现象：Nginx 容器启动后立即退出（Exited (1)），日志中频繁出现“invalid variable name in nginx.conf”错误。
·	根源：Nginx 官方镜像内部集成了用于自动替换环境变量的脚本（envsubst）。当在外层配置了 .env 文件，同时在 default.conf 中使用了 Nginx 自身的变量（如 $host、$remote_addr）时，Docker 脚本会误认为这些是需要替换的 Docker 变量。由于在环境变量中找不到对应的值，脚本会将 Nginx 的专属变量替换为空字符串，导致配置文件被破坏。
·	SRE 避坑铁律：“避免冲突，隔离处理”。
o	实验阶段：可直接删除 default.conf 中带有 $ 符号的非核心透传参数，仅保留最基础的 proxy_pass 配置。
o	工业阶段：在 YAML 的 Nginx 服务配置中注入 NGINX_ENVSUBST_FILTER=NONE，禁用 Docker 对 Nginx 配置文件的自动替换行为。
❌ 坑三：数据库初始化缺失（Unknown database 与密码为空导致启动失败）
·	现象：
1.	容器运行后，MySQL 状态显示为 Exited (1)，提示密码未设置。
2.	所有容器均启动成功（Up 状态），但通过 curl 访问时，前端或 API 报错“Unknown database 'srelab'”。
·	根源：
1.	从其他目录复制 compose.yaml 文件时，遗漏了隐藏的 .env 文件（包含密码配置），导致 MySQL 读取到空密码而启动失败。
2.	仅设置了管理员密码（MYSQL_ROOT_PASSWORD），但未指定初始化数据库。MySQL 中未创建对应的业务数据库，导致 Python API 访问时提示数据库不存在。
·	SRE 避坑铁律：在 YAML 文件的 mysql 环境变量配置中追加 MYSQL_DATABASE: 业务库名。若因数据损坏导致容器状态为 unhealthy，需执行 docker compose down -v 命令删除受损的数据卷，使 MySQL 重新初始化。
三、 SRE 职业心法与兵器库
通过本次实践，你需要彻底告别过去“盲目猜测”的习惯。未来在生产环境中，面对终端的黑底白字，记住以下高效的排查流程：
1. 终极排障兵器谱
·	第一步（查看状态）：docker compose ps -a。
不盲目猜测，首先查看哪个容器状态异常，记录其退出码（如 137 表示因内存溢出被内核终止，1 表示程序或配置错误）。
·	第二步（查看资源）：docker stats。
实时监控容器的资源使用情况，关注 CPU 和内存是否接近在 deploy.resources.limits 中设定的上限。
·	第三步（查看日志）：docker compose logs -f --tail=50 <服务名>。
日志是系统运行状态的真实反映。通过查看报错堆栈的最后一行，定位问题的根本原因。
·	第四步（检查宿主机端口）：ss -tlnp | grep <端口号>。
用于排查连接拒绝（Connection Refused）问题。ss -tlnp命令比传统的 netstat 更高效，能快速查看端口占用情况。
2. 顶级 SRE 的心法认知
“即使不了解 API 内部每一行 Python 代码的实现，也不清楚 SQL 的复杂联查逻辑，但依然能对系统状态感到踏实。”
·	广度即深度：SRE 的价值和高薪，并非源于编写优雅的业务代码，而是在于具备保障系统高可用、高并发、安全隔离及自我修复的全局掌控能力。
·	主动防御大于被动救火：在 09/10 阶段编写的 YAML 配置，之所以无需像以前那样频繁通过 exec 进入容器手动执行 ping、测试 DNS 和 TCP 连接，是因为通过 healthcheck 建立了自动化的健康检查机制。只要 docker compose ps显示所有服务均为 healthy 状态，即表示 Docker 已完成相关测试。
·	不依赖背诵，注重模板复用：工业界的工程师并非都能凭空编写 YAML 配置。保存好你在 10-Final 阶段优化完善的**“黄金模板（Golden Template）”**，未来新项目上线时，直接复制模板并修改少量参数，即可在 5 分钟内搭建起一个工业级、高可用的微服务集群。









