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











