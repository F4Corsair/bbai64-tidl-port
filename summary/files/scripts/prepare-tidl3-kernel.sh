#!/usr/bin/env bash
# Prepare only. Does not run make, install dependencies, or contact the board.
set -euo pipefail
package=$(cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$package/kernel-work/linux"
[[ -d $source_dir/.git ]] || { echo '기존 r47 kernel-work/linux 소스가 필요합니다.' >&2; exit 1; }
[[ $(git -C "$source_dir" rev-parse HEAD) == c03783811916b255c974912b3fd2eceb30fa8146 ]] || { echo '기준 커밋 불일치' >&2; exit 1; }
# Earlier patches overlap; verify their combined result rather than reversing
# each patch separately against the final tree.
python3 - "$package" "$source_dir" <<'PYCODE'
import pathlib,subprocess,tempfile,sys,re
package,source=map(pathlib.Path,sys.argv[1:])
patches=sorted((package/'patches').glob('000[123]-*.patch'))
assert len(patches)==3
paths=set()
for p in patches:
 paths.update(re.findall(r'^\+\+\+ b/(.+)$',p.read_text(),re.M))
with tempfile.TemporaryDirectory(prefix='tidl3-check-') as t:
 t=pathlib.Path(t)
 for rel in paths:
  r=subprocess.run(['git','-C',str(source),'show','HEAD:'+rel],capture_output=True)
  if r.returncode==0:
   q=t/rel;q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(r.stdout)
 for p in patches:
  subprocess.run(['git','apply','--unsafe-paths',str(p)],cwd=t,check=True)
 for rel in paths:
  assert (t/rel).read_bytes()==(source/rel).read_bytes(), 'Existing DMA source differs: '+rel
print('0001–0003 combined source: PASS')
PYCODE
patch="$package/patches/0004-rpmsg-char-report-bound-local-endpoint-address.patch"
if git -C "$source_dir" apply --reverse --check "$patch" 2>/dev/null; then
 echo '0004 패치가 이미 적용돼 있습니다.'
else
 git -C "$source_dir" apply --check "$patch"
 git -C "$source_dir" apply "$patch"
fi
git -C "$source_dir" diff --check
output="$package/kernel-work/out-tidl3"
[[ ! -e $output ]] || { echo 'out-tidl3가 이미 있습니다. 덮어쓰지 않습니다.' >&2; exit 1; }
config="$package/kernel-work/out-tidl2/.config"
[[ -r $config ]] || config="$package/patches/r47-tidl-build.config"
grep -qx 'CONFIG_DMABUF_HEAPS_CARVEOUT=y' "$config"
grep -qx 'CONFIG_REMOTEPROC_TI_VISION_DMA_BUF=y' "$config"
grep -qx 'CONFIG_RPMSG_CHAR=m' "$config"
mkdir -p "$output"
cp "$config" "$output/.config"
printf '빌드 준비 완료: %s\n커널 빌드는 실행하지 않았습니다.\n' "$output"
