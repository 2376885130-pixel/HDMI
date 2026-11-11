from pathlib import Path
import json,re,hashlib
R=Path(__file__).resolve().parents[1]
load=lambda p:json.loads((R/p).read_text())
c=load('reports/candidate/comparison.json')
s=load('reports/synth/status.json')
b=load('reports/baseline/synth/status.json')
route=load('reports/route/status.json')
original=load('reports/baseline/candidate/release.json')
rows=[]
for label,key in [('LUT','lut'),('FF','reg'),('BRAM9K','bram9k'),('BRAM32K','bram32k'),('DSP','dsp')]:
    rows.append(f'|布线后 {label}|{original["resources"][key]}|{c["resources"][key]}|')
for key in ['SWNS','STNS','HWNS','HTNS']:
    rows.append(f'|{key} (ns)|{original["timing"][key]:+.3f}|{c["timing"][key]:+.3f}|')
pattern=r'^\d+\. checking .+\(\d+\).*$'
old=re.findall(pattern,(R/'reports/baseline/review/check_timing.rpt').read_text(),re.M)
new=re.findall(pattern,(R/'reports/review/check_timing.rpt').read_text(),re.M)
coverage={'baseline':old,'rebuilt':new,'identical':old==new}
(R/'reports/review/coverage_compare.json').write_text(json.dumps(coverage,indent=2))
text='''# 整理与重建核验结果

基线为用户明确确认全部功能正常的 UART 完赛工程；本次在 D:/CODE_ANLU 独立整理，未修改可综合 RTL、IP、约束、ROM 或素材。原正式工程及 E 盘未写入。

## 依赖及保护

118 项 TD 工程引用及 11 处 ROM 初始化引用在包内可解析。原始保护范围为 RTL、约束、IP、TD 初始化 ROM、工程素材、工程文件和发布 bit，共 249 项；核验见 reports/audit/protected_after.json。功能分层见 docs/MODULE_INDEX.md。

工程元数据仅将项目绝对路径改为本地路径，并把 UserParams 内遗留 seed 5 对齐为原成功发布实际显式使用的 seed 12。编译顺序、器件、约束例外和实现策略保留。

## 本目录重新构建

从空的运行缓存开始，完成综合、seed 12 完整布局布线、hold ECO、final STA、DRC、时钟约束覆盖检查、UART 实际控制路径 setup/hold 报告及 bitgen。原 routed DB 没有作为新构建输入。

|指标|原完赛版|本目录重建|
|---|---:|---:|
'''+ '\n'.join(rows)+'\n\n'
text+=f'综合资源是否一致：{s["resources"]==b["resources"]}；布线资源是否一致：{c["resources_identical"]}；最终时序是否一致：{c["timing_identical"]}。\n\n'
text+='## bit 对比\n\n'
text+=f'- 原上板 bit SHA-256：`{c["original_sha256"]}`\n- 新构建 bit SHA-256：`{c["rebuilt_sha256"]}`\n- 两者是否逐字节一致：{c["bit_identical"]}。\n\n'
text+='原上板文件原样保存于 release/validated；新文件位于 prj/bitstream/TF_IMAGE_CODE_ANLU_REBUILD.bit。新文件未单独上板，不能把工具通过等同于实机验收。\n\n'
detail_path=R/'reports/candidate/bit_comparison_detail.json'
if detail_path.exists() and json.loads(detail_path.read_text()).get('identical_except_date_comment'):
    text+='逐字节进一步核对：仅 ASCII 文件头 `# Date:` 生成日期注释内 5 个字节不同。仅移除这整行注释后，两份完整文件逐字节相同，包括配置内容和 CRC；并非重新宣称原始文件 SHA-256 相同。见 reports/candidate/bit_comparison_detail.json。\n\n'
text+='## 仿真与覆盖边界\n\n本目录重新运行 10 项针对性测试，全部通过。保留原真实素材并发仿真及输入哈希，逐一核对对应当前 RTL；本次整理未重复运行耗时的实卡素材行为仿真，提供 tools/av_replay.py 供复现。历史仿真覆盖、模型边界和用户实机验收是不同证据，不互相替代。\n\n'
text+=f'check_timing 条目计数与原版一致：{coverage["identical"]}。'
text+='仍有原版的 dummy node 4 项、PLL/clock buffer 2 项、无输入延迟 10 项、无输出延迟 29 项；无时钟、无效约束、组合环、忽略/覆盖时序例外均为 0。不宣称全部板外 IO 时序已由 STA 覆盖；本次未放宽约束。\n\n'
text+='布线 DRC 无多驱动、无异常时序路径，仍提示原 SDRAM_CLK 有 1 路标记为局部布线资源的时钟网络；保留该警告，未隐藏。DRC 摘录在 reports/route/route_drc.rpt，完整输出在 console.log。\n\n'
text+='提交时可排除新产生的 TF_IMAGE_Runs、VVP、DB 和综合网表缓存；源码和文本核验报告保留。详见 docs/提交说明.md。\n'
(R/'docs/构建核验结果.md').write_text(text,encoding='utf-8')
print(json.dumps({'resource_match':c['resources_identical'],'timing_match':c['timing_identical'],'coverage_match':coverage['identical'],'bit_match':c['bit_identical']},indent=2))
