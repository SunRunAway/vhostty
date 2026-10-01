# Seance 👻

专门用来跑 Claude Code 的 macOS 原生终端。终端引擎用的是 [Ghostty](https://ghostty.org)（libghostty），外壳用 SwiftUI/AppKit 写，没有用任何 Web 技术。

> Séance（降神会）：召唤 Ghost(ty)，然后跟 Claude 对话。

## 功能

- **左侧是项目**：每个项目绑定一个目录。
- **项目下面是会话卡片**：每个会话就是一个 Claude Code 终端。卡片有 4 行：
  1. 会话标题，来自 Claude 自动生成的标题或 `/rename`，前面带状态图标
  2. 当前分支
  3. worktree 名称；不在 worktree 里时显示「主工作区」
  4. PR 号，比如 `#123`。颜色表示状态：open 绿 / merged 紫 / closed 红，点击会在浏览器打开
- **新建会话**：自动 `cd` 到项目目录，然后启动 `claude`。claude 退出后，终端会留在你的 shell 里。
- **状态实时显示**：
  - 转圈 = Claude 正在干活
  - ✋ = 等你确认权限
  - 绿点 = 等你输入
  - 蓝点 = 在后台干完了、你还没看
  - 空心圆 = 未启动
- **后台通知**：通知直接用 Claude Code 自带的终端通知（它识别出 Ghostty 后会发 OSC 9/777），所以会遵守你在 Claude 里的通知设置。会话没被选中或窗口在后台时，Seance 把它转成 macOS 系统通知，点击会跳到对应会话。Claude 一般在干完活、等你约 60 秒后才发通知；卡片上的蓝点和 Dock 角标则会立即更新（靠 hooks）。
- **历史会话**：每个项目下面列出最近的 Claude 会话，点一下就用 `claude --resume` 恢复。
- **自动保存**：退出时保存所有会话卡片。下次打开时，点哪个卡片才恢复哪个会话，不会一次性启动一堆 claude。
- **复用 Ghostty 配置**：直接读取你的 Ghostty 配置（字体、主题、快捷键），在 `~/.config/ghostty/config` 或 `~/Library/Application Support/com.mitchellh.ghostty/config`。

## 快捷键

| 快捷键 | 作用 |
|---|---|
| ⌘T | 在当前项目新建 Claude 会话 |
| ⇧⌘O | 添加项目 |
| ⌘W | 关闭当前会话（Claude 还在运行时会先问你） |
| ⌘1…9 | 切换到第 N 个会话 |
| ⇧⌘[ / ⇧⌘] | 上一个 / 下一个会话 |
| ⌃⌘S | 显示/隐藏侧栏 |
| ⌘+ / ⌘- / ⌘0 | 字体放大 / 缩小 / 还原 |

会话卡片和项目都可以右键，里面有更多操作。会话卡片还能拖动排序。

## 构建

只需要 Command Line Tools 和 zig，**不需要 Xcode**。

```bash
brew install zig          # 需要 0.15.2（Ghostty 1.3.1 的要求）
git clone --recursive <this repo> seance
cd seance
make                      # 第一次会先编译 libghostty，大约 5 分钟
make install              # 拷贝到 /Applications/Seance.app
```

## 工作原理

### Claude 是怎么启动的

每个会话用的命令大致是：

```
$SHELL -l -i -c 'seance-claude --session-id <uuid>; exec $SHELL -l'
```

- `seance-claude` 实际执行的是 `claude --settings <Seance 的 hooks 配置> ...`。这份 hooks 配置会和你自己的 `~/.claude/settings.json` **合并**，你自己的配置不会被改动。
- 会话 ID 由 Seance 生成，所以它确切知道每张卡片对应哪个 Claude 会话，之后也能 `--resume` 恢复。

### 卡片上的信息从哪来

| 信息 | 来源 |
|---|---|
| 标题 | Claude 写到终端标题的内容（`✳ xxx` / `◑ xxx`）；也会读会话记录 `~/.claude/projects/*/<id>.jsonl` 里的 `custom-title` / `ai-title` |
| 状态 | Claude Code hooks：`UserPromptSubmit` / `PostToolUse` → 工作中，`Notification` → 等你确认，`Stop` → 完成。终端标题前面的状态符号（`✳` 空闲，其他转圈符号表示工作中）作为补充 |
| 系统通知 | Claude Code 自己发出的终端通知（OSC 9/777），由 Seance 转成 macOS 通知 |
| 分支 / worktree | 对 Claude 当前的 cwd 执行 `git rev-parse`，cwd 来自 hooks |
| PR | 用 `gh pr view <branch>` 查当前分支对应的 PR；查不到时，用会话记录里的 `pr-link` |

hooks 事件的传递路径：`seance-hook`（App 里自带的一个小程序）通过 Unix socket，把事件转发给 App。

## 为了不装 Xcode 做的处理

Ghostty 官方的 macOS 构建依赖 Xcode。为了只用 Command Line Tools 就能编译，`patches/ghostty-seance.patch` 对 Ghostty 做了这些改动：

1. **Metal 着色器改成运行时编译**（`newLibraryWithSource`）。这样就不需要 Xcode 自带的 `metal` 编译器。
2. **在 macOS 上额外输出静态库 `libghostty.a` 和资源文件**。官方构建只产出 xcframework。
3. **修复打包问题**：新版 `libtool` 会静默丢弃 zig 打包时没有 8 字节对齐的目标文件，改成先解包再重新打包。

另外还有两个绕路：

- `scripts/make-zig-sdk.sh`：macOS 26 以后的 SDK 里，库描述文件只写了 arm64e 架构，zig 0.15 识别不了。这个脚本用 APFS 克隆一份 SDK（几乎不占空间），补上 arm64。
- `scripts/bundle.sh`：用 macOS 26 SDK 编译 Swift。因为 macOS 27 SDK 把 SwiftUI 的 `@State` 改成了宏，而宏插件只随 Xcode 提供。

## 开发调试

```bash
SEANCE_SUPPORT_DIR=/tmp/seance-test \
SEANCE_DEBUG_SNAPSHOT=/tmp/seance-snap \
build/Seance.app/Contents/MacOS/Seance
```

- `SEANCE_SUPPORT_DIR`：使用一份独立的状态目录，不影响正式数据。
- `SEANCE_DEBUG_SNAPSHOT`：每 1.5 秒把窗口截图和状态写到这个目录（`window.png`、`state.txt`）。往 `input.txt` 写命令可以驱动 App：先用 `to <会话卡片 UUID>` 指定目标，再用 `text …`、`enter`、`down`、`notify` 操作；`select <UUID>` 切换会话，`new` 新建会话。输入只会发给明确指定的会话。
