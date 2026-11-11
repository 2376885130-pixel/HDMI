# 星衡双屏航天科普系统 · 完赛代码提交包

唯一代码基线：`FPGA_DUAL_HDMI_UART_20261019`，对应用户已经确认全部功能正常的 UART bit。目标器件 EG4S20BG256；工具 TD 6.2.168116。

## 打开与构建

TD 打开 `prj/al/TF_IMAGE.al`，顶层为 `tf_image_top`。工程文件、IP、约束和 ROM 均使用包内路径。**运行脚本时不要移动单个子目录**；整包可迁移，推荐英文无空格路径。

在本目录执行：

```powershell
python tools/uart_tests.py
python tools/build_release.py
```

完整构建依次执行清空综合运行、综合、seed 12 布局布线、hold ECO、final STA、约束检查与 UART 路径复核、资源/时序门槛、bit 生成。不复用原工程构建缓存；遇到失败立即停止。重复发布前请另建空的输出副本，脚本拒绝覆盖已有候选 bit。

默认 TD：`D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe`；可用环境变量 `TD_COMMANDS` 指定。仿真需要 Python 3、Icarus Verilog，默认工具目录 `D:/Downloads/IVERILOG/bin`，可用 `IVERILOG_BIN` 指定。TD 安装设备库及授权不包含在提交包内。

## 目录与分层

|目录|内容|
|---|---|
|`rtl/`|可综合设计，顶层及主屏各子系统；逐文件层次见 `docs/MODULE_INDEX.md`|
|`rtl/audio/`、`rtl/hdmi_audio/`、`rtl/integration/`|WAV/PCM、HDMI 音频封包及音视频接口|
|`rtl/eval/`|四主题共用的二维扫描副屏与统一交互控制，非完整 3D 引擎|
|`rtl/board/`、`rtl/vendor/`|板级视频物理层、原第三方/厂商依赖，含加密文件|
|`rtl/theme_rom/`、`prj/al/theme_rom/`|源码侧资源与 TD 工作目录初始化副本，均保留原内容|
|`constraints/`、`prj/al_ip/`|原引脚/时序约束、PLL IP 及配置|
|`prj/al/`|唯一 TD 工程入口和可重复执行的 Tcl|
|`media/`|完赛工程随附的图片、WAV、字幕及素材清单；本次未访问或修改 E 盘|
|`sim/`、`tools/`|当前版本测试台、行为模型、仿真数据及构建/审计工具|
|`release/validated/`|原上板通过 bit 的原字节副本|
|`prj/bitstream/`|从本提交包重新构建的 bit，与原发布文件分开|
|`reports/baseline/`|原版本的资源、时序、仿真和发布证据，只作对照|
|`reports/synth/`、`reports/route/`、`reports/review/`|本目录重新构建的日志与检查|
|`reports/audit/`、`reports/candidate/`|保护哈希、依赖完整性、最终构建比较和打包清单|

源码按原依赖目录保存，并用索引实现功能分层；没有为了目录外观重命名 RTL、修改 include 或调整工程编译顺序。未拷入原工程构建缓存、失败候选或面积研究分支。`TF_IMAGE_Runs` 为本次构建新产生的输出，上传时可按 `docs/提交说明.md` 排除。

## 操作与验证

按键、双屏、基础/进阶、音画、三秒快览均保持完赛版实现。UART 为 115200、8N1、ASCII+实际 CRLF；`T1`～`T4` 仅首页选主题，长按 KEY3 进入；`M1` 主题内进入演示，`M0` 退出。详见 `docs/UART使用说明.md`。

整理过程没有修改任何可综合 RTL、媒体、时钟、引脚或时序约束。工程文件仅将绝对目录改为本地目录，并把遗留 UserParams seed 5 对齐到原发布构建实际使用的 seed 12。

原 bit 已由用户上板验证；重新构建 bit 的验证范围应以 `reports/candidate/comparison.json` 和 `docs/构建核验结果.md` 为准。原报告中“待实机验收”是历史记录，不代表当前用户尚未验收原 bit。不要将历史仿真或新构建时序结果说成新 bit 的实机测试。

可选真实素材并发回放：`python tools/av_replay.py`。需要 WSL Ubuntu 和 Verilator，读取包内历史实卡扇区快照，不访问 E 盘；日志写入 `reports/sim/av_replay*`。该回放保留原行为模型边界，不能替代实板。默认十项单元回归与历史音画回归均有逐文件 RTL 哈希可追溯。

打包核验：`python tools/audit_package.py`。默认会对本机原始源目录执行只读保护核对；迁移到其他电脑后，原目录可能不存在，此时应使用已保存的审计报告与 SHA-256 清单核对提交文件，不将其误判为 RTL 构建依赖。
