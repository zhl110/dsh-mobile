# ~/.dsh-hook.sh —— 打开 Termux 就进 DeepSeek Harness 控制台。
# 上一版把判断写在 ~/.bashrc 里、指向 /data/local/sh/dsh-console.sh，实测**静默失效**了：
# app 上下文（你这台是 untrusted_app_27，c87,c257,c512,c768）读 /data/local/sh 是
# `runcon ... ls /data/local/sh` → Permission denied（SELinux），所以 `[ -f /data/local/sh/... ]` 永远不成立。
# 这一版把脚本本体放进 Termux 自己的 home，root 侧再按绝对路径读它。
# 想临时跳过：开 Termux 前先 export NO_DSH_CONSOLE=1；想彻底退掉：删 ~/.bashrc 与 ~/.bash_profile 里那两行。
if [ -z "$DSH_CONSOLE_DONE" ] && [ -z "$NO_DSH_CONSOLE" ] && [ -f "$HOME/dsh-console.sh" ]; then
  if [ "$(id -u)" = 0 ]; then
    DSH_CONSOLE_DONE=1 sh "$HOME/dsh-console.sh"
  elif su -c "DSH_CONSOLE_DONE=1 sh $HOME/dsh-console.sh"; then
    :
  else
    echo "[dsh] 拿不到 root：SU Manager → 超级用户 → 右上角 + → 勾上 Terminal，再重开 Termux"
  fi
fi
