#!/bin/bash
# scripts/dsh-inode-and-pnpm-probe38.sh —— 两件小事，一发做完（都只读）：
#   ① 引擎那第 5 个 inotify 监视的 inode（0x1b4dc9 = 1789385）是哪个文件；
#   ② pnpm 这个可执行件是什么时候到这台机上的 —— 因为今早 App 插件页那两次操作死于 "spawn pnpm ENOENT"，
#      要分清"当时 pnpm 根本还没装"与"装了但那个进程 spawn 不到"，这两条结论完全不同。
set -u
export LANG=C
echo "== 1. 全盘找 inode 1789385（限 /root，maxdepth 5）"
find /root -maxdepth 5 -inum 1789385 -printf '  %p  mode=%a size=%s mtime=%TY-%Tm-%Td %TH:%TM:%TS\n' 2>/dev/null || echo "  没找到"
echo "  --- 对照：四个已认出来的（p36 的表）"
for f in /root/.dsh /root/.dsh/profiles/web /root/.dsh/profiles/web/package.json /root/.dsh/profiles/web/cordis.patch.yml; do
  printf '  ino=%s  %s\n' "$(stat -c %i "$f" 2>/dev/null)" "$f"
done

echo "== 2. pnpm / corepack / dsh 这几个可执行件各自的来路与时间"
for f in /usr/local/bin/pnpm /usr/local/bin/npx /usr/local/bin/corepack /usr/local/bin/dsh /usr/local/bin/npm; do
  printf '  %-24s ' "$f"
  if [ -L "$f" ]; then
    printf 'symlink → %s\n' "$(readlink "$f")"
  else
    printf 'file %s B mode=%a mtime=%s\n' "$(stat -c %s "$f")" "$(stat -c %a "$f")" "$(stat -c %y "$f" | cut -c1-19)"
  fi
done
echo "  --- pnpm 若是指向 corepack 的 shim，看 corepack 的缓存里有什么（只列名字与时间）"
for d in /root/.cache/node/corepack /usr/local/lib/node_modules/corepack; do
  printf '  %s ：' "$d"; [ -e "$d" ] && find "$d" -maxdepth 3 -printf '%TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null | sort | head -10 | tr '\n' ' ' && echo || echo "不存在"
done
echo
echo "  --- pnpm 版本与它自己的解析路径"
pnpm --version 2>&1 | head -1
head -3 /usr/local/bin/pnpm 2>/dev/null | tr -d '\0'
echo "  --- node 与 dsh 的件时间（对照用）"
stat -c '  %n  %s B  mtime=%y' /usr/local/bin/node /usr/local/lib/node_modules/@deepseek-ai/dsh/lib/bin.js 2>&1
echo "== 3. 今早那两次 ENOENT 的现场（把几条 operation 的时间与内容并排，判它是不是「pnpm 还没到机上」那一段）"
for d in /root/.dsh/profiles/web/.plugin-manager/logs/operation-*; do
  printf '  %s  mtime=%s\n' "$(basename "$d")" "$(stat -c %y "$d" | cut -c1-19)"
  for f in "$d"/*; do
    [ -f "$f" ] || continue
    printf '    %s (%s B)\n' "$(basename "$f")" "$(stat -c %s "$f")"
    head -c 400 "$f" | sed 's/^/      | /'
    echo
  done
done
echo "  完（只读）"
