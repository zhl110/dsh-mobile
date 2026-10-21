#!/usr/bin/env bash
# dsh-market-route-probe48.sh —— 只读两件事：① 把「市场页拿 502」这条路由端到端真打一发（口令从文件读、不进 argv、不打印），
# 看修完之后它到底回不回 200、回多大；② 把《手机端情况.md》B 类剩下的批次量出"要装几个包、下多少 MB"，好让他挑（铁律 7：没点头的一个不装）。
#
# 为什么这一发值得用一次真请求：14.28 那格我写的最后一句是"欠他一眼"，而插件源码给了一条更硬的判据 ——
# 前端拿到非 2xx 会显示报错文案 + 重试按钮，只有"请求还没回来"才一直转圈（dshmarket src/client/MarketSection.tsx:2678/2698 与 :6437-6446）。
# 所以"屏幕上还是转圈"与"屏幕上写着错"这两件事，在路由层面是两种不同的失败；我们自己打一发就能分清是哪一种，
# 不用每次等他点开。代价：这一发会真的去取一次目录（网络 + 插件自己那份缓存与日志会长），不改任何设置、不点「应用」。
set -u
M=/root/.dsh/profiles/web/.dsh-market
TS=$(date -u +%H%M%S)

echo "== 0. 时刻"
echo "  UTC  $(date -u '+%F %T')   北京 $(TZ=Asia/Shanghai date '+%F %T' 2>/dev/null)"

echo "== 1. 上一发安装里那个【1 upgraded】复点（名字集合不变，所以差集数不出来，只能看版本）"
dpkg -l perl-base 2>/dev/null | awk '$1=="ii"{printf "  perl-base 现在 = %s（计划里是 5.38.2-3.2ubuntu0.4 → 5.38.2-3.2ubuntu0.6）\n", $3}'
echo "  git / python3 在位复点：$(git --version 2>&1) / $(python3 -V 2>&1)"

echo "== 2. 市场那条路由端到端（GET :3081/dsh-market/registry，带我们自己那份入口口令）"
echo "  发请求之前：log.ndjson = $(stat -c %s $M/log.ndjson 2>/dev/null) B / $(wc -l < $M/log.ndjson 2>/dev/null) 行，改于 $(stat -c %y $M/log.ndjson 2>/dev/null | cut -d. -f1)"
cat > /tmp/p48route-$TS.js <<'JS'
// 口令只从文件读进内存，不进 argv、不打印、不写日志；这条文件本身跑完就删。
// 每一发都在 node 里解析完只报"条数与前 3 个 id"，730 KB 的正文一个字不进读数文件。
const fs = require('fs'), http = require('http');
const key = fs.readFileSync('/root/.dsh/entry.key', 'utf8').trim();
function hit(n) {
  return new Promise((resolve) => {
    const t0 = Date.now();
    const req = http.get({ host: '127.0.0.1', port: 3081, path: '/dsh-market/registry',
      headers: { host: '127.0.0.1:3081', cookie: 'dsh-entry=' + key, 'user-agent': 'curl-probe-48' },
      agent: false, timeout: 150000 }, (res) => {
      const chunks = []; let bytes = 0;
      res.on('data', (d) => { chunks.push(d); bytes += d.length; });
      res.on('end', () => {
        const ms = Date.now() - t0;
        let sum = '';
        if (res.statusCode === 200) {
          try {
            const j = JSON.parse(Buffer.concat(chunks).toString('utf8'));
            const arr = Array.isArray(j) ? j : (j.plugins || j.catalog || j.entries || j.items || null);
            sum = Array.isArray(arr)
              ? arr.length + ' 条；前 3 个 ' + arr.slice(0, 3).map((p) => p.id || p.name || p.slug || '?').join(', ')
              : '顶层不是数组，键 = ' + Object.keys(j).slice(0, 10).join('|');
          } catch (e) { sum = '200 但 JSON 解析失败：' + e.message.slice(0, 60); }
        } else {
          sum = '非 200，body 头 180 字 = ' + Buffer.concat(chunks).toString('utf8').replace(/\s+/g, ' ').slice(0, 180);
        }
        console.log(`  第 ${n} 发 → ${res.statusCode} ${bytes} B ${ms} ms ct=${res.headers['content-type'] || '-'}`);
        console.log(`        ${sum}`);
        resolve({ ms });
      });
    });
    req.on('timeout', () => { console.log(`  第 ${n} 发 → 150 s 没回完，主动断开`); req.destroy(); resolve({ ms: 150000 }); });
    req.on('error', (e) => { console.log(`  第 ${n} 发 → 连接错 ${e.code || e.message}`); resolve({ ms: 0 }); });
  });
}
(async () => {
  console.log('  第一发（plugins.json 那 730 KB 走 GitHub Pages 的 Fastly，慢的话就慢在这一发）：');
  await hit(1);
  console.log('  第二发（紧跟着再打，两发的毫秒一比就知道插件有没有把结果缓存住）：');
  await hit(2);
})();
JS
node /tmp/p48route-$TS.js 2>&1 | sed 's/^//'
echo "  发请求之后：log.ndjson = $(stat -c %s $M/log.ndjson 2>/dev/null) B / $(wc -l < $M/log.ndjson 2>/dev/null) 行，改于 $(stat -c %y $M/log.ndjson 2>/dev/null | cut -d. -f1)"
echo "  --- 日志尾部两行（只看 event 与 detail 的头 150 字）"
tail -2 $M/log.ndjson 2>/dev/null | cut -c1-150 | sed 's/^/      /'
echo "  --- 插件那侧有没有落缓存件（.dsh-market 目录清单）"
ls -la $M 2>/dev/null | awk 'NR>1{printf "      %-28s %10s B  %s %s\n", $9, $5, $6, $7}'
rm -f /tmp/p48route-$TS.js /tmp/p48body.json
echo "  --- 顺手复点入口内存里那圈流水的 market 行数（口径同 --status，不重跑那条命令就没意义）"
HOME=/root TMPDIR=/tmp DSH_ENTRY_KEY_FILE=/root/.dsh/entry.key DSH_ENTRY_PORT=3081 DSH_UP_PORT=3080 \
  node /usr/local/bin/dsh-entry.js --status 2>&1 | grep -E 'dsh-market|计数|最近请求' | cut -c1-120 | sed 's/^/      /'

echo "== 3. 剩下那几批要装多少（apt-get -s，一个字节不写；这批的数字就是给他挑的）"
for BATCH in "pip:python3-pip" "编译:gcc g++ make cmake pkg-config" "媒体文档:ffmpeg imagemagick poppler-utils sqlite3" "杂项:unzip zip file rsync wget tmux"; do
  NAME=${BATCH%%:*}; PKGS=${BATCH#*:}
  apt-get -s install -y --no-install-recommends $PKGS >/tmp/.p48sim 2>&1; RC=$?
  echo "  [$NAME] apt-get -s install -y --no-install-recommends $PKGS → rc=$RC"
  grep -E 'upgraded,|Need to get|After this operation' /tmp/.p48sim | sed 's/^/      /'
  grep -E '^E: ' /tmp/.p48sim | sed 's/^/      报错: /'
  rm -f /tmp/.p48sim
done

echo "== 4. apt 留下的下载缓存（可清，清不清他说了算）"
echo "  /var/cache/apt/archives = $(du -sk /var/cache/apt/archives 2>/dev/null | cut -f1) KB，.deb 计数 = $(ls -1 /var/cache/apt/archives/*.deb 2>/dev/null | wc -l)"

echo "== 5. 服务复点（这一发只发了两条 GET，不该有任何换代）"
echo "  含 'dsh web' 的进程数 = $(pgrep -f 'dsh web' | wc -l)  引擎 pid = $(pgrep -f 'dsh web' | head -1)（14.28 那格起它是 21363，变了就是换代了）"
printf '  :3080 GET / → %s\n' "$(curl -s -o /dev/null -m 8 -w '%{http_code} %{size_download}B' http://127.0.0.1:3080/ 2>&1)"
echo "  流量增量口径：这一发前后的 /proc/net/dev 全表没在这里取，回 Windows 侧与 p46.txt 第 6 节那份比"
echo " 完（探针 48：发了两发真 GET 给市场路由，除此之外全只读；没点「应用」、没装包、没改 hosts、没重启）"
