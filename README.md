# 商场拆迁王 · 午夜百货

Godot 4.7.2 制作的 3D 网页解压小游戏。自由打砸在同一座商场内进行，砸开的墙洞和落地的碎片都留在场景里。想砸多久都可以，点右上角的「收工」结算。

- 点击物件或卡通角色直接出手。空格和 J 会攻击高亮目标，主角自动靠近。
- 按住约 0.3 秒再松开会追加重击，约 0.75 秒蓄满。目标旁的进度条显示蓄力进度。重锤也能把落地的碎片再震飞。
- 售货机炸出彩色汽水罐，砸坏街机能撞到相邻机器，货架和保险柜可能翻出可继续砸的现金盒。钱币自动拾取。
- 点三位卡通角色会自动扇巴掌。蓄力能让经理打转、大叔蹦一下、开会达人手忙脚乱。
- 循环配乐独立播放。ESC 暂停，Enter 开始或继续。切后台会自动暂停，暂停会取消当前蓄力。

## 试玩与比赛包

克隆或完整解压 GitHub 的源码 ZIP 后，用 Chrome／Edge 打开根目录的 `index.html` 即可离线试玩。仓库中的 `preview/` 包含所需的完整网页试玩版。开发者要玩自己刚导出的版本，可以打开 `build/web/index.html` 或双击 `开始游戏.cmd`。

比赛包是构建生成的 `dist/MeowBeat-Web.zip`。解压后根目录含 `index.html`，可以离线运行，也可以把包内文件部署到静态网站。

压缩和解压均由构建脚本强制小于200,000,000字节，大小和SHA256见dist/manifest.json。规则参考BadmintonAce已有交付约束，未获得完整官方比赛规则。

## 克隆与协同开发

```sh
git clone https://github.com/twogold-design/MusicGame.git
cd MusicGame
```

用 **Godot 4.7.2** 导入根目录的 `project.godot`，按 F6 运行打开的场景，或按 F5 运行项目。运行所需的美术、字体、音乐和音效都随仓库提供。

Windows 下可双击 `打开Godot编辑器.cmd`。若 `godot` 不在 PATH，可在本次 PowerShell 会话设置 `GODOT_BIN` 为本机可执行文件的绝对路径。项目脚本把缓存和存档放在仓库的 `.runtime/` 中。

网页导出需要 Node.js 18+ 及与 Godot 版本匹配的 Web 模板。用项目启动脚本打开编辑器后安装对应的导出模板，或把 `GODOT_WEB_TEMPLATE` 指向已解包的 `web_nothreads_release.zip`，再从项目根目录运行以下命令。

```powershell
.\tools\build.ps1
```

需要刷新随仓库发布的试玩版时，运行 `./tools/build.ps1 -UpdatePreview` 并提交 `preview/` 的改动。

协作时从 `main` 创建功能分支，通过 Pull Request 合并。提交源码、场景、素材，以及对应的 Godot `.uid` 和 `.import` 文件。常规构建输出、缓存、本地存档和浏览器测试产物由各自的环境生成。

## 源码与验证

scripts/rhythm_wreck3d.gd：单场景 3D 世界、自由打砸、碎片、钱币、卡通角色和界面。scripts/wreck3d_art.gd 提供家具和角色的程序化模型。配乐在 assets/audio/wreck3d，材质和巴掌音效在 assets/audio/demolition。

测试说明见 `docs/3D商场验证.md`。`tools/test_wreck3d.gd` 验证场景与物理，`tools/test_wreck3d_audio.gd` 检查音乐循环和音效。网页测试截图位于 `artifacts/`。

Windows 上运行当前网页测试时，先构建，再执行以下命令。测试默认使用系统 Chrome，可用 `CHROME_BIN` 指定本机 Chrome 路径。

```powershell
. .\tools\environment.ps1
npm --prefix tools ci
Expand-Archive -LiteralPath .\dist\MeowBeat-Web.zip -DestinationPath .\.runtime\wreck3d-package -Force
npm --prefix tools run test:web
```

打开Godot编辑器.cmd用于修改，重新导出网页版.cmd负责导入、导出、离线处理和打包。此前2D玩法源码和验证文档保留供历史参考。

音乐和美术为本项目制作。Godot MIT见docs/GODOT-LICENSE.txt，Noto Sans SC字体SIL OFL见assets/fonts/FONT-LICENSE.txt。
