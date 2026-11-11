from pathlib import Path
import hashlib,json,difflib
def prepare(R):
 p=R/'rtl/tf_image_top.v';original=p.read_text();s=original
 changes=[('key1_mode_control u_key1','key1_mode_control #(.POR_CYCLES(16),.FILTER(8),.LONG_CYCLES(200)) u_key1'),
 ('p_rover_control u_rover_control','p_rover_control #(.FILTER(8),.SETTLE(32)) u_rover_control'),
 ('theme_control u_theme','theme_control #(.CLOCK_HZ(1000),.DEBOUNCE(8)) u_theme'),
 ('tf_startup_control u_startup','tf_startup_control #(.POWER_WAIT_CYCLES(64)) u_startup')]
 for a,b in changes:
  assert s.count(a)==1,(a,s.count(a));s=s.replace(a,b)
 q=R/'sim/tf_image_top_timers.v';q.write_text(s)
 undo=s
 for a,b in changes:undo=undo.replace(b,a)
 assert undo==original
 sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 (R/'reports/review/sim_top.json').write_text(json.dumps(dict(source_sha256=sha(p),simulation_sha256=sha(q),only_timer_parameters_changed=True),indent=2))
 (R/'reports/review/sim_top.diff').write_text(''.join(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='rtl/tf_image_top.v',tofile='sim/tf_image_top_timers.v')))
if __name__=='__main__':prepare(Path(__file__).resolve().parents[1])
