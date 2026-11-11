from pathlib import Path
import sys,json,hashlib,re
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'tools'))
from verify import run
rows=[run('tb_uart_system'),run('tb_uart_events'),run('tb_uart_priority')]
# Port additions to historical positional benches are a mechanical adaptation.
for name in ['tb_four_control','tb_three_seconds']:
 p=R/f'sim/{name}.v';s=p.read_text()
 if name=='tb_four_control':s=s.replace('state,model);',"state,model,1'b0,1'b0);")
 else:s=s.replace('manual,timed);',"manual,timed,1'b0,2'd0);")
 q=R/f'sim/uart_{name}.v';q.write_text(s);rows.append(run(name,q))
for name in ['tb_audio_modes','tb_key1_mode','tb_basic_present','tb_wave_visible','tb_display_osd']:
 rows.append(run(name))
inputs={str(p.relative_to(R)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (R/'rtl').rglob('*') if p.is_file()}
(R/'reports/sim/uart_units.json').write_text(json.dumps(dict(tests=rows,inputs=inputs),indent=2))
