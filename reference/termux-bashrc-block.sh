# >>> dsh-console >>>（2026-10-20：判断逻辑挪进 ~/.dsh-hook.sh，那文件为什么必须待在 Termux 自己的 home 里，它头上有实测原因）
[ -f "$HOME/.dsh-hook.sh" ] && . "$HOME/.dsh-hook.sh"
# <<< dsh-console <<<
