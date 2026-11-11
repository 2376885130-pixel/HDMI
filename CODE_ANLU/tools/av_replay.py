"""Optional replay of the packaged real-content behavioral regression via WSL."""
from pathlib import Path
import subprocess,json,hashlib,time
from display_sim_top import prepare
R=Path(__file__).resolve().parents[1]
prepare(R)
converted=subprocess.check_output(['wsl','-d','Ubuntu','--','wslpath','-u',str(R)],text=True).strip()
# Arguments are passed positionally, not interpolated into a shell command.
script='cd "$1/sim" && verilator --binary --timing --top-module tb_av_content -Wno-fatal -O3 -j 6 --Mdir /tmp/code_anlu_av -f av_sources.f > ../reports/sim/av_replay_build.log 2>&1 && /tmp/code_anlu_av/Vtb_av_content > ../reports/sim/av_replay.log 2>&1'
t=time.time()
c=subprocess.run(['wsl','-d','Ubuntu','--','bash','-lc',script,'bash',converted],timeout=2400)
log=R/'reports/sim/av_replay.log'
passed=c.returncode==0 and log.exists() and 'PASS actual-volume WAV' in log.read_text()
(R/'reports/sim/av_replay.json').write_text(json.dumps({'passed':passed,'seconds':time.time()-t,'scope':'Behavioral sector/SDRAM boundaries; original volume snapshot; not a hardware test'},indent=2))
assert passed,'See reports/sim/av_replay*.log'
print('PASS real-content AV replay')
