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