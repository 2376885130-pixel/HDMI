"""Clean TD rebuild, review, resource/timing gates and separate candidate bit."""
from pathlib import Path
import os,sys,subprocess,json,hashlib
R=Path(__file__).resolve().parents[1]
TD=os.environ.get('TD_COMMANDS','D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe')
def td(name,marker,log):
    with (R/log).open('w') as f:
        c=subprocess.run([TD,name],cwd=R/'prj/al',stdout=f,stderr=subprocess.STDOUT,timeout=3600)
    text=(R/log).read_text(errors='replace')
    assert c.returncode==0 and marker in text,(name,text[-2500:])
if '--finish-only' not in sys.argv:
    subprocess.run([sys.executable,str(R/'tools/td_build.py'),'synth'],cwd=R,check=True)
    subprocess.run([sys.executable,str(R/'tools/td_build.py'),'route','--seed','12'],cwd=R,check=True)
route=json.loads((R/'reports/route/status.json').read_text())
assert route['completed'] and route['timing_pass'],route
td('review_uart.tcl','UART_REVIEW_COMPLETE','reports/review/console.log')
td('emit_uart.tcl','UART_BIT_COMPLETE','reports/candidate/bitgen.log')
new=R/'prj/bitstream/TF_IMAGE_CODE_ANLU_REBUILD.bit'
old=R/'release/validated/TF_IMAGE_DUAL_HDMI_UART_20261019.bit'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
baseline=json.loads((R/'reports/baseline/candidate/release.json').read_text())
report=dict(resources=route['resources'],timing=route['timing'],
    resources_identical=route['resources']==baseline['resources'],
    timing_identical=route['timing']==baseline['timing'],
    original_sha256=sha(old),rebuilt_sha256=sha(new),bit_identical=sha(old)==sha(new),
    original_hardware_validated=True,rebuilt_hardware_validated=False)
(R/'reports/candidate/comparison.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
