from pathlib import Path
import sys,subprocess,time,re,json,hashlib,os
R=Path(__file__).resolve().parents[1]
root=R/'baseline' if '--baseline' in sys.argv else R
stage=sys.argv[1];out=root/'reports'/stage;out.mkdir(parents=True,exist_ok=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def inputs():return {str(p.relative_to(root)):sha(p) for part in ['rtl','constraints','prj/al_ip'] for p in (root/part).rglob('*') if p.is_file()}|{'prj/al/TF_IMAGE.al':sha(root/'prj/al/TF_IMAGE.al')}
if stage=='synth':
    (root/'reports/build_inputs.json').write_text(json.dumps(inputs(),indent=2))
    body='reset_runs syn_1\nlaunch_runs syn_1 -jobs 2\nwait_run syn_1\nopen_run syn_1\n'
elif stage=='route':
    (root/'reports/route_inputs.json').write_text(json.dumps(inputs(),indent=2))
    seed=int(sys.argv[sys.argv.index('--seed')+1]) if '--seed' in sys.argv else None
    body='reset_runs phy_1\n'
    if seed is not None:body+=f'set_param place seed {seed} -run phy_1\nget_param place seed -run phy_1\n'
    body+='launch_runs phy_1 -step route -jobs 2\nwait_run phy_1\nopen_run phy_1\nset_param place hold_fix high\nfix_hold -clock_opt -eco\nupdate_timing -mode final\n'
    body+='report_timing_status -file ../../reports/route/final_timing.rpt\nreport_timing_summary -file ../../reports/route/timing_summary.rpt\nreport_timing_exception -file ../../reports/route/timing_exceptions.rpt\nreport_route_status -drc -file ../../reports/route/route_drc.rpt\nexport_db ../../reports/route/final.db\n'
else:raise ValueError(stage)
body+=f'report_area -io_info -file ../../reports/{stage}/area.rpt\n'
if stage=='synth':body+='write_verilog ../../reports/synth/netlist.v\n'
tcl=root/'prj/al'/f'{stage}.tcl'
tcl.write_text('cd [file dirname [file normalize [info script]]]\nimport_device eagle_s20.db -package EG4S20BG256\nopen_project TF_IMAGE.al\n'+body+'puts {REBASE_STAGE_COMPLETE}\nexit\n')
t=time.time()
with (out/'console.log').open('w') as f:
    c=subprocess.run([os.environ.get('TD_COMMANDS','D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'),tcl.name],cwd=tcl.parent,stdout=f,stderr=subprocess.STDOUT,timeout=3600)
log=(out/'console.log').read_text(errors='replace');passed=c.returncode==0 and 'REBASE_STAGE_COMPLETE' in log
a=(out/'area.rpt').read_text(errors='replace') if passed and (out/'area.rpt').exists() and (out/'area.rpt').stat().st_mtime>=t else ''
area={k:int(m[1]) for k in ['lut','reg','bram9k','bram32k','dsp'] if (m:=re.search(r'^\s*#'+k+r'\s+(\d+)',a,re.M))}
status={'root':str(root),'stage':stage,'completed':passed,'seconds':time.time()-t,'resources':area,'returncode':c.returncode}
if stage=='route':status['placement_seed_override']=seed
if stage=='route' and passed and (out/'final_timing.rpt').exists() and (out/'final_timing.rpt').stat().st_mtime>=t:
    timing=(out/'final_timing.rpt').read_text()
    status['timing']={k:float(re.search(k+r':\s*(-?[\d.]+)ns',timing)[1]) for k in ['SWNS','STNS','HWNS','HTNS']}
    status['timing_pass']=min(status['timing'].values())>=0
(out/'status.json').write_text(json.dumps(status,indent=2));print(json.dumps(status),flush=True)
assert passed,status
