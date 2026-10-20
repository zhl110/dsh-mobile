// dsh-fetch-probe.js —— 只读：用 node 自己（跟 dsh 同一个运行时）打登录接口，把 no-response 的真因分开
// 不发任何密钥，不写盘
const origins = ["https://platform.deepseek.com", "https://api.deepseek.com"];
const paths = ["/auth-api/v0/dsh/auth_init", "/auth-api/v0/users/current"];

async function main() {
  console.log("node", process.version, "abi", process.versions.modules);
  const dns = require("node:dns");
  const os = require("node:os");
  for (const h of ["platform.deepseek.com", "api.deepseek.com"]) {
    dns.lookup(h, { all: true, verbatim: true }, (e, a) =>
      console.log(`dns.lookup ${h} ->`, e ? "ERR " + e.code : JSON.stringify(a)));
  }
  console.log("getaddrinfo verbatim off ->", os.networkInterfaces ? "" : "");
  for (const origin of origins) {
    for (const path of paths) {
      const url = origin + path;
      for (const mode of ["manual", "error"]) {
        for (const method of ["GET", "POST"]) {
          const t0 = Date.now();
          try {
            const r = await fetch(url, {
              method,
              redirect: mode,
              headers:
                method === "POST"
                  ? { "content-type": "application/json" }
                  : undefined,
              body: method === "POST" ? "{}" : undefined,
              signal: AbortSignal.timeout(15000),
            });
            let loc = r.headers.get("location") || "";
            let txt = "";
            try { txt = (await r.text()).slice(0, 90).replace(/\s+/g, " "); } catch {}
            console.log(
              `OK   ${mode}/${method} ${url} status=${r.status} type=${r.type} loc="${loc}" body="${txt}" ${Date.now() - t0}ms`
            );
          } catch (e) {
            console.log(
              `FAIL ${mode}/${method} ${url} name=${e.name} msg=${String(e.message).slice(0, 90)} cause=${e.cause ? String(e.cause.code || e.cause.message).slice(0, 90) : "-"} ${Date.now() - t0}ms`
            );
          }
        }
      }
    }
  }
}
main();
