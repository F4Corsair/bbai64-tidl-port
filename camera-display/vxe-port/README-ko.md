# BBAI64 VXE 로컬 포팅 준비

[English](README-en.md) · [사전 조사](preanalysis-ko.md) · [배포 가이드](deployment-ko.md) · [작업 과정](../worklog-ko.md) · [성과](../outcomes-ko.md) · [실기 결과](results-ko.md)

## 확보 및 검증 결과

- Yocto meta-ti의 `11.02.11` 태그에서 커밋 `ea8c0b1cf1ab8a0b327e3feb1144c1ccf05b8278`의 기본 레시피를 확인했다. 이 레시피의 `SRC_URI`에는 별도 패치가 없으며, 참조 리비전은 `0bcbb20af32ea13275b452f0e84f5a49966d0bf6`이다. SDK 이미지 빌드에 적용된 레이어별 bbappend는 미확인이다. TI 원본은 해당 리비전으로 이 폴더의 `ti-source/`에 확보했다. [Yocto 릴리스 레시피](https://git.yoctoproject.org/meta-ti/tree/meta-ti-bsp/recipes-bsp/ti-img-encode-decode/ti-vxe-vxd-driver_6.12.bb?h=11.02.11)
- 고정된 드라이버 소스의 `v4l2_fh_add/del` 및 platform `.remove` 버전 분기는 r47 헤더와 일치한다. 실제 빌드 결과로 나머지 API의 호환성을 판정한다. 드라이버는 40비트 DMA 마스크를 요청하고, `encoder/mtx_fwif.c`가 `fw_binaries/include_all_fw_variants.h`를 통해 MTX 펌웨어를 컴파일에 포함한다. 별도 인코더 펌웨어 파일 설치는 필요하지 않다. 원본 저장소의 라이선스와 펌웨어 헤더의 고지를 보존한다.
- [오버레이 소스](k3-j721e-bbai64-vxe.dtso)를 기존 BBAI64 후보 DTB에 적용했다. 정렬해 역컴파일한 결과의 유일한 차이는 VXE 노드다. 로컬 산출물은 `generated/`에 있고 `SHA256SUMS` 검증을 통과했다. DTB SHA256은 `e60858c8397c8255aab5add08dc06a1484c0d7c07ea0316ca4ce7f86c5813b1a`다. 실기 probe와 인코딩은 미검증이다.

## 사용자 실행

프로젝트 루트에서 실행한다. 각 스크립트의 출력 디렉터리는 새 경로를 지정한다.

다른 작업 폴더에서 재현할 때는 `git clone --branch scarthgap/k6.12 https://git.ti.com/git/multimedia/img-vxe-vxd.git camera-display/vxe-port/ti-source`를 실행한 뒤, 해당 저장소에서 위 드라이버 커밋으로 detached checkout한다.

```bash
bash camera-display/vxe-port/prepare-dtb.sh camera-display/vxe-port/dtb-check
bash camera-display/vxe-port/build-modules.sh camera-display/vxe-port/module-check
(cd camera-display/vxe-port/module-check && sha256sum -c SHA256SUMS)
```

[모듈 빌드 스크립트](build-modules.sh)는 기존 tidl3 빌드 출력과 툴체인을 검사하고 TI 레시피 방식으로 외부 모듈을 컴파일한다. TI Makefile은 두 모듈을 빌드하며 배포 후보는 `vxe-enc.ko`만 복사한다. 소스 리비전, 툴체인, modpost 또는 vermagic 검사가 실패하면 `build.log`를 확인하고 배포를 중단한다. 이번에 수행한 검증은 스크립트 구문 및 DT 오프라인 검사까지다.

모듈 빌드가 통과하면 [사전 조사](preanalysis-ko.md)의 인수 기준에 따라 기존 DTB와 부트 항목을 보존하고 별도 후보 항목에서 시험한다. 사용자 적용 이후 probe, 합성 NV12→H.264, TIDL 회귀, D435i 연동 순으로 확인한다.
