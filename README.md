# MEOW BEAT · 3D节拍拆迁王

Godot 4.7.2制作的网页节奏破坏小游戏。当前默认是真正3D的「午夜百货」：整局在同一座切角商场内砸家具、扇卡通人物、收战利品，镜头不追随、不切换房间。MeshInstance3D实体、Camera3D和RigidBody3D物理碎片都在独立3D世界运行。

**空格砸亮的目标，按住再松开重砸。** 角色自动靠近，零钱沿弧线自动收来。也可用J、鼠标或触屏；点具体物件会通过3D射线选中并砸它，无需额外走位、瞄准或追钱。

开场听四下木块声。看商场画面下方的节拍圈，外圈和内圈重合、亮起时点按出手，蓄力时在同一时机松开。提前一点按会显示“准备好了”，到拍再出手。窗口之外仍能砸，节拍圈旁会提示偏早或偏晚。商场里的脚下光圈用来标记当前目标。跳过可选半拍也能维持连拍。

商场里有电视、沙发、办公桌、显示器、街机、售货机、货架、盆栽和大保险柜。命中后局部掉件，砸碎后原模型部件变成带碰撞的三维碎块，落地保留；货架、柜子和保险柜半血会露出可继续砸的现金盒。现金盒不会无限生成。大件留有足够耐久，场景不会整局只剩空地。

催加班经理、插队大叔、开会达人是夸张卡通角色，选中后同一个按键自动改成扇巴掌：短脆“啪”声、歪头、转圈和手掌动画，没有血腥表现。不引入第二套操作。

## 节奏与音乐

120BPM，2秒准备、48秒游玩、2秒尾音；96正拍加6个可选半拍，共102个砸点。宽松节拍前后150ms，精准前后110ms。按下先轻砸，保持至少0.28秒松开追加重砸，任意拍可蓄力。拍外也能砸，准拍更强，连续四拍和重砸能触发连锁。没有血量失败。

原创《拆掉这夜晚》有24小节，经过主歌、funk切分贝斯、break、drop、旋律抬升和终段鼓花。短木块提示音标记正拍，每小节第一拍更亮。提示音、伴奏和双响应轨同步启动，玩家的准拍打击补出旋律。

ESC暂停，Enter开始/继续，切后台自动暂停音乐、钱币和碎片；暂停取消未释放蓄力，恢复后重新按住。结算前自动结清尚在飞来的钱币。

## 试玩与比赛包

克隆或完整解压 GitHub 的源码 ZIP 后，用 Chrome／Edge 打开根目录的 `index.html` 即可离线试玩。仓库中的 `preview/` 包含所需的完整网页试玩版。开发者要玩自己刚导出的版本，可以打开 `build/web/index.html` 或双击 `开始游戏.cmd`。

比赛包是构建生成的 `dist/MeowBeat-Web.zip`。解压后根目录含 `index.html`，可以离线运行，也可以把包内文件部署到静态网站。

压缩和解压均由构建脚本强制小于200,000,000字节，大小和SHA256见dist/manifest.json。规则参考BadmintonAce已有交付约束，未获得完整官方比赛规则。

## 克隆与协同开发

```sh
git clone https://github.com/twogold-design/MusicGame.git
cd MusicGame
```

用 **Godot 4.7.2** 导入根目录的 `project.godot`，按 F6 运行打开的场景，或按 F5 运行项目。运行所需的美术、字体、音乐、音效和谱面都随仓库提供。

Windows 下可双击 `打开Godot编辑器.cmd`。若 `godot` 不在 PATH，可在本次 PowerShell 会话设置 `GODOT_BIN` 为本机可执行文件的绝对路径。项目脚本把缓存和存档放在仓库的 `.runtime/` 中。

网页导出需要 Node.js 18+ 及与 Godot 版本匹配的 Web 模板。用项目启动脚本打开编辑器后安装对应的导出模板，或把 `GODOT_WEB_TEMPLATE` 指向已解包的 `web_nothreads_release.zip`，再从项目根目录运行以下命令。

```powershell
.\tools\build.ps1
```

需要刷新随仓库发布的试玩版时，运行 `./tools/build.ps1 -UpdatePreview` 并提交 `preview/` 的改动。

协作时从 `main` 创建功能分支，通过 Pull Request 合并。提交源码、场景、素材，以及对应的 Godot `.uid` 和 `.import` 文件。常规构建输出、缓存、本地存档和浏览器测试产物由各自的环境生成。

## 源码与验证

scripts/rhythm_wreck3d.gd：单场景3D世界、破坏、刚体、钱币、卡通人物、UI和新音乐接入。scripts/wreck3d_art.gd：程序化实体家具、猫咪锤手与可动Head/Hammer。父类保留公共输入、音频及轻砸/蓄力处理。assets/audio/wreck3d和tools/generate_wreck3d_audio.cjs是新配乐；demolition目录包含材质与巴掌短音。

测试说明见 `docs/3D商场验证.md`。`tools/test_wreck3d.gd` 验证场景与物理，`tools/test_wreck3d_audio.gd` 检查混音和节拍提示。测试报告会写到 `artifacts/`。

Windows 上运行当前网页测试时，先构建，再执行以下命令。测试默认使用系统 Chrome，可用 `CHROME_BIN` 指定本机 Chrome 路径。

```powershell
. .\tools\environment.ps1
npm --prefix tools ci
Expand-Archive -LiteralPath .\dist\MeowBeat-Web.zip -DestinationPath .\.runtime\wreck3d-package -Force
npm --prefix tools run test:web
```

打开Godot编辑器.cmd用于修改，重新导出网页版.cmd负责导入、导出、离线处理和打包。旧经典四轨和节拍冒险仍在其他模式。此前2D玩法源码和验证文档保留供历史参考，不代表当前规则。

音乐、美术和谱面为本项目制作。Godot MIT见docs/GODOT-LICENSE.txt，Noto Sans SC字体SIL OFL见assets/fonts/FONT-LICENSE.txt。
