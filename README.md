# Filelay

`Filelay` 是一个 macOS 菜单栏常驻的指定文件同步工具。

它解决的是这样一类问题：有些文件必须留在软件自己的原始目录里，比如配置文件、证书、脚本、使用数据或应用状态文件。这些文件不能直接搬进 iCloud Drive，但你又希望它们在多台 Mac 之间保持一致。`Filelay` 会保留这些文件原本的位置，再借助 iCloud Drive 作为中转层完成同步。

## 核心特点

- 只同步你明确指定的文件，不接管整个文件夹
- 本地文件保留在原始路径，不要求迁移到 iCloud 目录
- 使用 iCloud Drive 作为中转，不额外引入第三方网盘
- 每台设备都需要手动建立关联，不会偷偷创建本地文件
- 本地变化自动上传，云端新版本自动同步到已关联设备
- 双端同时修改时进入冲突处理，而不是静默覆盖
- 支持版本信息、设备状态、同步历史和云端删除传播

## 适用场景

- 同步应用配置文件
- 同步软件使用数据或状态文件
- 同步证书、脚本、模板、规则文件
- 同步那些依赖固定路径、软件本身又不提供同步能力的文件
- 软件提供同步但需要额外付费，而你已经有 iCloud Drive

## 工作方式

1. 在 `Filelay` 中选择一个本地文件
2. 决定把它上传为新的云端文件，或关联到一个已有云端文件
3. 建立关联后，`Filelay` 会监听本地与云端变化，并在后台自动同步
4. 如果两边同时发生修改，系统会进入冲突处理，由你决定保留哪一边

重要规则：

- 设备 A 已同步的文件，不会自动出现在设备 B
- 设备 B 必须手动选择本地文件并建立关联，才会开始同步
- 自动识别只做提示，不会自动关联

## 运行

```bash
swift run Filelay
```

也可以在 Xcode 中直接打开 `Package.swift` 运行 `Filelay` target。

## 测试

```bash
swift test
```

## 开机自启动

安装登录项：

```bash
./install_menu_app_autostart.sh --app "/Applications/Filelay.app"
```

移除登录项：

```bash
./uninstall_menu_app_autostart.sh
```

## 真实 iCloud 验收

真实 iCloud 环境下的双设备验收清单见：

- [Docs/Real-iCloud-Acceptance-Checklist.md](Docs/Real-iCloud-Acceptance-Checklist.md)
