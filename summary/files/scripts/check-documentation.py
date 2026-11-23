#!/usr/bin/env python3
"""Validate bilingual document pairs, language routing, and local Markdown anchors."""
from pathlib import Path
import json,os,re,subprocess,urllib.parse
root=Path(__file__).resolve().parents[3]
pairs=json.loads((root/'summary/files/documentation-map.json').read_text())
langs={root/item[lang]:lang for item in pairs for lang in ('ko','en')}
errors=[];assets=[];links=0
for p,lang in langs.items():
 if not p.is_file():errors.append(f'Missing document: {p}');continue
 s=p.read_text()
 if p.parent==root and not s.startswith('| English | 한국어 |\n'):
  errors.append(f'Missing leading language table: {p.name}')
 for url in re.findall(r'\]\(([^)]+)\)',s):
  if '://' in url or url.startswith('mailto:'):continue
  path,sep,frag=url.partition('#');path=urllib.parse.unquote(path)
  q=(p.parent/path).resolve() if path else p
  # Source-line suffixes are workspace navigation links, not literal filenames.
  q=Path(re.sub(r':\d+$','',str(q)))
  if q.suffix=='.md':
   links+=1
   if not q.is_file():errors.append(f'Broken Markdown link: {p.relative_to(root)} → {url}');continue
   if q in langs and langs[q]!=lang:
    if not (p.parent==root and q.parent==root and p.name.startswith('README') and q.name.startswith('README')):
     errors.append(f'Cross-language link: {p.relative_to(root)} → {url}')
   if sep:
    if f'id="{urllib.parse.unquote(frag)}"' not in q.read_text():errors.append(f'Missing explicit anchor: {p.relative_to(root)} → {url}')
  elif not q.exists():assets.append(f'{p.relative_to(root)} → {url}')
 for b in re.findall(r'^```bash\n(.*?)^```',s,re.M|re.S):
  r=subprocess.run(['bash','-n'],input=b,text=True,capture_output=True)
  if r.returncode:errors.append(f'Shell syntax: {p.relative_to(root)}: {r.stderr.strip()}')
print(f'Document pairs: {len(pairs)}; local Markdown links: {links}; errors: {len(errors)}')
for e in errors:print('ERROR',e)
print(f'Unresolved non-Markdown workspace links: {len(assets)} (SDK/build/log files may be excluded from Git)')
for a in sorted(set(assets)):print('ASSET',a)
raise SystemExit(bool(errors))
