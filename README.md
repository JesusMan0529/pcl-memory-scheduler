# pcl-memory-scheduler

我写这个小工具，是为了定时调用 Plain Craft Launcher（PCL）里的“内存优化”，省去手动打开百宝箱、点击按钮的步骤。它使用 PCL 自带的 `--memory` 启动参数；它是独立工具，不是 PCL 官方插件，也没有修改 PCL 本体。

安装后，Windows 会在开机约 30 秒后启动后台程序。它立即调用一次 PCL，此后每 5 分钟调用一次。后台程序没有窗口，在任务管理器“详细信息”里叫 `MemoryScheduler.exe`。每次优化时会短暂出现 `Plain Craft Launcher 2.exe`。

## 准备

- Windows 10/11 x64。**必须先从 [PCL 官方下载页](https://meloong.com/pcl)下载 PCL 2 并安装或解压到电脑上**；本仓库不提供 PCL。先手动打开 PCL，确认“更多 → 百宝箱 → 内存优化”可以使用。
- Windows 自带的 PowerShell 5.1、.NET Framework 4.x 和任务计划程序。
- 一次管理员授权：PCL 的内存优化本身要求管理员权限。

安装时，我会把你指定的 PCL 可执行文件复制到 `Program Files` 下的受保护目录。后台程序随后运行这份副本，避免 SYSTEM 计划任务直接执行原安装目录里可能被普通用户替换的文件。**更新 PCL 后要重新安装本工具**，才能使用新版本的可执行文件。

## 安装

1. 下载并安装或解压 [PCL 2](https://meloong.com/pcl)，确认能找到 `Plain Craft Launcher 2.exe`。
2. 下载本仓库的源码 ZIP 并解压，或使用 `git clone https://github.com/JesusMan0529/pcl-memory-scheduler.git`。
3. 记下电脑上 `Plain Craft Launcher 2.exe` 的完整路径。
4. 以管理员身份打开 **Windows PowerShell**，进入解压后的仓库目录，执行：

   ```powershell
   .\Install.ps1 -PclPath 'D:\Games\PCL\Plain Craft Launcher 2.exe'
   ```

   把示例路径换成自己的 PCL 路径。如果 PowerShell 阻止脚本运行，可以仅为这次窗口输入 `Set-ExecutionPolicy -Scope Process Bypass`，然后重试安装命令。

安装脚本使用 Windows 自带的 C# 编译器构建后台程序，注册名为 `PCL-Memory-Optimize-Every5Minutes` 的开机任务，随后立即测试第一次后台调用。成功时，`install-result.json` 会写在源码目录；失败时会撤销本次安装，并在该文件中记录原因。

## 查看与移除

- 执行记录：`C:\ProgramData\PCLMemoryScheduler\runs.csv`。其中的 `success` 表示 PCL 正常退出；`pcl_exit_code` 是 PCL 报告的释放量，单位为 KiB。
- 程序与 PCL 副本：`C:\Program Files\PCLMemoryScheduler\`。
- 临时停止：在 Windows“任务计划程序”里找到 `PCL-Memory-Optimize-Every5Minutes`，结束并禁用该任务；需要恢复时重新启用并运行。
- 完全移除：以管理员身份在源码目录运行 `.\Uninstall.ps1`。这会移除开机任务和程序，保留执行记录。

更新 PCL 或本工具时，先运行 `.\Uninstall.ps1`，再用新的 PCL 路径运行 `.\Install.ps1 -PclPath '你的 PCL 完整路径'`。

程序在关机和睡眠期间不会优化内存，也不会补做那段时间错过的调用。单次调用超过 90 秒会停止，并在日志中记录超时。内存占用下降不保证电脑运行更快；如果没有定时清理的需求，可以不安装。

## 实现与验证

PCL 的[启动代码](https://github.com/Meloong-Git/PCL/blob/main/Plain%20Craft%20Launcher%202/Application.xaml.vb)提供 `--memory` 参数，调用内存优化后退出。本项目只调用这个参数，仓库不包含 PCL 源码或安装包。源码包括 `MemoryScheduler.cs`、`Install.ps1` 和 `Uninstall.ps1`，不需要额外下载编译工具。

2026-10-04，我在 Windows 上验证了 C# 编译、PowerShell 脚本语法，以及两次后台调用成功且相隔约 300 秒。把 PCL 可执行文件复制到独立目录后，`--memory` 入口仍可启动；未提权测试会显示 PCL 自己的管理员权限提示。仓库版本的完整安装和实际重启后的启动尚未验证。
