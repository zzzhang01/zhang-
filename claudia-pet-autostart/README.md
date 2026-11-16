# Claudia 桌宠：跟着 Claude 一起开、一起关

## 安装（只需做一次）

1. 把这个文件夹里的 4 个文件复制到 `E:\claudia-pet`（和 `claudia-pet.exe` 放在一起）：
   - `claudia-watcher.ps1`
   - `claudia-watcher.vbs`
   - `install.bat`
   - `uninstall.bat`
2. 双击 `install.bat`，看到 `[OK] Installed.` 就装好了。

之后每次开机，监视器都会在后台悄悄运行（不会弹出窗口）：

- **Claude 打开** → 桌宠自动出现
- **Claude 关闭** → 桌宠自动退出（大约 6 秒内）
- Claude 开着的时候，如果你手动关掉桌宠，它不会再自己跳出来，下次打开 Claude 才会出现。

## 卸载

双击 `uninstall.bat`。

## 可以改的设置

用记事本打开 `claudia-watcher.ps1`，最上面有几项设置：

| 设置 | 说明 |
| --- | --- |
| `$Target = 'both'` | 跟随哪个 Claude：`'both'` 两个都算，`'desktop'` 只跟 Claude 桌面版，`'code'` 只跟 Claude Code（命令行） |
| `$Interval = 3` | 每隔几秒检查一次 |
| `$DefaultPetDir` | 桌宠所在的文件夹，默认是 `E:\claudia-pet` |

改完以后重新双击一次 `install.bat` 就会生效。

## 注意

- Claude 桌面版点右上角 ✕ 有时只是缩到右下角托盘，并没有真正退出，这时桌宠也会继续开着。要在托盘图标上右键选择 “Quit/退出” 才算真正关闭。
- 如果 Windows 提示脚本被阻止，在 `.ps1` 文件上右键 → 属性 → 勾选“解除锁定”，再重新运行 `install.bat`。
