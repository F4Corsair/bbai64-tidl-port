# 보드 검증 결과

- 시험 일시 / 부팅 매체 / UART 로그:
- `uname -a` / 원본·후보 DTB SHA256 / GP·HS 판정:
- 펌웨어 세트·커널 소스 및 변경 식별자:
- ONNX / artifacts / input SHA256, abs tolerance:

| 단계 | 상태 | 결과 및 근거 |
|---|---|---|
| 01 기준 및 live DT | 미검증 | |
| 02 코어·펌웨어·MCU attach | 미검증 | |
| 03 RPMsg·DMA 및 DSP 데이터 왕복 | 미검증 | |
| 04 동적 로딩·TIOVX | 미검증 | |
| 05 CPU 비교·위임·C71x/MMA | 미검증 | |

`tidl-results/`의 Markdown·상세 로그와 동일 실행의 UART/C71x 프로파일을 첨부한다. 스크립트의 종료 코드는 성공 0, 실패 1, 미검증 2다. 03의 호스트 DMA 통과나 05의 EP 처리 시간만 확보했으면 해당 검증 범위를 적고 남은 기능은 미검증으로 표시한다.
