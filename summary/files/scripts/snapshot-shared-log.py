#!/usr/bin/env python3
"""SDK J721E app_log snapshot; read-only mapping, never updates reader indices."""
import os,mmap,struct,json,sys
from pathlib import Path
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
assert os.geteuid()==0,'root required'
assert b'BeagleBone AI-64' in Path('/proc/device-tree/model').read_bytes()
addr=0xac000000;size=0x40000
# Verify a live reservation covers the exact SDK log window before /dev/mem.
found=False
for p in Path('/sys/firmware/devicetree/base/reserved-memory').glob('*/reg'):
 b=p.read_bytes()
 if len(b)!=16:continue
 ah,al,sh,sl=struct.unpack('>4I',b);a=ah<<32|al;n=sh<<32|sl
 if a<=addr and addr+size<=a+n:found=True
assert found,'live DT does not reserve SDK app log range'
fd=os.open('/dev/mem',os.O_RDONLY|os.O_SYNC)
try:
 with mmap.mmap(fd,size,flags=mmap.MAP_SHARED,prot=mmap.PROT_READ,offset=addr) as m: data=m[:]
finally:os.close(fd)
(out/'app-log.bin').write_bytes(data)
rows=[]
for cpu in range(16):
 b=data[cpu*16384:(cpu+1)*16384];rd,wr,valid,sync=struct.unpack_from('<4I',b)
 name=b[16:32].split(b'\0')[0].decode('ascii','replace');n=16352
 row=dict(slot=cpu,name=name,rd=rd,wr=wr,valid=hex(valid),sync=sync)
 rows.append(row)
 if valid==0x1357231 and rd<n and wr<n:
  ring=b[32:];pending=ring[rd:wr] if rd<=wr else ring[rd:]+ring[:wr]
  (out/f'cpu-{cpu}-pending.txt').write_text(pending.decode('utf8','replace'))
  # Retain all ring bytes even if a previous reader consumed the messages.
  (out/f'cpu-{cpu}-ring.txt').write_text((ring[wr:]+ring[:wr]).replace(b'\0',b'').decode('utf8','replace'))
(out/'app-log-index.json').write_text(json.dumps(rows,indent=2)+'\n')
print('SHARED_LOG_SNAPSHOT_OK; non-atomic snapshot, indices unchanged')
