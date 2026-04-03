# Filelay 已发现问题记录

更新时间：2026-04-02

## 1) 开启「自动启动」时可能出现双实例

- **现象**：在 Filelay 正在运行时，打开设置中的「开机自动启动」，会立刻出现第二个 Filelay 实例。
- **原因**：安装登录项脚本会执行 `launchctl bootstrap`，且 `LaunchAgent` 配置了 `RunAtLoad=true`，因此注册完成后会马上拉起一份新进程。
- **修复状态**：已在应用侧加入“单实例保护”。若检测到已存在同一 Bundle ID 或同一路径可执行文件的实例，新实例会自动退出。
- **受影响位置**：`Sources/Filelay/StatusBarApp.swift`、`install_menu_app_autostart.sh`

## 2) 可能存在 watcher 触发的高频同步循环

- **现象**：在内容未变时，仍可能出现频繁同步周期触发。
- **原因**：同步中会更新 metadata 回执时间戳（`lastAppliedAt`），metadata 写入本身又会触发 watcher，可能形成循环触发。
- **修复状态**：已修复。
- **修复方式**：不再监听 metadata 写入路径；同时只有当收据内容确实变化时才更新时间戳并写入 metadata。
- **受影响位置**：`Sources/Filelay/SyncEngine.swift`、`Sources/Filelay/FileSystemMonitor.swift`

## 3) 关联已有文件时版本基线可能缺失

- **现象**：个别关联路径下，后续冲突判定可能过于保守。
- **原因**：当 metadata 中 `cloudVersion` 为空时，关联流程可能写入了回执但没有完整初始化 `cloudVersion`，导致 `lastSeenCloudVersionId` 基线不稳定。
- **修复状态**：已修复。
- **受影响位置**：`Sources/Filelay/SyncEngine.swift`

## 4) 文件夹 hash 对符号链接风险处理不足

- **现象**：同步目录中存在符号链接时，可能出现枚举异常膨胀或性能问题。
- **原因**：目录哈希遍历中未显式跳过符号链接。
- **修复状态**：已修复。
- **修复方式**：目录 hash 对符号链接做“按链接本身计入 hash、且不遍历其目标内容”，避免递归/环导致的卡顿。
- **受影响位置**：`Sources/Filelay/SyncEngine.swift`

## 5) 冲突预览读取大文件会造成内存峰值

- **现象**：发生冲突且文件较大时，可能有明显内存占用升高。
- **原因**：预览逻辑一次性读取完整文件后再截断展示。
- **修复状态**：已修复。
- **修复方式**：冲突预览只读取前固定字节数（64KB），再尝试 UTF-8 解析并截断展示。
- **受影响位置**：`Sources/Filelay/SyncEngine.swift`
