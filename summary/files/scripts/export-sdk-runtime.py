#!/usr/bin/env python3
"""Extract selected runtime/unsigned firmware from the exact SDK rootfs archive."""
import csv,hashlib,tarfile,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1];archive=Path(sys.argv[1]);wanted={}
for row in csv.DictReader((root/'staging/manifests/components.tsv').open(),delimiter='\t'):
 dst=row['staged'];src=row['source']
 if '::' not in src or not (dst.startswith('staging/lib/') or dst.startswith('staging/firmware/')):continue
 if dst.endswith('.signed'):continue
 wanted[src.split('::',1)[1]]=(dst,row)
with tarfile.open(archive,'r|xz') as t:
 for m in t:
  name=m.name.removeprefix('./')
  if name not in wanted:continue
  dst,row=wanted.pop(name);p=root/dst;p.parent.mkdir(parents=True,exist_ok=True)
  if p.exists() or p.is_symlink():raise RuntimeError('Destination exists: '+str(p))
  if m.issym():
   target=row['link'];assert target and '/' not in target;p.symlink_to(target)
  elif m.isfile():
   data=t.extractfile(m).read();assert hashlib.sha256(data).hexdigest()==row['sha256'],name;p.write_bytes(data)
  else:raise RuntimeError('Unsupported archive member: '+name)
assert not wanted, list(wanted)
print('SDK runtime/unsigned firmware exported and hashes verified')
