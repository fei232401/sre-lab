# SRE-Lab - Linux Day 1 完整笔记

---

# 1. Linux 系统结构认知

Linux 使用单一根目录 `/`，所有资源都挂载在其下。

## 核心目录

- /home：普通用户目录（类似 Windows C:\Users）
- /etc：系统配置文件（nginx/mysql/ssh配置）
- /var：日志、缓存、动态数据
- /usr：软件安装目录
- /tmp：临时文件
- /bin：基础命令
- /proc：进程与内核信息（虚拟文件系统）

---

# 2. 路径体系（非常重要）

## 绝对路径
从 `/` 开始：

/home/fei/sre-lab

## 相对路径
基于当前目录：

./lab
../etc

## 特殊符号

- .  当前目录
- .. 上级目录
- ~  用户 home（/home/fei）

---

# 3. 文件与目录操作

## 创建

mkdir -p dir/subdir
touch file.txt

## 查看结构

ls
ls -l
tree（需安装）

## 删除

rm file
rm -r dir
rm -rf dir（危险操作）

---

# 4. 文件内容操作（核心）

## 写入

echo "text" > file      # 覆盖写入
echo "text" >> file     # 追加写入

## 查看

cat file                # 直接输出
less file               # 分页查看

---

# 5. Linux 命令特性（非常重要）

- 成功时通常“无输出”
- 空文件 cat 不显示内容
- 错误才会提示
- 命令 = 工具，不是程序界面

---

# 6. Git 基础（学习系统核心）

## 初始化流程

git init
git add .
git commit -m "message"

## 状态理解

- Untracked：未跟踪
- Staged：暂存区
- Committed：已提交

## commit 本质

一次“学习快照”

---

# 7. 本阶段已用工具

## 命令行工具

- cat：查看文件
- echo：写入内容
- mkdir：创建目录
- touch：创建文件
- ls：查看结构
- cd：切换目录

## 进阶工具（已提及但未深入）

- vim：终端编辑器（复杂但强大）
- nano：简易编辑器
- tree：目录结构可视化

---

# 8. vim / nano / tree 简述

## vim
- 强大但学习曲线陡
- 模式化编辑器（insert/normal）
- 运维必备

## nano
- 简单易用
- 适合新手

## tree
- 目录结构可视化工具
- 用于快速理解项目结构

---

# 9. 当前学习逻辑（很关键）

学习不是记命令，而是建立系统认知：

输入命令 → 观察结果 → 理解结构 → 形成模型

---

# 10. 当前阶段总结

你已经完成：

- Linux 文件系统入门
- 文件操作基础
- Git 初始化与提交
- IO（输入输出重定向）
- 初步 Shell 使用

---

# 11. 下一阶段目标

进入：

## Shell 编程基础

- 变量
- if判断
- for循环
- 管道 |
- 重定向深化

并开始理解：

> Linux 如何“像编程语言一样运行”