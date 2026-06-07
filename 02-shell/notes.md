# Shell Learning Phase 1 Summary

## 1. Shell本质
Shell不是命令集合，而是：
→ 操作系统的“自动化控制语言”

---

## 2. 基础命令
- cd / ls / pwd
- cat / echo
- > / >> 输出重定向

---

## 3. 管道思想（核心）
| 用于组合多个命令

示例：
cat file | grep "error"

---

## 4. 脚本基础
### if结构
### for循环
### bash执行

核心理解：
→ Shell脚本 = 自动化任务执行器

---

## 5. 进程模型
- & 后台运行
- jobs / kill
- ps

核心：
Linux所有运行都是进程

---

## 6. 权限模型
- chmod +x
- sudo / root
- rwx模型

核心：
权限 = 系统安全边界

---

## 7. systemd
- systemctl start/stop/status
- service管理

核心：
服务 = 长期运行进程 + systemd

---

## 8. 网络基础
- curl localhost
- ss -tulnp
- 127.0.0.1 vs localhost

核心：
服务可用 = 进程 + 端口 + 网络

---

## 9. 日志系统
- journalctl
- /var/log/nginx
- logrotate

核心：
SRE排障 = 日志驱动

---

## Phase 1总结
Shell Phase 1 = Linux基础 + 服务控制 + 排障认知建立完成

# 🚀 Shell Phase 2–3 Notes (SRE Automation Core)

---

# =========================
# 📌 Phase 2：文本处理
# =========================

## 1. grep（过滤）

```bash
grep "error" file.log
grep -c "500" access.log
作用：
查找匹配行
过滤日志
统计出现次数
2. awk（按列处理）
Bash
awk '{print $1}' file.log
awk '{print $2}' file.log
作用：
提取字段（IP / user / status）
结构化日志分析
3. sed（文本修改）
Bash
sed 's/80/8080/' file.txt
sed -i 's/old/new/' file.txt
作用：
替换内容
修改配置文件
删除行
⚠️ 常见错误总结
❌ 1. grep 卡住
原因：
没有文件输入
等待 stdin
解决：
Bash
grep pattern file.log
❌ 2. 变量写错
Bash
service = "ssh"   ❌
service="ssh"     ✔
❌ 3. 参数缺失
Bash
bash script.sh
解决：
Bash
if [ -z "$1" ]; then
  echo "missing argument"
fi
=========================
📌 Phase 3：Shell自动化
=========================
1. if 判断
Bash
if [ $? -eq 0 ]; then
  echo "OK"
else
  echo "FAIL"
fi
2. for 循环
Bash
for service in ssh nginx mysql
do
  echo $service
done
3. 脚本参数
Bash
$1   # 第一个参数
$@   # 所有参数
4. 命令替换
Bash
result=$(grep error file.log)
5. SRE脚本模型
Plain text
输入 → 处理 → 输出
=========================
📌 SRE核心能力总结
=========================
✔ grep → 过滤日志
✔ awk → 提取字段
✔ sed → 修改内容
✔ for → 批量处理
✔ if → 条件判断
✔ shell → 自动化工具
=========================
📌 SRE核心认知升级
=========================
从：
手动执行命令 ❌
→
自动化处理系统 ✔
Shell Phase 4 - 日志分析与故障排查
===================
   PHASE 4
===================
学习目标

从“会写Shell脚本”提升到“能够利用Shell分析系统和定位故障”。

---

Phase 4.1 日志分析基础

grep统计错误数量

统计日志中的500错误：

grep -c "500" access.log

含义：

- grep：查找内容
- -c：统计匹配次数

---

awk按列提取字段

示例日志：

127.0.0.1 GET /login 200

字段含义：

字段| 内容
$1| IP
$2| Method
$3| URL
$4| Status

示例：

awk '{print $1}'

输出IP。

awk '{print $3}'

输出URL。

awk '{print $4}'

输出状态码。

---

Phase 4.2 日志统计组合拳

TOP IP

awk '{print $1}' access.log | sort | uniq -c | sort -nr

作用：

统计访问次数最多的IP。

---

TOP URL

awk '{print $3}' access.log | sort | uniq -c | sort -nr

作用：

统计访问量最高的URL。

---

状态码统计

awk '{print $4}' access.log | sort | uniq -c

作用：

统计200、404、500等状态码数量。

---

Phase 4.3 综合日志分析脚本

access_report.sh

功能：

- 统计错误数量
- 统计TOP IP
- 统计TOP URL
- 统计状态码

核心知识：

参数传递

log=$1

代表接收脚本参数。

---

参数校验

if [ -z "$log" ]; then
    echo "Usage: ..."
    exit 1
fi

作用：

防止用户忘记输入日志文件。

---

chmod执行权限

赋予脚本执行权限：

chmod +x access_report.sh

执行：

./access_report.sh access.log

---

Phase 4.4 故障排查思维

学习重点：

不是命令本身，而是排障顺序。

---

场景1

用户反馈：

Connection Refused

正确思路：

服务层优先
↓
systemctl status nginx
↓
ss -tlnp
↓
journalctl

原因：

Connection Refused通常表示：

服务器可达，但端口无人监听。

---

场景2

Nginx启动失败

日志：

Address already in use

含义：

80端口被占用。

排查：

ss -tlnp | grep :80

或者：

sudo lsof -i :80

找出占用端口的进程。

---

场景3

Nginx正常运行

80端口正常监听

但用户仍无法访问

排查顺序：

curl localhost
↓
确认本机访问是否正常
↓
检查应用返回结果
↓
检查防火墙
↓
检查网络

---

本阶段踩过的坑

1. if语句空格错误

错误：

if [-z "$log" ]; then

正确：

if [ -z "$log" ]; then

原因：

[ 是命令，必须有空格。

---

2. grep把变量写成字符串

错误：

grep -c "500" log

正确：

grep -c "500" "$log"

区别：

- log：文件名
- $log：变量值

---

3. 日志尾部空行

现象：

2
3 200
2 500

原因：

日志存在空行。

解决：

删除空行。

或者：

awk 'NF {print $4}'

过滤空行。

---

4. Git忽略日志文件

现象：

git add access.log

失败。

排查：

git check-ignore -v access.log

发现：

*.log

被.gitignore忽略。

解决：

将教学日志改名：

demo_access.txt

---

5. VS Code找不到文件

原因：

打开了错误目录。

经验：

先确认：

pwd

再确认：

tree -L 2

不要第一时间怀疑文件丢失。

---

6. 虚拟机卡死

现象：

SSH断开。

VS Code无法连接。

最终原因：

VirtualBox虚拟机异常。

经验：

先确认：

- 虚拟机是否运行
- SSH服务是否运行
- 是否真的属于Git问题

不要看到现象就直接下结论。

---

本阶段最重要收获

SRE排障核心思路：

现象
↓
定位层级
↓
缩小范围
↓
验证猜想
↓
找到根因
↓
修复问题

不要直接重启。

不要直接猜测。

先观察，再验证。