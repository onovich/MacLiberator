# MacLiberator

MacLiberator 是一个面向 macOS 本地使用的修复脚本，目标是帮助用户快速排查“非 App Store 下载的 App 无法打开”这类常见问题，避免手动一条一条试命令。

## 这份项目在解决什么问题

macOS 对第三方应用的限制比较严格。用户下载 App 之后，常见报错通常集中在两类：

1. 提示“文件已损坏，无法打开”
2. 提示“您没有权限打开应用”或者“应用程序不能打开”

这些问题背后通常是几类原因：

- App 被打上了 quarantine 隔离属性
- App 的签名状态不满足系统检查
- App 包内真正的可执行文件缺少执行权限
- 系统级 Gatekeeper 安全策略阻止了启动

原始经验里会按系统版本分别给命令，但实践上并不总要严格区分版本。更有效的方式通常是按风险从低到高逐步尝试，哪个方案先生效，就停在那一步。

## 当前方案

项目根目录中的 [MacLiberator.command](MacLiberator.command) 是双击可运行的入口脚本。

它会按下面的顺序尝试修复：

1. 自动定位 App 包内主执行文件，并执行 chmod +x
2. 检查并移除 com.apple.quarantine
3. 对 App 执行 codesign --force --deep --sign -
4. 只有前面都不行时，才提示是否执行 sudo spctl --master-disable

脚本每一步之后都会停一下，让用户自己重新尝试打开 App；如果已经成功，就可以直接结束，不再继续后面的步骤。

## 为什么不是彻底一键全自动

这个项目不适合做成完全黑盒的一键脚本，原因很简单：

- 前三步是文件级修复，影响局部
- 关闭 Gatekeeper 是系统级修改，影响整个系统的安全策略
- 所有 sudo 步骤都需要用户明确授权

所以更合理的产品形态不是“静默全试一遍”，而是“自动串行尝试 + 高风险步骤单独确认”。

## 使用方式

1. 双击运行 [MacLiberator.command](MacLiberator.command)
2. 把目标 .app 拖进终端窗口，或者直接输入路径
3. 按提示逐步执行
4. 每一步执行后，先尝试重新打开 App
5. 如果已经成功，输入 y 提前结束

脚本会在项目目录生成 macliberator.log，用来记录执行结果。

## 风险说明

- sudo xattr 和 sudo codesign 会请求管理员密码
- sudo spctl --master-disable 会关闭 Gatekeeper，仅建议作为最后手段
- 如果执行了 spctl --master-disable，恢复命令是：

```bash
sudo spctl --master-enable
```

## 手动方案附录

如果你不想使用脚本，也可以手动执行原始命令。

### 1. 提示“文件已损坏，无法打开”

先尝试移除 quarantine：

```bash
sudo xattr -rd com.apple.quarantine 文件路径
```

如果无效，再尝试重新签名：

```bash
sudo codesign --force --deep --sign - 文件路径
```

如果仍然无效，最后再考虑关闭 Gatekeeper：

```bash
sudo spctl --master-disable
```

### 2. 提示“您没有权限打开应用”或“应用程序不能打开”

右键 App，点“显示包内容”，进入 Contents/MacOS，找到真正的执行文件后执行：

```bash
chmod +x 执行文件路径
```

### 3. 通用建议

打不开时，不要只试左键双击，也请尝试右键后点“打开”。