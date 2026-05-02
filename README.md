# History

History 是一个 macOS 菜单栏工具，用 SwiftUI 编写，用来查看、搜索并打开最近使用过的文件、应用和文件夹。

## 功能

- 常驻 macOS 菜单栏
- 展示最近文件、应用和文件夹
- 支持按名称、路径和类型搜索
- 支持点击记录打开，并可在 Finder 中显示
- 左键点击菜单栏图标打开窗口，右键点击菜单栏图标退出
- 优先读取 Finder/系统标记的最近使用记录，并按 Spotlight 的 `kMDItemLastUsedDate` 排序
- 读取 Finder 当前窗口路径和 Finder 最近文件夹记录，记录通过 Finder 打开的文件夹
- 记录通过本工具打开过的内容，作为系统记录的稳定补充

## 运行

开发调试：

```sh
swift run History
```

构建菜单栏 `.app`：

```sh
bash scripts/build-app.sh
open .build/History.app
```

`.app` 的 `Info.plist` 启用了 `LSUIElement`，运行时只显示菜单栏图标，不显示 Dock 图标。

## 最近记录说明

系统级记录通过 Spotlight 的 `mdfind -attr kMDItemLastUsedDate` 元数据结果获取，只读取带有 `kMDItemLastUsedDate` 的文件、应用和文件夹，并按该最近使用时间排序。Finder 或其他应用打开文件后，如果系统为它写入了 Spotlight 最近使用时间，就会出现在列表里，效果接近 Finder 的“最近使用”。

macOS 没有稳定公开 API 可以实时监听 Finder 对所有文件、应用和文件夹的“打开”动作，所以这里采用系统最近使用元数据作为主要来源；通过本工具打开的项目会写入本地缓存，后续会稳定展示。

## Finder 权限

为了记录 Finder 打开的文件夹，History 会读取两类来源：

- 通过 AppleEvent 读取 Finder 当前窗口的目标路径。
- 读取 Finder 的 `FXRecentFolders` 最近文件夹书签记录。

首次运行打包后的 `.app` 时，macOS 会提示允许 History 控制 Finder；请选择允许。

如果之前拒绝过授权，可以在这里重新开启：

```text
系统设置 > 隐私与安全性 > 自动化 > History > Finder
```

调试时建议运行 `.build/History.app`，而不是直接 `swift run`，这样权限会绑定到 History 这个 App。
