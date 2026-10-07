# Vhostty 开发者文档

给想了解实现或参与开发的人看。使用说明见 [README](README.zh-CN.md)。

## 工作原理

### Claude 是怎么启动的

每个会话用的命令大致是：

```
$SHELL -l -i -c 'vhostty-claude --session-id <uuid>; exec $SHELL -l'
```

- `vhostty-claude` 实际执行的是 `claude --settings <Vhostty 的 hooks 配置> ...`。这份 hooks 配置会和你自己的 `~/.claude/settings.json` **合并**，你自己的配置不会被改动。
- 会话 ID 由 Vhostty 生成，所以它确切知道每张卡片对应哪个 Claude 会话，之后也能 `--resume` 恢复。
- Claude 退出后在同一个 tab 里手动跑 `claude -r <id>` 也会被跟踪：Claude Code 为每个运行中的进程写 `~/.claude/sessions/<pid>.json`，Vhostty 从进程环境变量里的 `VHOSTTY_TAB_ID` 认出它属于哪张卡片，把卡片切到那个会话。这样起的 claude 不带 hooks，状态只能靠终端标题。

### Codex 会话

Codex 每张卡片跑的是 `vhostty-codex -c tui.terminal_title=…`（新建）或 `vhostty-codex resume -c tui.terminal_title=… <id>`（恢复），它只是调用 `codex`，退出后通过 `vhostty-hook` 告诉 App。和 Claude 的不同：

- Codex 不能预先指定会话 ID，而且 TUI 只是共享后台服务（daemon）的客户端，进程上看不出它在跑哪个会话。所以 Vhostty 用 `-c` 把卡片里 Codex 的终端标题设成 `["activity","thread-title"]`：会话还没有标题时，`thread-title` 显示的就是完整的会话 ID（Codex 一启动就有）。卡片从自己的终端标题里读到 ID。（`thread-id` 这一项会被截到 32 个字符，不能用。）
- Codex 在发出第一条消息时才保存会话，没保存的会话不能 `codex resume`。所以读到的 ID 先记在 `codexThreadID`，等它出现在 Codex 的会话索引 `~/.codex/state_<n>.sqlite` 的 `threads` 表里，才成为卡片的会话 ID。在 Codex 里 `/new` 开了新会话，标题里会出现新的 ID，卡片也跟着换。
- 不注入 Codex hooks（Codex 的 hooks 要用户手动信任，而且在 daemon 里运行，拿不到卡片的环境变量）。状态来自终端标题：有转圈就是工作中。启动和恢复时 Codex 也会转一会儿，这一段不算一轮工作。
- 历史会话、标题、分支也来自 `threads` 表（只列用户自己发起的会话，不含子代理、自动化和已归档的）。
- Codex 的数据目录是 `CODEX_HOME`（默认 `~/.codex`）。卡片里的 Codex 由交互式登录 shell 启动，所以 Vhostty 启动时也用 `$SHELL -l -i -c` 读这个变量。

### 卡片上的信息从哪来

| 信息 | 来源 |
|---|---|
| 标题 | Claude 写到终端标题的内容（`✳ xxx` / `◑ xxx`）；也会读会话记录 `~/.claude/projects/*/<id>.jsonl` 里的 `custom-title` / `ai-title` |
| 状态 | Claude Code hooks：`UserPromptSubmit` / `PostToolUse` → 工作中，`Notification` → 等你确认，`Stop` → 完成。终端标题前面的状态符号（`✳` 空闲，其他转圈符号表示工作中）作为补充 |
| 系统通知 | Claude Code 自己发出的终端通知（OSC 9/777），由 Vhostty 转成 macOS 通知 |
| 分支 / worktree | 对 Claude 当前的 cwd 执行 `git rev-parse`，cwd 来自 hooks |
| PR | 用 `gh pr view <branch>` 查当前分支对应的 PR；查不到时，用会话记录里的 `pr-link` |

hooks 事件的传递路径：`vhostty-hook`（App 里自带的一个小程序）通过 Unix socket，把事件转发给 App。

## 为了不装 Xcode 做的处理

Ghostty 官方的 macOS 构建依赖 Xcode。为了只用 Command Line Tools 就能编译，`patches/ghostty-vhostty.patch` 对 Ghostty 做了这些改动：

1. **Metal 着色器改成运行时编译**（`newLibraryWithSource`）。这样就不需要 Xcode 自带的 `metal` 编译器。
2. **在 macOS 上额外输出静态库 `libghostty.a` 和资源文件**。官方构建只产出 xcframework。
3. **修复打包问题**：新版 `libtool` 会静默丢弃 zig 打包时没有 8 字节对齐的目标文件，改成先解包再重新打包。

另外还有两个绕路：

- `scripts/make-zig-sdk.sh`：macOS 26 以后的 SDK 里，库描述文件只写了 arm64e 架构，zig 0.15 识别不了。这个脚本用 APFS 克隆一份 SDK（几乎不占空间），补上 arm64。
- `scripts/bundle.sh`：用 macOS 26 SDK 编译 Swift。因为 macOS 27 SDK 把 SwiftUI 的 `@State` 改成了宏，而宏插件只随 Xcode 提供。

## 开发调试

```bash
VHOSTTY_SUPPORT_DIR=/tmp/vhostty-test \
VHOSTTY_DEBUG_SNAPSHOT=/tmp/vhostty-snap \
build/Vhostty.app/Contents/MacOS/Vhostty
```

- `VHOSTTY_SUPPORT_DIR`：使用一份独立的状态目录，不影响正式数据。
- `VHOSTTY_DEBUG_SNAPSHOT`：每 1.5 秒把窗口截图和状态写到这个目录（`window.png`、`state.txt`）。往 `input.txt` 写命令可以驱动 App，一行一条：

| 命令 | 作用 |
|---|---|
| `to <UUID>` / `toshell <UUID>` | 指定后面按键发给哪个会话的 Claude 终端 / 底部终端 |
| `text …`、`enter`、`up`、`down`、`esc` | 往指定的终端输入文字或按键 |
| `notify` | 给指定会话发一条测试通知，授权状态写到 `notify.txt` |
| `select <UUID>` | 切换到这个会话 |
| `new` / `new claude` / `new codex` | 新建默认类型 / Claude / Codex 会话 |
| `search [文字]` / `endsearch` | 打开当前项目的会话搜索并填入文字 / 关闭搜索 |
| `toggleshell` | 开关当前会话的底部终端 |
| `focus claude` / `focus shell` | 聚焦上面 / 下面的终端 |
| `menukey <ctrl\|cmd> <字符>` | 把快捷键直接交给主菜单处理 |
| `post <ctrl\|cmd\|none> <字符>` | 模拟一次真实按键，走 AppKit 正常的分发流程 |
| `cmdj-through-terminal` | 检查 ⌘J 是被终端吃掉还是交给了菜单，结果写到 `keyequiv.txt` |

按键和文字只会发给用 `to` / `toshell` 明确指定的会话。

## 发布

推一个 `v` 开头的标签，GitHub Actions（`.github/workflows/release.yml`）就会在 macOS arm64 机器上编译，把 `Vhostty.zip` 发到同名的 Release：

```bash
git tag v0.2.0 && git push origin v0.2.0
```

版本号取自标签，写进 `Info.plist` 的 `CFBundleShortVersionString`。libghostty 按 Ghostty 版本和补丁缓存，补丁不变时不会重新编译。在 Actions 页面手动运行这个 workflow 只编译、上传构建产物，不发 Release。用户通过 `scripts/install.sh` 安装最新的 Release。

## 文档

README 有英文（`README.md`）和中文（`README.zh-CN.md`）两份，改功能、快捷键或构建步骤时两份要一起改。

## 多语言

界面文字在代码里写英文（`String(localized:)`，以及 SwiftUI 的 `Text` / `Button` 等字面量），简体中文翻译在 `Resources/zh-Hans.lproj/Localizable.strings`，英文的单复数在 `Resources/en.lproj/Localizable.stringsdict`。App 跟随系统语言；想单独切换，可以在「系统设置 → 通用 → 语言与地区 → 应用程序」里给 Vhostty 指定语言，或者：

```bash
defaults write dev.vhostty.Vhostty AppleLanguages '("en")'   # 恢复：defaults delete dev.vhostty.Vhostty AppleLanguages
```

新增文字时记得同时在 `zh-Hans.lproj` 里加一条翻译，key 就是英文原文（插值写成 `%@` / `%lld`）。
