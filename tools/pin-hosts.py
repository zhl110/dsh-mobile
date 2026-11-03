#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""pin-hosts.py — 给手机上的 Ubuntu chroot 续命 DNS。

为什么要这个脚本：本机实测（一加 13 / Android 15 / KernelSU，2026-10-19）53 端口的 UDP 和 TCP
出站都被拦，chroot 里那份 /etc/resolv.conf 根本问不到答案——apt、npm、api.deepseek.com 全是
靠 /etc/hosts 里钉死的 IP 才通的。IP 会漂，漂了就断，所以刷新这一步必须能一条命令重复跑。

做法：PC 侧用 DoH（HTTPS/443，实测通）解析域名表 → 只替换 /etc/hosts 里
`# >>> dsh-mobile pin-hosts >>>` 到 `# <<< dsh-mobile pin-hosts <<<` 这一段 → 表外的行原样留着
（localhost 那些一条不动）。表内的域名在段外出现过的旧行会被清掉，免得两条互相抢先。

用法：
    python tools/pin-hosts.py                      # 用默认 adb 路径与默认域名表
    python tools/pin-hosts.py --domains a.com b.com
    python tools/pin-hosts.py --dry-run            # 只打印要写什么，不落盘
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request

BEGIN = "# >>> dsh-mobile pin-hosts >>> (脚本维护，手改会被覆盖)"
END = "# <<< dsh-mobile pin-hosts <<<"

# 默认表就是这轮实测出来的：模型调用 + 账号登录 + 装东西的镜像 + apt 源。
# platform.deepseek.com 是 2026-10-19 补进来的：账号包 lib/types/index.d.ts 写着
# "Platform origin serving auth-api and browser pages"，protocol.js 拼的是
# `${origin}/auth-api/v0/dsh/${method}`，而这个域名在 chroot 里 getent 为空、curl exit=6（解析不到），
# /data/local/dsh.log 里的 sign-in failed errorCode:'no-response' 就是它——不钉这个域名，Web UI 里登录不回来。
# 故意不含 dsh-otel-collector.deepseeksvc.com——它不钉就解析不到，遥测自然发不出去（实测 rx 增量为 0）。
DEFAULT_DOMAINS = [
    "api.deepseek.com",
    "platform.deepseek.com",
    "registry.npmmirror.com",
    "cdn.npmmirror.com",
    "mirrors.tuna.tsinghua.edu.cn",
]

DOH_SERVERS = [
    "https://dns.alidns.com/resolve",
    "https://dns.google/resolve",
]

# Ubuntu base 自带这几行，本轮之前我拿 pins 整份覆盖过 /etc/hosts，把它们弄丢了
# （实测 getent hosts localhost 空）。这个工具从此负责兜住：缺了就补，在位就不动。
CANONICAL = [
    "127.0.0.1\tlocalhost",
    "::1\tlocalhost ip6-localhost ip6-loopback",
]

# adb 找法：DSH_ADB → PATH 里的 adb → 本仓约定那发（原来写死的是作者本机带用户名的路径，2026-11-03 移除）
DEFAULT_ADB = os.environ.get("DSH_ADB") or shutil.which("adb") or r"D:\mycode\.agent-tools\platform-tools\adb.exe"
HOSTS = "/data/local/dsh-rootfs/etc/hosts"
TMP_ON_DEVICE = "/data/local/tmp/hosts.dsh-mobile"


def doh_resolve(domain, servers, timeout=8):
    """问 DoH 要 A 记录；返回 IP 列表（可能多个，全留下）。"""
    last_err = None
    for base in servers:
        url = "%s?name=%s&type=1" % (base, domain)
        req = urllib.request.Request(url, headers={"Accept": "application/dns-json"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                data = json.loads(r.read().decode("utf-8"))
        except Exception as e:  # 换下一个 DoH
            last_err = e
            continue
        answers = [a["data"] for a in data.get("Answer", []) if a.get("type") == 1]
        if answers:
            return answers, base
    return [], "err=%s" % (last_err or "no-server")


def adb_shell(adb, cmd):
    """adb 会把 argv 用空格拼成一行发给设备 shell，所以 su -c 的引号必须我自己加，
    否则设备端只把 cmd 的第一个词当命令（本轮就踩过：这样跑出来的"无输出"是假的）。"""
    wrapped = "su -c '%s'" % cmd.replace("'", "'\\''")
    p = subprocess.run([adb, "shell", wrapped], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return p.stdout.replace("\r\n", "\n")


def adb_read(adb, path):
    """exec-out 拿字节，不经过 shell 的 CRLF 转换。"""
    p = subprocess.run([adb, "exec-out", "su", "-c", "cat %s" % path], capture_output=True)
    if p.returncode != 0:
        raise SystemExit("!! 读 %s 失败：%s" % (path, p.stderr.decode("utf-8", "replace").strip()))
    return p.stdout.decode("utf-8", "replace")


def adb_push(adb, local, remote):
    p = subprocess.run([adb, "push", local, remote], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    if p.returncode != 0:
        raise SystemExit("!! push 失败：%s" % (p.stdout + p.stderr))
    return (p.stdout + p.stderr).strip().splitlines()[-1]


def split_managed(text):
    """把 /etc/hosts 拆成（段外内容, 段内旧内容）。没有标记就整份算段外。"""
    if BEGIN in text and END in text:
        pre, rest = text.split(BEGIN, 1)
        old, post = rest.split(END, 1)
        return pre + post, old.lstrip("\n")
    return text, ""


def main():
    ap = argparse.ArgumentParser(description="刷新 chroot 里的 /etc/hosts 钉 IP 段")
    ap.add_argument("--adb", default=DEFAULT_ADB)
    ap.add_argument("--domains", nargs="*", default=DEFAULT_DOMAINS)
    ap.add_argument("--dry-run", action="store_true", help="只打印，不写盘")
    args = ap.parse_args()

    adb = args.adb
    if not os.path.exists(adb):
        raise SystemExit("!! 找不到 adb：%s（用 --adb 指一下）" % adb)
    print("连着的是：%s" % adb_shell(adb, "getprop ro.product.model").strip())
    lines_out, failed = [], []
    for d in args.domains:
        ips, src = doh_resolve(d, DOH_SERVERS)
        if not ips:
            failed.append(d)
            print("  [失败] %-32s %s" % (d, src))
            continue
        for ip in ips:
            lines_out.append("%s\t%s" % (ip, d))
        print("  [ok]   %-32s %s  <- %s" % (d, ",".join(ips), src))

    if not lines_out:
        raise SystemExit("!! 一个域名都没解析到，不改动盘上的 hosts")

    original = adb_read(adb, HOSTS)
    outside, old_block = split_managed(original)
    # 段外若有我们表内域名的旧行（比如本轮之前手工 append 的那批），一并清掉
    keep = []
    for line in outside.splitlines():
        m = re.match(r"^\s*(\S+)\s+(\S+)\s*$", line)
        if m and m.group(2) in args.domains and not line.strip().startswith("#"):
            continue
        keep.append(line)
    body = "\n".join(keep).strip("\n")
    # 兜住 Ubuntu base 那几行 localhost：实测本轮之前它们被我覆盖丢了，getent hosts localhost 是空的
    missing = [c for c in CANONICAL if c not in keep]
    if missing:
        body = "\n".join(missing) + "\n\n" + body
        print("\n补回 base 自带的规范行：%s" % " / ".join(missing))
    new_block = "\n".join(lines_out)
    stamp = "# 生成时间 %s；53 端口被拦，这里靠 PC 侧 DoH 拿答案" % __import__("datetime").datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    merged = body + "\n\n" + BEGIN + "\n" + stamp + "\n" + new_block + "\n" + END + "\n"

    print("\n--- 段内旧内容（%d 行）将被替换：" % len([l for l in old_block.splitlines() if l.strip()]))
    for l in old_block.splitlines():
        if l.strip():
            print("    " + l)
    print("--- 新段：")
    for l in (BEGIN + "\n" + stamp + "\n" + new_block + "\n" + END).splitlines():
        print("    " + l)
    if failed:
        print("!! 这几个没解析到，本轮不动它们的旧行（如果段外有的话会被清掉，注意）：%s" % ", ".join(failed))

    if args.dry_run:
        print("\n--dry-run：没写盘")
        return

    local_tmp = os.path.join(os.environ.get("TEMP", "."), "hosts.dsh-mobile")
    with open(local_tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(merged)
    print("\npush ->", adb_push(adb, local_tmp, TMP_ON_DEVICE))
    before = len(original.encode("utf-8"))
    after = len(merged.encode("utf-8"))
    out = adb_shell(adb, "cp %s %s && chmod 0644 %s && rm %s && ls -l %s" % (
        TMP_ON_DEVICE, HOSTS, HOSTS, TMP_ON_DEVICE, HOSTS))
    now = adb_shell(adb, "wc -c < %s" % HOSTS).strip()
    print("写盘读数：原 %d B -> 现 %s B（本地 %d B，%s）" % (
        before, now or "?", after, "字节相等" if str(after) == str(now) else "对不上，检查换行符"))
    print(out.strip())

    # 写完当场验两件事：base 那几行回来了没、真域名打不打得通（401 = 通但没带 key，符合预期）
    check = adb_shell(adb,
        "chroot /data/local/dsh-rootfs /usr/bin/env TMPDIR=/tmp "
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin "
        "/bin/bash -lc \"getent hosts localhost >/dev/null && echo 'localhost 解析=有' || echo 'localhost 解析=没有'; "
        "curl -sS -o /dev/null -w 'api.deepseek.com HTTP=%{http_code}\\n' --max-time 15 https://api.deepseek.com/\"")
    print("chroot 内实测：\n" + (check.strip() or "无输出"))


if __name__ == "__main__":
    main()
