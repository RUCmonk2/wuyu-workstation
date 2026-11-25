# 无语工作站 (Wuyu Workstation)

原生 macOS（Swift 6 / SwiftUI）多模型桌面调度工作台与共享 MCP 黑板，将 **Codex**、**Antigravity**（Gemini 4 + 内置 Claude）、**Gemini** 与 **Claude** 整合进一套轻量、丝滑的本地协作环境。

## 核心特性

- **macOS 磨砂玻璃四向悬浮 Dock**：支持 **顶部 / 底部 / 左侧 / 右侧** 自由切换（菜单一键切、设置页切、或直接拖向屏幕边缘自动磁吸变形），采用原生 `NSVisualEffectView` 玻璃材质与 `matchedGeometryEffect` 弹簧切页动效。
- **零闪烁桌面切换与一键联合分屏**：基于 macOS `AXUIElement` 实现单页浏览器式 Tab 切换及双拼 / `1+2` 三端分屏；已对齐窗口走零闪烁快路径，并针对 Electron 客户端内置 `AXEnhancedUserInterface` 兼容处理。
- **内置零依赖原生 Swift MCP Server（`bridge mcp`）**：同时挂载到 Codex 与 Antigravity，提供 `wuyu_get_current`、`wuyu_list_threads`、`wuyu_read_thread`、`wuyu_create_workflow`、`wuyu_submit_reply`、`wuyu_update_status` 6 个工具，彻底免记 UUID。
- **零传声筒全自动协同 + 内置 `CodexRunner`**：
  - 配合 Antigravity `/wuyu-flow` 技能与官方 `codex mcp-server` 实现多轮自主交互并实时直播上屏；
  - 工作站内直接调用本地 `codex exec --json`（支持 `read-only` / `workspace-write` 沙箱、推理强度与系统/自定义代理配置），流式显示进度并自动落盘回执。
- **多主题配色引擎**：默认使用「山水」日间主题，保留原有 11 套配色、日夜外观、对比度切换及自定义色值。「山水」主题的纸色、墨绿与山景来自 [叶耀之的个人主页](https://yeyaozhi.eu.cc/)。
- **桌面工作台 V2**：可拖拽侧边栏、85%–91% 自适应流式画幅、Markdown 代码块渲染与一键复制、目录实时监听（`DispatchSource`）、Git Diff 上下文自动抓取与剪贴板一键存回执。

## 构建与运行

需要 macOS 与 Xcode Command Line Tools（Swift 6）：

```sh
# 首次构建并安装到 ~/Applications/无语工作站.app（同时生成 .build/bridge-cli）
./build

# 打开工作站
./打开无语工作站.command

# 后续修改源码后一键更新并重启
./更新并重启无语工作站.command
```

### 命令行与 MCP

```sh
./bridge apps                     # 检查四个桌面客户端绑定路径
./bridge threads                  # 列出按任务聚合的协作线程
./bridge current antigravity      # 读取当前待处理的活跃线程
./bridge mcp                      # 以 stdio 模式运行本地 MCP Server
```

默认共享黑板目录为 `~/.wuyu-workstation/mailbox`（权限 `0700`，可用 `--store <目录>` 或环境变量 `WUYU_MAILBOX_DIR` 覆盖）。

### 辅助功能权限（一键分屏）

首次使用自动贴合与分屏时，请在 macOS **系统设置 → 隐私与安全性 → 设备控制和数据访问（辅助功能）** 中添加 `~/Applications/无语工作站.app`。

> **提示（更新免重授权）**：在 macOS「钥匙串访问 → 证书助理 → 创建证书」中创建一个名为 `WuyuWorkstationDev` 的本地「代码签名」证书后，`./build` 会自动使用该证书签名，往后每次更新重编译都能自动保留系统分屏权限。
