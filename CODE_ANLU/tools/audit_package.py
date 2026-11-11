"""Audit packaged inputs, ROM dependencies, original protection and final manifests."""
from pathlib import Path
import hashlib,json,xml.etree.ElementTree as ET,re
R=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
audit=json.loads((R/'reports/audit/package_inputs.json').read_text())
S=Path(audit['source'])
before=json.loads((R/'reports/audit/protected_before.json').read_text())
changed=[rel for rel,h in before.items() if not (S/rel).is_file() or sha(S/rel)!=h]
protected={'original_root':str(S),'checked_files':len(before),'unchanged':not changed,'changed':changed,'formal_project_and_E':'No writes performed by packaging or build scripts'}
(R/'reports/audit/protected_after.json').write_text(json.dumps(protected,indent=2))
assert not changed,changed
missing=[]
root=ET.fromstring((R/'prj/al/TF_IMAGE.al').read_text().replace('UsedInP&R','UsedInP&amp;R'))
for el in root.iter('File'):
    p=(R/'prj/al'/el.attrib['Path']).resolve()
    if not p.is_file() or not p.is_relative_to(R):missing.append(str(p))
different=[]
for rel in audit['byte_identical_files']:
    if not (R/rel).is_file() or sha(R/rel)!=before[rel]:different.append(rel)
for p in (R/'rtl').rglob('*.v'):
    for name in re.findall(r'\$readmem[hb]\(\s*"([^"]+)"',p.read_text(errors='replace')):
        if not (R/'prj/al'/name).is_file():missing.append(name)
for part in ['rtl','constraints','prj/al_ip','prj/al/theme_rom']:
    for p in (R/part).rglob('*'):
        if p.is_file() and (S/p.relative_to(R)).is_file():
            if sha(p)!=sha(S/p.relative_to(R)):different.append(str(p.relative_to(R)))
status={'dependency_complete':not missing,'missing':missing,'unchanged_design':not different,'different':different,'source_project_entries':len(list(root.iter('File')))}
(R/'reports/audit/completeness.json').write_text(json.dumps(status,indent=2))
assert not missing and not different,status
# Check retained historical simulation results belong to the actual packaged RTL.
for name in ['uart_units.json','av_uart_final.json']:
    record=json.loads((R/'reports/baseline/sim'/name).read_text())
    for rel,h in record['inputs'].items():
        p=R/rel.replace('\\','/')
        assert p.is_file() and sha(p)==h,(name,rel)
    assert record.get('passed',all(x['passed'] for x in record.get('tests',[])))
files={}
for p in sorted(R.rglob('*')):
    if not p.is_file():continue
    rel=p.relative_to(R).as_posix()
    if 'TF_IMAGE_Runs/' in rel or '__pycache__/' in rel or p.suffix in ['.vvp','.logw'] or p.name.startswith('td_'):continue
    if rel=='reports/audit/package_sha256.json':continue
    files[rel]=sha(p)
(R/'reports/audit/package_sha256.json').write_text(json.dumps(files,indent=2))
print(json.dumps({'protection':protected,'completeness':status,'manifest_files':len(files)},indent=2))
