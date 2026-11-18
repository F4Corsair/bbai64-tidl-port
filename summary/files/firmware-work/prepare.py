#!/usr/bin/env python3
"""Create an independent SDK copy and apply the diagnostic patch. No build/SSH."""
import argparse, pathlib, shutil, subprocess, os
p=argparse.ArgumentParser()
p.add_argument('source',type=pathlib.Path)
p.add_argument('destination',type=pathlib.Path)
a=p.parse_args(); src=a.source.resolve(); dst=a.destination.resolve()
if src==dst or src in dst.parents or dst in src.parents:
    p.error('SDK source and destination must be disjoint')
if dst.exists(): p.error('destination must not exist; use a fresh variant directory')
if not (src/'vision_apps/platform/j721e/rtos/common/app_init.c').is_file():
    p.error('not the expected SDK root')
# Do not use hard links: builds must never write through to sdk_original.
shutil.copytree(src,dst,symlinks=True,ignore=shutil.ignore_patterns('.git'))
# Internal absolute links are redirected to the copy. External/broken links are
# recorded; the build wrapper rejects external links to existing destinations.
notes=[]
for base, dirs, files in os.walk(dst,followlinks=False):
    for name in dirs+files:
        q=pathlib.Path(base)/name
        if not q.is_symlink(): continue
        target=os.readlink(q)
        if os.path.isabs(target):
            try: rel=pathlib.Path(target).relative_to(src)
            except ValueError: pass
            else:
                q.unlink(); q.symlink_to(dst/rel)
        if not q.exists(): notes.append('BROKEN '+str(q.relative_to(dst)))
        elif dst not in q.resolve().parents:
            notes.append('EXTERNAL '+str(q.relative_to(dst)))
(dst/'bbai64-copy-links.txt').write_text('\n'.join(notes)+'\n')
for patch in ['0001-mcu2-0-init-trace.patch', '0002-r5-trace-cache-writeback.patch']:
    subprocess.run(['patch','--batch','--forward','-p1','-i',str(pathlib.Path(__file__).resolve().parent/patch)],cwd=dst,check=True)
(dst/'.bbai64-diagnostic-copy').write_text(str(src)+'\n')
print('Prepared',dst,'; inspect bbai64-copy-links.txt before building')
