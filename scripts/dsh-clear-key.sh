#!/system/bin/sh
# dsh-clear-key.sh —— 把存在 dsh 凭据库里的 DeepSeek API Key 清掉（回到"开始使用"那个弹窗状态）
# 为什么走文件而不是页面：UI 里 设置→模型→编辑 那个框的占位写的是"留空使用已保存凭据"，
# 清空再保存并不会删除已存的那条（实测），所以真要清得改盘上那份。
# 凭据库位置（chroot 内）：/root/.dsh/.credentials.yaml，0600，明文存 refs.DEEPSEEK_API_KEY。
# 用法：sh /data/local/sh/dsh-clear-key.sh
CTRL=/data/local/sh/dsh-chroot.sh
CREDS=/data/local/dsh-rootfs/root/.dsh/.credentials.yaml
BAK=/data/local/dsh-rootfs/root/credentials.yaml.cleared-$(date +%Y%m%d-%H%M%S)

[ "$(id -u)" = 0 ] || { echo "需要 root：先 su"; exit 1; }
[ -f "$CREDS" ] || { echo "凭据库不在位：$CREDS"; exit 1; }

echo "[..] 先停服务（不停的话它退出时会把内存里的旧凭据写回去）"
sh "$CTRL" --stop

echo "[..] 清掉之前先确认里面有没有 key 那一条"
if grep -q "^  DEEPSEEK_API_KEY:" "$CREDS"; then
  cp -p "$CREDS" "$BAK" && echo "     在，已整份备份到 chroot 内 /root/$(basename "$BAK")"
  grep -v -e '^  DEEPSEEK_API_KEY:' -e '^refs:$' "$CREDS" > "$CREDS.new" \
    && mv "$CREDS.new" "$CREDS" && chmod 600 "$CREDS" \
    && echo "[ok] 已删除 refs.DEEPSEEK_API_KEY 这一条"
else
  echo "     没有 DEEPSEEK_API_KEY 这条，什么都不用删"
fi

echo "--- 清完之后的键名（值一律不打印）---"
grep -oE '^[ ]*[A-Za-z_.-]+:' "$CREDS" | sed 's/^/  /'
echo "--- 是否还残留 key 字样：$(grep -c DEEPSEEK_API_KEY "$CREDS" 2>/dev/null || echo 0) 处"

echo "[..] 重新拉起服务"
sh "$CTRL" --web
