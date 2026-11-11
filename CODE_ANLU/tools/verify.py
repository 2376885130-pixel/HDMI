"""Portable unit-test helper; does not change synthesizable RTL."""
from pathlib import Path
import os, subprocess
R=Path(__file__).resolve().parents[1]
I=Path(os.environ.get('IVERILOG_BIN','D:/Downloads/IVERILOG/bin'))
O=R/'reports/sim';O.mkdir(parents=True,exist_ok=True)
sources=[p for p in (R/'rtl').rglob('*.v') if 'vendor' not in p.parts]
def run(name,tb=None,extra=(),timeout=240):
    tb=tb or R/'sim'/f'{name}.v'
    out=O/(name+'.vvp')
    c=subprocess.run([str(I/'iverilog.exe'),'-g2012','-s',name,'-o',str(out),*map(str,sources),*map(str,extra),str(tb)],capture_output=True,text=True)
    (O/(name+'.compile.log')).write_text(c.stdout+c.stderr)
    if c.returncode:raise RuntimeError(c.stderr)
    c=subprocess.run([str(I/'vvp.exe'),str(out)],cwd=R/'sim',capture_output=True,text=True,timeout=timeout)
    (O/(name+'.log')).write_text(c.stdout+c.stderr)
    ok=c.returncode==0 and 'PASS' in c.stdout and 'FATAL' not in c.stdout
    print(name,'PASS' if ok else 'FAIL',c.stdout.strip(),flush=True)
    assert ok,(c.stdout,c.stderr)
    return dict(test=name,passed=ok)
