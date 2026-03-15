# Filelay

**Sync any file across your Macs with iCloud — even apps that don't support sync.**

> No extra subscriptions. No third-party cloud. Your data stays in your iCloud.

Current version: `0.1.0` · Build `1`

[English](#english) · [中文](#chinese)

---

<a name="english"></a>

## What is Filelay?

Some apps store their config files, data, or state in fixed local paths that iCloud Drive can't reach. Filelay solves this — it watches those files and uses iCloud Drive as a relay layer to keep them in sync across all your Macs.

You don't need to move any files. You don't need to configure anything. Just pick a file, and Filelay takes care of the rest.

## Why Filelay?

- **You already have iCloud** — no new subscriptions, no new accounts
- **Your data stays in Apple's ecosystem** — nothing leaves iCloud
- **Zero config** — no dotfiles, no YAML, no terminal required
- **Works for any file** — app configs, certificates, scripts, saved state, license files

## How It Works

```text
Local file -> (file watch) -> iCloud relay -> (distributed to) -> Other Macs
```

1. On Device A, pick a local file and upload it to iCloud as a relay copy
2. On Device B, pick the corresponding local file and link it to the iCloud copy
3. Filelay monitors both sides — local changes sync up, iCloud changes sync down

**Important:** Files synced on Device A do **not** automatically appear on Device B. Device B must manually select its local file and establish the link. This is intentional — Filelay never creates or overwrites files without your explicit action.

## Features

- Watches only the files you explicitly select — no folder takeover
- Local files stay at their original paths — no migration required
- Bidirectional sync with automatic conflict detection
- When both sides change simultaneously, you choose which version wins
- Sync history, device status, and cloud deletion propagation
- Runs as a macOS menu bar app — always on, never in the way

## Getting Started

### Run from source

```bash
swift run Filelay
```

Or open `Package.swift` in Xcode and run the `Filelay` target.

### Auto-start on login

```bash
# Install
./install_menu_app_autostart.sh --app "/Applications/Filelay.app"

# Remove
./uninstall_menu_app_autostart.sh
```

### Run tests

```bash
swift test
```

## Use Cases

- Keep Cursor / VS Code / Raycast settings identical across Macs
- Sync app license files or certificates
- Sync shell configs or scripts stored outside `~/.config`
- Sync app data files that live inside the app's own directory
- Replace paid sync features you already get "for free" via iCloud

## Requirements

- macOS 13+
- iCloud Drive enabled

## License

MIT

---

<a name="chinese"></a>

# Filelay

**用 iCloud 同步任意 Mac 软件的文件，即使该软件本身不支持同步。**

> 不需要额外订阅。不引入第三方云服务。数据始终留在你的 iCloud 里。

当前版本：`0.1.0` · Build `1`

---

## Filelay 是什么？

有些软件把配置文件、数据或状态文件存放在固定的本地路径里，iCloud Drive 无法直接覆盖这些位置。Filelay 解决的就是这个问题，它监听这些文件，以 iCloud Drive 作为中转层，让它们在你的多台 Mac 之间保持同步。

你不需要移动任何文件，不需要写任何配置，选择文件，剩下的交给 Filelay。

## 为什么用 Filelay？

- **你已经有 iCloud 了** — 不需要额外订阅，不需要注册新账号
- **数据留在 Apple 生态内** — 没有任何数据流出 iCloud
- **零配置** — 不需要 dotfiles、不需要 YAML、不需要打开终端
- **适用于任意文件** — 应用配置、证书、脚本、使用数据、授权文件

## 工作方式

```text
本地文件 -> (文件监听) -> iCloud 中转 -> (分发到) -> 其他 Mac
```

1. 在设备 A 上选择一个本地文件，上传到 iCloud 作为中转副本
2. 在设备 B 上选择对应的本地文件，与 iCloud 中的副本建立关联
3. Filelay 同时监听两侧，本地变化自动上传，iCloud 变化自动同步到本地

**重要说明：** 设备 A 同步的文件**不会**自动出现在设备 B。设备 B 必须手动选择本地文件并建立关联，才会开始同步。这是有意为之的设计，Filelay 不会在未经你明确操作的情况下创建或覆盖任何文件。

## 核心特性

- 只同步你明确指定的文件，不接管整个文件夹
- 本地文件保留在原始路径，无需迁移
- 双向同步，自动检测冲突
- 双端同时修改时，由你决定保留哪一个版本
- 支持同步历史、设备状态查看、云端删除传播
- 以 macOS 菜单栏 app 形式常驻运行，不打扰日常使用

## 快速开始

### 从源码运行

```bash
swift run Filelay
```

或在 Xcode 中打开 `Package.swift`，运行 `Filelay` target。

### 开机自启动

```bash
# 安装
./install_menu_app_autostart.sh --app "/Applications/Filelay.app"

# 移除
./uninstall_menu_app_autostart.sh
```

### 运行测试

```bash
swift test
```

## 典型使用场景

- 保持多台 Mac 上的 Cursor / VS Code / Raycast 配置完全一致
- 同步软件授权文件或证书
- 同步存放在 `~/.config` 以外位置的 shell 配置或脚本
- 同步存放在软件自身目录下的应用数据文件
- 替代某些软件的付费同步功能，你已经有 iCloud 了

## 系统要求

- macOS 13+
- 已启用 iCloud Drive

## 开源协议

MIT
