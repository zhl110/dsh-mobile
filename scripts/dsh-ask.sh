#!/bin/bash
# dsh-ask.sh —— 在 chroot 里跑「命令行问一句」的壳。
# 为什么单独一个文件：dsh 0.2.1-rc.2 实测没有终端 UI，headless 是一次性任务模式
# （它自己的 cordis.patch.yml 写着 "one-shot task mode"、且 disabled: credentials/authorization），
# 所以这条只认 /root/.dsh-env 里的 DEEPSEEK_API_KEY，不认 Web 里登录的账号。
# 问题从 /tmp/dsh-task 读，不走命令行参数 —— 免得引号嵌套，也免得那句话进 shell history。
set -u
[ -f /root/.dsh-env ] && . /root/.dsh-env
[ -s /tmp/dsh-task ] || { echo "没东西可问：/tmp/dsh-task 是空的"; exit 1; }
q=$(cat /tmp/dsh-task)
echo "问: $q"
echo "---"
exec dsh --profile headless "$q"
