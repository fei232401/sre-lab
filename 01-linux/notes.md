# Linux 学习笔记 - Day 1

## 1. Linux 文件系统结构

Linux 使用单一根目录 `/` 作为所有文件的起点。

常见目录：
- /home：用户目录
- /etc：系统配置文件
- /var：日志与变化数据
- /usr：软件与程序
- /tmp：临时文件

---

## 2. 绝对路径 vs 相对路径

- 绝对路径：从 / 开始
  例：/home/fei/sre-lab

- 相对路径：基于当前目录
  例：./lab 或 ../etc

---

## 3. 文件操作基础

### 创建
- mkdir：创建目录
- touch：创建空文件

### 写入
- echo "内容" > file（覆盖）
- echo "内容" >> file（追加）

### 读取
- cat file：查看文件内容

---

## 4. Git 基础操作

- git status：查看状态
- git add：加入暂存区
- git commit：提交快照

---

## 5. 今日关键理解

- Linux 命令成功通常“无输出”
- 文件为空时 cat 不显示内容
- ~ 等价于 /home/用户
- Git commit 是学习里程碑

---

## 6. 学习目标

从“会敲命令” → “理解系统结构”