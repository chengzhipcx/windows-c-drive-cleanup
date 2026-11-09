# windows-c-drive-cleanup

一个 [ZCode](https://github.com/) / Claude Code 风格的 **Agent Skill**:让 AI 助手按实测有效的流程,帮你分析并清理 Windows C 盘空间,并把 npm / Yarn / uv / Bun 等开发缓存迁移到大容量磁盘,防止复发。

> 本技能源自一次真实清理:Windows 11 + Git Bash 环境,单次释放 **27GB**(4GB → 31GB),并把四大包管理器缓存全部迁到 D 盘。

## 解决什么问题

- C 盘红了不知道空间去哪了
- `AppData\Local\Temp` 里几十个 `_MEI*` PyInstaller 残留目录
- npm / Yarn / uv 缓存不知不觉吃掉 10GB+
- VS Code 扩展安装包缓存(`CachedExtensionVSIXs`)越攒越多
- 清完没多久又满了 —— 因为缓存默认还在 C 盘

## 安装

把 `SKILL.md`、`scripts/` 复制到你的 Agent 技能目录:

```bash
# ZCode 用户级技能目录
cp -r windows-c-drive-cleanup ~/.agents/skills/
```

或者克隆整个仓库:

```bash
git clone https://github.com/chengzhipcx/windows-c-drive-cleanup.git ~/.agents/skills/windows-c-drive-cleanup
```

## 技能内容

| 文件 | 说明 |
|---|---|
| `SKILL.md` | 完整工作流:分析 → 分档清理 → 缓存迁移 → 验证,含 Git Bash 环境踩坑记录 |
| `scripts/scan_c_drive.sh` | 分层扫描脚本:`--tier1` 快扫热点 / `--tier2` AppData 全量 / `--tier3` 顶层目录,`--json` 程序化输出 |
| `scripts/clean_c_drive.sh` | 零风险档清理:默认 dry-run 只列清单,`--apply` 才执行;Temp(_MEI* 残留)+ npm/Yarn/uv/pip 缓存 + VS Code 扩展缓存 |

## 工作流概览

1. **分析**:磁盘总览 → 排除 pagefile/WSL 误判 → 后台 `du` 三层扫描 → 定位热点
2. **报告**:表格呈现,按风险分档(零风险 / 需确认 / 禁区),让用户选择
3. **清理**:Temp(保留活跃会话)+ 各包管理器官方清理命令
4. **迁移**:npm(~/.npmrc)、uv/Yarn(setx)、Bun(BUN_INSTALL + PATH)
5. **验证**:前后剩余空间对比,如实汇报实测值

## 内置踩坑记录(均实测踩过)

- Git Bash 中 PowerShell `$_` 被 shell 吞掉 → 用 `\$_`
- robocopy 斜杠参数(`/MOVE` `/E`)被 MSYS 转义 → `MSYS_NO_PATHCONV=1` 或改用 `cp`
- **bun 缓存内是符号链接别名,直接 `cp` 会展开成双倍体积** → 缓存清掉重建,勿搬运
- 搬运必须先校验大小/文件数再删源
- `setx` 后已开终端读不到新值,`reg query /v` 在 Git Bash 下不可用

## 关于作者

- 个人网站：[codercheng.xyz](https://codercheng.xyz)
- 微信公众号：**coder程**（微信搜一搜，或扫码关注）

<p align="center">
  <img src="wechat-codercheng.png" width="560" alt="微信公众号：coder程">
</p>

## License

[MIT](LICENSE)
