# 검증 하네스

이 저장소를 다루는 환경엔 Swift 툴체인이 없어 컴파일 검증을 못 한다.
그래서 순수 로직(파서·잔액·중복차단·정기결제)을 Python으로 포팅해두고
실제 Gmail에서 가져온 문자열로 회귀 테스트한다.

```bash
python3 parser_check.py      # Chase 파서 18케이스 + htmlToText
python3 balance_check.py     # 잔액 계산, 앵커 경계
python3 echo_check.py        # 중복 입금 병합
python3 recurring_check.py   # 정기결제 감지 임계값
python3 muscle_load_check.py # 근육 부하 계산
python3 bible_ref_check.py   # 성경 구절 파싱
python3 receipt_parse_check.py # 스크린샷 OCR 파싱
python3 budget_uplift_check.py # 받은 정산만큼 예산 올리기
```

Swift 쪽 로직을 고치면 **여기 먼저 반영해서 돌려보고** 기존 케이스가
깨지지 않는지 확인할 것. 케이스는 전부 실제 메일에서 온 것이라
임의로 바꾸면 검증 가치가 사라진다.

대응 관계:

| 스크립트 | Swift 원본 |
|---|---|
| `parser_check.py` | `Mail/TransactionParser.swift`, `Mail/MIMEMessage.swift` |
| `balance_check.py` | `Core/BalanceService.swift`, `Core/Templates.swift`(EntryKind) |
| `echo_check.py` | `Mail/MailSyncService.swift` (`isEcho`) |
| `recurring_check.py` | `Core/RecurringDetector.swift` |
| `muscle_load_check.py` | `Workout/MuscleLoad.swift` |
| `bible_ref_check.py` | `Core/BibleReference.swift` |
| `receipt_parse_check.py` | `Capture/ReceiptScan.swift` (`ReceiptTextParser`) |
| `budget_uplift_check.py` | `Core/BudgetMath.swift` |

`receipt_parse_check.py` 의 "실물 Chase Zelle 확인 화면" 케이스는 진짜
스크린샷(IMG_0751)에서 온 줄들이다 — **손대지 말 것.** 나머지 케이스는
Venmo·영수증 등 아직 실물을 못 받아서 그럴듯하게 짜둔 것이라, 실제 화면을
확보하면 교체하면 된다.
