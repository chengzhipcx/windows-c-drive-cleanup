---
name: windows-c-drive-cleanup
description: Windows C 盘空间分析与清理,以及开发缓存(npm/Yarn/uv/Bun/pip/pnpm)迁移到其他磁盘。当用户提到 C 盘满了、磁盘空间不足、清理磁盘、释放空间、电脑变卡想清理、Temp 临时文件、AppData 占用大、HuggingFace/模型缓存、Docker 虚拟磁盘过大、包管理器缓存迁移时使用;即使用户只是随口问"C 盘怎么又满了"也应触发本技能。
---

# Windows C 盘清理与缓存迁移

实测有效的完整流程(2026-11 在 Windows 11 + Git Bash 环境验证,单次释放 27GB)。核心思路:**先分析再动手、按风险分档让用户选择、清完顺手迁移缓存防复发**。

## 总流程

1. 分析:磁盘总览 → 排除误判项 → 大目录扫描 → 定位热点
2. 报告:表格呈现数据,按风险分档给方案,让用户选择执行范围
3. 清理:按用户选定的档位执行
4. 迁移(推荐主动提出):包管理器缓存迁到大容量盘
5. 验证:对比清理前后剩余空间,如实汇报

本技能自带两个脚本,优先用它们而不是临时拼命令:

```bash
# 扫描(分层控制耗时,--json 便于程序处理)
bash scripts/scan_c_drive.sh --tier1 <用户名>   # 只扫已知热点,约 1 分钟
bash scripts/scan_c_drive.sh --tier2 <用户名>   # 默认:热点 + AppData 全量
bash scripts/scan_c_drive.sh --tier3 --json <用户名>  # 加顶层目录,最慢

# 零风险档清理:默认 dry-run 只列清单,确认后加 --apply 才执行
bash scripts/clean_c_drive.sh <用户名>
bash scripts/clean_c_drive.sh --apply <用户名>
```

清理脚本体现了一个关键原则:**破坏性操作必须先 dry-run 展示清单,经确认再执行**。自己拼清理命令时也遵守这个原则。

## 第一步:磁盘分析

### 磁盘总览

Git Bash 里 PowerShell 的 `$_` 会被 shell 吞掉,统一用 `\$_` 转义:

```bash
powershell -NoProfile -Command "Get-CimInstance Win32_LogicalDisk | ForEach-Object { '{0} 总:{1:N0}GB 已用:{2:N0}GB 剩余:{3:N0}GB' -f \$_.DeviceID, (\$_.Size/1GB), ((\$_.Size-\$_.FreeSpace)/1GB), (\$_.FreeSpace/1GB) }"
```

### 排除误判项(动手前先确认,避免白忙)

- **pagefile.sys / hiberfil.sys**:`ls -la /c/ | grep -iE "pagefile|hiberfil"`。若虚拟内存已配到其他盘,这块不占 C 盘。
- **WSL 虚拟磁盘**:`wsl --list -v`(输出乱码通常意味着未安装发行版);再 `find /c/Users -maxdepth 5 -name "*.vhdx"` 兜底。

### 大目录扫描

`du` 扫大目录很慢(Users 目录可达数分钟),**必须 run_in_background 后台跑**,同时并行查其他线索,最后汇总。推荐三层递进:

```bash
# 1. 顶层分布(后台)
du -s -B1 /c/Users /c/Windows "/c/Program Files" "/c/Program Files (x86)" /c/ProgramData

# 2. 用户 AppData 两个子树(后台)
du -s -B1 /c/Users/<user>/AppData/Local/*   | awk '$1>300000000 {printf "%.2f GB\t%s\n", $1/1073741824, $2}'
du -s -B1 /c/Users/<user>/AppData/Roaming/* | awk '$1>100000000 {printf "%.2f GB\t%s\n", $1/1073741824, $2}'

# 3. 系统级可清理项(很快)
du -s -B1 /c/Windows/SoftwareDistribution/Download /c/Windows/Temp /c/Windows/Installer '/c/$Recycle.Bin'
```

### 已知热点清单(按出现频率与收益排序)

| 路径(在 `%USERPROFILE%` 下) | 典型大小 | 性质 |
|---|---|---|
| `AppData\Local\Temp` | 5~15GB | `_MEI*` PyInstaller 程序残留(每个约 0.25GB,残留几十个很常见)、安装包 `.tmp` 残留 |
| `AppData\Local\npm-cache` | 2~5GB | npm 缓存 |
| `AppData\Local\Yarn` | 3~5GB | Yarn 缓存 |
| `AppData\Local\uv` | 1~4GB | uv 缓存 |
| `AppData\Local\pip` | 0.5~3GB | pip 缓存(`pip cache purge`) |
| `AppData\Local\pnpm` | 1~5GB | pnpm store(`pnpm store prune`) |
| `AppData\Roaming\Code\CachedExtensionVSIXs` | 1~2GB | VS Code 扩展安装包缓存 |
| `AppData\Local\ms-playwright` | ~2GB | Playwright 浏览器(`npx playwright uninstall --all` 可删) |
| `~\.cache` | 1~30GB | HuggingFace 模型(`~\.cache\huggingface`)、torch 等缓存;AI 用户重点排查 |
| `~\.ollama` | 2~50GB | Ollama 本地模型 |
| `AppData\Local\Docker` | 5~30GB | Docker Desktop 的 `ext4.vhdx` 虚拟磁盘,**只增不减**;要在 Docker 设置里迁盘或 `docker system prune` 后 compact vhdx |
| `AppData\Local\NVIDIA\DXCache`、`GLCache` | 0.5~2GB | 着色器缓存,可删会重建 |
| `AppData\Local\Google` | 5GB+ | Chrome 数据,只能清其中 Cache/Code Cache/GPUCache 子目录 |
| `miniconda3`/`anaconda3`(若在 C 盘) | 3~20GB | conda 环境;`conda clean --all` 清缓存,环境本身需确认 |
| `AppData\Roaming\Tencent`、微信/钉钉等 | 3~5GB | 聊天数据,**禁区**(微信可在设置里把存储迁到 D 盘) |
| `/c/Windows.old` | 10~30GB | 旧系统备份,升级后 10 天可自动清;`cleanmgr` 里"以前的 Windows 安装"删除 |

先按这张表定向排查,再结合 du 扫描结果补充本机特有大户。

### 非开发类大户与系统级手段

开发缓存之外,按顺序考虑这些(收益从高到低):

1. **微信/QQ 存储迁移**:微信 设置→文件管理→更改目录到 D 盘(迁移自带搬运,比手动搬安全)。
2. **磁盘清理 cleanmgr**:运行 `cleanmgr /d C:`,勾选"Windows 更新清理""以前的 Windows 安装""缩略图"等;先 `cleanmgr /sageset:1` 配置可复用。
3. **组件存储清理**:`Dism /Online /Cleanup-Image /StartComponentCleanup`(WinSxS 瘦身,通常回收 1~3GB,勿加 /ResetBase 以保留卸载补丁能力)。
4. **存储感知**:设置→系统→存储 开启存储感知,自动定期清 Temp 和回收站,治本。
5. **系统还原点**:`vssadmin list shadowstorage` 查占用;一般不建议动,除非占用异常。

## 第二步:分档清理

分析完先给报告,按风险分档,**让用户选择执行范围**,不要擅自清理:

- **第一档(零风险,默认推荐)**:Temp(保留活跃会话目录)、npm/Yarn/uv/pip 缓存、VS Code `CachedExtensionVSIXs`。包缓存删后自动重建,代价只是下次装包慢一点。这一档可直接用 `scripts/clean_c_drive.sh`(先 dry-run 看 `--apply`)。
- **第二档(需用户确认)**:Playwright 浏览器、Chrome 的 Cache 子目录、各 AI IDE(TRAE/Code 等)的缓存目录。逐项说明用途后再删。
- **禁区(无论用户多着急都不碰)**:Tencent/微信/QQ 数据、`Documents`、浏览器 Profile、`Windows\Installer`(卸载修复依赖)、用途不明的目录。

### 执行要点

Temp 清理保留活跃会话(如 ZCode 的 `zcode-bash-*` 前缀):

```bash
cd /c/Users/<user>/AppData/Local/Temp && for f in *; do case "$f" in zcode-bash-*) continue;; esac; rm -rf "$f" 2>/dev/null; done
```

包管理器优先用官方清理命令,比手动 rm 更干净:

```bash
npm cache clean --force
yarn cache clean
uv cache clean
```

## 第三步:缓存迁移(防复发,清理后主动建议)

| 工具 | 配置方式 | 生效时机 |
|---|---|---|
| npm | `npm config set cache "D:\\cache\\npm"`(写入 ~/.npmrc) | 立即 |
| uv | `setx UV_CACHE_DIR "D:\cache\uv"` | 新终端 |
| Yarn 1.x | `setx YARN_CACHE_FOLDER "D:\cache\yarn"` | 新终端 |
| Bun | `setx BUN_INSTALL "D:\cache\bun"` + 修改 PATH | 新终端 |
| pip | `pip config set global.cache-dir D:\cache\pip` | 立即 |
| pnpm | `pnpm config set store-dir D:\cache\pnpm-store` | 立即(已有项目重装依赖后生效) |

- `setx` 写用户级注册表。验证一律用 PowerShell 读(`reg query /v` 的 `/v` 会被 Git Bash 转义成路径,不可用):
  ```bash
  powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('UV_CACHE_DIR','User')"
  ```
- 配置完成后用真实命令验证识别(`uv cache dir`、`npm config get cache`),不能只看 setx 报成功。

### Bun 迁移的特殊坑

bun 的缓存目录(`~/.bun/install/cache`)内部是**符号链接别名**(bun 的 Windows 兼容机制),直接 `cp -r` 会把链接展开成真实文件副本,体积翻倍、链接结构丢失。正确做法:

1. `bin` 本体复制到新位置,验证可执行(`bun.exe --version`);
2. **缓存直接删掉不搬**——纯可再生数据,bun 下次装包会在新位置自建正确结构;
3. 删除旧 `~/.bun` 前先改 PATH,否则 bun 命令失效:
   ```powershell
   $p = (Get-Item 'HKCU:\Environment').GetValue('Path', '', 'DoNotExpandEnvironmentNames')
   $new = $p.Replace('C:\Users\<user>\.bun\bin', 'D:\cache\bun\bin')
   Set-ItemProperty -Path 'HKCU:\Environment' -Name Path -Value $new -Type ExpandString
   ```

## 踩坑记录(Git Bash 环境,均实测踩过)

1. **PowerShell `$_` 被 Git Bash 吞掉** → 写成 `\$_`。
2. **robocopy 的 `/MOVE` `/E` 斜杠参数被 MSYS 转义成路径** → 轻则无效、重则报错 16 什么都不做。要么加 `MSYS_NO_PATHCONV=1`,要么改用 `cp -rp`。
3. **`cp` 复制含符号链接的目录会展开链接** → bun 缓存、node_modules 这类内容不要 cp,删掉重建。
4. **搬运必须先校验再删源**:`du -s -B1` 对比两侧大小 + `find -type f | wc -l` 对比文件数;数字对不上(如翻倍)立即停下排查,**绝不先删源目录**。
5. **大目录 du 必须后台跑**,前台超时白等;多个扫描任务并行发,统一等通知汇总。
6. **已开终端读不到 setx 新值** → 汇报时提醒用户重开终端才生效。
7. **rm -rf 大目录(几万文件)可能超过前台超时** → Temp 清理这种也要后台或容忍较长时间。

## 验证与汇报

清理完成后重查剩余空间,与清理前对比:

```bash
powershell -NoProfile -Command "Get-CimInstance Win32_LogicalDisk -Filter \"DeviceID='C:'\" | ForEach-Object { 'C盘剩余: {0:N1} GB' -f (\$_.FreeSpace/1GB) }"
```

汇报固定包含:**前后对比数字、逐项明细表、生效注意事项(重开终端/下次装包变慢)、长期建议(新项目与大工具装大容量盘)**。释放空间要如实报实测值,不估算。
