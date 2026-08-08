> ## ⚠️ 이 저장소는 **Notion 연동판**입니다
>
> 아래 문서는 배포판(`Personal-OS-`)에서 가져온 것이라 "Notion 연동 완전 제거"라고
> 적혀 있지만, **이 저장소에는 해당되지 않습니다.** 이쪽은 배포판의 모든 기능을
> 가져오면서 Notion 양방향 동기화를 유지한 변형입니다.
>
> 배포판과의 차이:
> - `PersonalOS/Notion/` (NotionAPI · NotionMapper · NotionSyncService) + `UI/NotionSettingsView.swift` 존재
> - `POSDatabase`에 `notionDatabaseID` / `notionDatabaseTitle` / `notionSyncEnabled` / `notionLastSyncAt`,
>   `POSEntry`에 `notionPageID` / `notionSyncedAt` / `notionLastEditedAt` 유지
> - `KeychainStore`는 `Core/`에 한 벌만 두고 메일 비밀번호 + Notion 토큰 둘 다 보관
> - 로컬 변경 지점마다 `NotionSyncService.shared.scheduleAutoSync()`,
>   삭제 직전마다 `entryWillDelete(_:)` 호출 (메일 임포트 직후 포함)
> - 노션 가계부 DB에 `유형` select(지출/수입/받은 정산/보낸 정산)를 추가해 둠 —
>   없으면 노션에서 당겨온 입금이 전부 "지출"로 잡혀 잔액이 깨진다
>
> 그 외 §3의 설계 결정(EntryKind 4종, 파서 임계값, isEcho 조건 등)은 이 저장소에도
> 그대로 적용됩니다.

---

# PersonalOS — 세션 인수인계

이 문서 하나로 다른 세션이 이 앱의 현재 상태를 이어받을 수 있게 정리한 것.
**2026-08-01 ~ 08-04** 사이에 한 작업 전부와, 그렇게 만든 **이유**를 담았다.
이유가 중요한 건, 근거를 모르면 다음 사람이 되돌리기 쉬운 결정들이 섞여 있어서다.

---

## 0. 앱 정체

| | |
|---|---|
| 저장소 | `~/Sihoon/Github/Personal-OS-` (GitHub: `SihoonSung`) |
| 스택 | SwiftUI + SwiftData + CloudKit, 외부 패키지 **0개** |
| 타깃 | iOS 26 / macOS 26. **visionOS는 제거함** |
| 번들 ID | `com.calebsung.PersonalOS` / 팀 `4G33B8YF8S` |
| 앱 그룹 | `group.com.calebsung.PersonalOS` |
| iCloud | `iCloud.com.calebsung.PersonalOS` |
| 언어 | 코드 주석·UI 모두 한국어 (기존 코드 관례) |
| 사용자 | 조지아 거주, Chase 체크카드(...9601) 하나, 룸메 5명과 공과금 정산 |

**구조 원리**: Notion 스타일 범용 DB 엔진(`POSDatabase` / `POSProperty` /
`POSEntry` / `POSValue`) 위에 가계부·할 일 같은 템플릿을 얹은 형태. 가계부도
특별한 테이블이 아니라 `templateKey == "budget"`인 일반 데이터베이스다.
속성은 이름으로 찾는다(`TemplateSemantics.swift`) — 사용자가 이름을 바꿔도
타입 기반 폴백으로 계속 동작하게.

---

## 1. 이번에 한 일 요약

1. **Notion 연동 완전 제거** — 로컬 + iCloud 전용으로
2. **이메일 파싱 가계부** — Gmail IMAP 직접 구현, Chase 알림 5종 파싱
3. **계좌 잔액** — 기준점 + 이후 거래 가감
4. **정기 결제 자동 감지** — 거래 기록에서 구독 추론
5. **Face ID 앱 잠금**
6. **위젯** — 잔액(홈+잠금화면), 말씀 시계(StandBy)
7. **말씀 시계** — 시각을 성경 장:절로 읽는 위젯 + 데이터 생성기

---

## 2. 신규 파일

### 메일 파이프라인 `PersonalOS/Mail/`

| 파일 | 역할 |
|---|---|
| `IMAPClient.swift` | NWConnection+TLS 위에 직접 구현한 최소 IMAP. LOGIN / LIST(SPECIAL-USE) / EXAMINE / UID SEARCH / UID FETCH |
| `MIMEMessage.swift` | 헤더 언폴딩, multipart 재귀, base64·quoted-printable, RFC2047, HTML→텍스트 |
| `TransactionParser.swift` | Chase 5종 + Apple 파서, 가게명 정리 |
| `CategoryRules.swift` | 키워드 테이블 + 사용자 학습 규칙(`POSMerchantRule`) |
| `MailSettings.swift` | UserDefaults 키 + Keychain 비밀번호 |
| `MailSyncService.swift` | 오케스트레이션, 중복 차단, 알림 |

### Core

| 파일 | 역할 |
|---|---|
| `BalanceService.swift` | 잔액 스냅샷 계산 |
| `RecurringDetector.swift` | 정기 결제 추론 |
| `VerseClock.swift` | 말씀 시계 데이터 로더 (**위젯 타깃에도 멤버십 필요**) |
| `KeychainStore.swift` | Notion 폴더에서 이동해옴 |

### UI

`MailSettingsView` / `ReviewQueueView` / `BalanceEditorView` /
`RecurringView` + `FixedCostCard` / `Dashboard/BalanceCard` /
`App/AppLock.swift`(+`LockGate`)

### 스크린샷 기록 `PersonalOS/Capture/`

Chase가 Zelle **송금 성공** 건만 알림 대상에서 빼놔서(취소·수취인 변경·만료는
온다. 이체 알림 임계값은 이미 최소 $1.00) 메일로는 영영 못 잡는 구멍을 메운다.

- `ReceiptScan.swift` — 파싱된 거래 + `ReceiptTextParser` (순수 로직)
- `ReceiptOCR.swift` — Vision 온디바이스 텍스트 인식, 위→아래 정렬
- `PendingCapture.swift` — 앱 그룹 경유로 인텐트 → 앱 본체 전달
- `CaptureIntent.swift` — App Intent. **Share Extension이 아닌 이유**: 새 타겟이
  필요해서 프로비저닝·Xcode Cloud 변수가 늘어난다. App Intent는 앱 타겟 안의
  파일 하나면 되고, 단축어로 감싸면 공유 시트에 똑같이 뜬다.
- `UI/CaptureReviewSheet.swift` — 확인 후 저장 + 사진 보관함 경로
- `UI/CaptureGuideView.swift` — 단축어 만드는 법 (설정 → 연동)

저장된 항목은 `sourceKind == "capture"` 라 검토 대기(`"email"` 기준)에
안 들어간다. 사람이 이미 확인하고 누른 것이기 때문.

### 공유 익스텐션 `ChoiceOS/`

공유 시트 **앱 아이콘 줄**에 PersonalOS 가 뜨게 하는 길. App Intent 는 단축어
앱에만 등록되고 공유 시트에는 그걸 감싼 단축어가 뜰 뿐이라, 앱을 직접 띄우려면
익스텐션이 있어야 한다. 둘은 공존한다 — 단축어 경로도 그대로 쓸 수 있다.

익스텐션에 넣는 파일은 **의존성이 없어야 한다.** `EntryKind`(원래
`Templates.swift`)와 `WidgetShared`(원래 `WidgetSnapshot.swift`)를 각각
`Core/EntryKind.swift` · `Core/AppGroup.swift` 로 떼어낸 이유가 이것이다.
그대로 두면 익스텐션이 SwiftData 모델 레이어를 통째로 끌어온다.
**이 두 파일에 import 를 추가하지 말 것.**

익스텐션은 **얇다**: OCR → 앱 그룹에 적기 → `personalos://capture` 로 앱 열기.
확인·저장은 앱 안의 `CaptureReviewSheet` 가 한다. SwiftData 저장소가 앱
컨테이너에 있어서 익스텐션이 같은 DB 를 못 보기 때문이고, 앱 그룹으로 옮기는
건 CloudKit 이 붙은 운영 데이터 이사라 위험 대비 이득이 없다.

타겟 이름은 `ChoiceOS`(App Store 앱 이름과 같게 만들어졌다). 남은 배선과
이미 해둔 것은 `ChoiceOS/SETUP.md`. 타겟 생성은 반드시 Xcode UI 로 할 것 —
pbxproj 를 손으로 고쳐 타겟을 만들다 깨뜨리면 아카이브부터 다시 잃는다.

**익스텐션의 `MARKETING_VERSION` 은 앱과 같아야 한다.** 다르면 App Store
업로드에서 반려된다. 앱 버전 올릴 때 익스텐션도 같이 올릴 것.

`Config/PersonalOS-Info.plist` 는 URL 스킴 등록용이다. `CFBundleURLTypes` 는
배열 안 딕셔너리라 `INFOPLIST_KEY_` 로 표현이 안 된다. 동기화 폴더
(`PersonalOS/`) 안에 두면 번들 리소스로도 복사돼 충돌하므로 밖에 둔다.

### 기타

- `Tools/build_verse_clock.py` — 말씀 시계 JSON 생성기
- `Tools/tests/*.py` — 검증 하네스 4종 (아래 §9)
- `PersonalOS/Resources/verse-clock.json` — 140KB, 720칸

---

## 3. 되돌리면 안 되는 설계 결정

### 3-1. `EntryKind`는 4종이어야 한다

```
지출      잔액 −, 지출통계 O
수입      잔액 +, 수입통계 O    (급여)
받은 정산  잔액 +, 통계 X       (룸메 Zelle 입금)
보낸 정산  잔액 −, 통계 X
```

처음엔 `지출/수입/이체` 3종이었는데 **"이체"로는 돈이 들어온 건지 나간 건지
알 수 없어서 잔액 계산이 불가능**했다. 값 하나가 부호와 통계 포함 여부를
혼자 결정하게 만든 게 핵심. `Templates.migrate()`가 옛 "이체" 값을
"받은 정산"으로 옮긴다.

Zelle 입금이 `받은 정산`인 이유: 대부분 룸메 공과금 정산금(2026-08-02 하루에
5명한테 $725)이라 수입으로 잡으면 월 수입 통계가 망가진다. 잔액에는 정확히
더해지고 통계에서만 빠진다.

### 3-2. 파서는 헤드라인 문장이 맞을 때만 거래를 만든다

느슨한 `\$[0-9.]+` 매칭을 쓰면 안 된다. Chase는 금액이 적힌 비거래 메일을
잔뜩 보낸다:

- "You set up automatic payment" → 본문에 `Payment amount $530.13`
- "Your Zelle® payment was canceled" → `Amount $876.55`
- 명세서 알림, 크레딧 점수, Connected Banking, 보안 알림

전부 무시돼야 한다. 그래서 **정해진 헤드라인 5종**에만 반응하게 했다.

### 3-3. `isEcho` 중복 차단의 조건이 좁은 이유

같은 입금이 Zelle 메일과 Deposit 메일 두 통으로 올 수 있어서 넣은 가드인데,
조건이 셋 다 필요하다:

- **들어온 돈만** — 지출은 같은 금액이 하루 두 번 나오는 게 정상
  (MTA 지하철 $3.00을 2026-07-25 오전 10:02와 오후 1:22에 두 번 찍음)
- **서로 다른 파서 규칙일 때만** — 같은 규칙이면 진짜 별개 거래
  (2026-07-08에 룸메 둘이 각자 $4.50씩 보냄)
- 36시간 이내 + 금액 동일(±$0.005)

### 3-3-b. `searchSenders` 는 **도메인**이어야 한다 (Gmail IMAP)

RFC 3501 의 `SEARCH FROM` 은 From 헤더 부분일치지만 **Gmail 은 이 명령을 자기
검색 엔진으로 처리해서 주소를 통째로 맞춘다.** 그래서 `alerts@chase.com` 으로
검색하면 0통이 나온다 — 실제 발신자 `no.reply.alerts@chase.com` 의
부분문자열인데도. 도메인(`chase.com`)으로 검색해야 잡힌다.

가져온 뒤 `MailSource.senderDomains` 로 한 번 더 거르므로 넓게 잡아도 안전하다.
**주소를 좁히는 방향으로 되돌리지 말 것.**

증상이 "연결은 되는데 0통"이었고, `testConnection` 이 검색 오류를 `try?` 로
삼켜서 빈 결과와 구분되지 않은 탓에 진단이 오래 걸렸다. 지금은 검색 실패와
0건을 다른 문구로 보고한다.

### 3-4. 정기 결제 임계값

```
간격 흔들림 ≤ max(2.5일, 주기의 15%)
금액의 60% 이상이 중앙값의 ±8% 안
최소 3회 관측 (같은 날 여러 번은 1회로 압축)
```

처음엔 흔들림 30% / 금액 25%였는데 **단골 카페(카페베네, 3·14·7일 간격
방문)를 "주간 구독 $17.49"로 잡았다.** 조인 뒤 오탐 0.

금액 일치 비율을 60%로 **남겨둔 건 의도적**이다 — 구독료가 오른 직후
(옛 금액 2회 + 새 금액 1회)에도 계속 잡히고, `priceChanged`로 표시된다.
BILT PAYMENT($23/$125/$145)처럼 진폭이 큰 건 안 잡히는데, 그건 "고정"지출이
아니므로 맞는 동작.

### 3-5. 메일 레이어 전체가 MainActor

빌드 설정이 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`라, actor를 따로 파면
동시성 애노테이션이 폭증한다. 전부 MainActor에 두고 async I/O만 쓰는 쪽이
훨씬 단순했다. 백필 중엔 메시지마다 `await Task.yield()`로 UI를 양보한다.

### 3-6. IMAP 타임아웃은 소켓을 직접 취소해야 한다

`withThrowingTaskGroup`으로 타임아웃을 걸어도, 소켓 콜백이 resume하는
`withCheckedThrowingContinuation`은 **취소만으로는 절대 resume되지 않는다.**
그대로 두면 그룹이 자식을 기다리며 영원히 멈추고, `isSyncing`이 true로 박혀
동기화 버튼이 죽는다. 그래서 타임아웃 시 `connection.cancel()`을 먼저 호출해
대기 중인 receive를 에러로 깨운다.

### 3-7. `private let` vs `private var` (실제로 빌드를 깨뜨림)

View 구조체에서 프로퍼티 래퍼 없는 `private var x = ...`는 memberwise
이니셜라이저를 private으로 끌어내려 다른 파일에서 생성이 불가능해진다.
`private let`은 이니셜라이저 파라미터에 아예 안 들어가서 안전.
싱글턴 참조는 전부 `private let`으로.

### 3-8. Keychain 접근성

`kSecAttrAccessibleAfterFirstUnlock`. 기본값(WhenUnlocked)이면 잠긴 폰에서
백그라운드 새로고침이 메일 비밀번호를 못 읽어 아무 일도 안 일어난다.

### 3-9. 숫자 입력은 **문자열이 진실**이다 (소숫점 버그)

`EntryDetailView`의 숫자 칸이 이런 왕복 바인딩이었다:

```swift
get: { Double → String }        // 모델을 다시 포맷해서 보여준다
set: { String → Double }        // 입력을 즉시 Double로 접는다
```

"12" 뒤에 "."을 누르면 `Double("12.") == 12.0` → 다시 그리기 → `"12"`.
**소숫점이 영영 안 찍힌다.** `TextField(value:format:)` 도 포맷터가 같은
왕복을 해서 똑같이 막힌다 (운동 세트의 무게 칸이 그랬다).

그래서 `UI/NumberField.swift`의 `PosNumberField`로 통일했다:

- 편집 중에는 화면의 문자열이 진실. 모델에는 **완성된 숫자일 때만** 흘린다.
- `"12."` · `"-"` 같은 중간 상태는 모델을 건드리지 않는다.
- 모델이 밖에서 바뀌면(노션 pull) **포커스가 없을 때만** 다시 읽는다.

**금지**: 숫자 칸에 `Binding<String>`의 get에서 모델을 포맷하거나
`TextField(value:format:)`을 쓰는 형태로 되돌리는 것. 버그가 그대로 재발한다.

### 3-9-b. 받은 정산은 **예산을 올린다**, 지출을 깎지 않는다

받은 정산은 지출/수입 통계에 안 잡히지만(§3-1) 그 달에 실제로 더 쓸 수 있는
돈이다. 룸메 몫까지 공과금 $876 을 내면 지출 $876 이 예산을 깎는데, 며칠 뒤
$438 을 돌려받아도 예산은 $876 을 쓴 채로 남는다.

그래서 `Core/BudgetMath.swift` 가 **실효 예산 = 설정 예산 + 그 달 받은 정산**
을 계산하고, 대시보드 카드·가계부 화면·위젯이 전부 이걸 쓴다.

**지출에서 빼지 않는 이유**: 어느 카테고리에서 빼야 할지 알 수 없고, 빼는
순간 카테고리 분해와 일별 추이가 같이 흔들린다. 예산만 올리면 "얼마 썼나"는
사실 그대로 두고 "얼마까지 쓸 수 있나"만 맞출 수 있다.

주의 두 가지:

- **세 화면이 같은 함수를 써야 한다.** 한 곳만 고치면 앱과 위젯의 "남은 예산"이
  달라진다. 계산은 `BudgetMath` 한 군데에만 둘 것.
- **예산 미설정(0)이면 정산이 있어도 0으로 둔다.** 정산만으로 예산이 생기면
  "설정에서 월 예산을 정하세요" 안내가 사라져서 더 헷갈린다.
- 올라간 이유는 화면에 적는다 (`예산 $3,000 + 받은 정산 $438 = $3,438`).
  숫자가 설명 없이 늘어나면 오히려 안 믿게 된다.

### 3-10. 키보드는 **바깥 아무 데나 탭**하면 내려간다 (완료 막대 아님)

`.decimalPad` · `.numberPad` 에는 리턴 키가 없어서 한 번 올라오면 내릴 방법이
없다. 처음엔 키보드 위에 "완료" 막대를 얹었는데 화면이 하나 더 생기는 꼴이라
걷어냈다. 지금은 `posScreen()` 이 창(UIWindow)에 탭 인식기를 하나 달아둔다.

SwiftUI 가 아니라 UIKit 인 이유:

- `.onTapGesture` 를 화면 전체에 걸면 그 아래 버튼·리스트 행의 탭을 먹는다.
  창 인식기에 `cancelsTouchesInView = false` 를 주면 터치가 그대로 흘러간다.
- **입력 칸 위의 탭은 반드시 무시해야 한다.** 안 그러면 텍스트 필드를 누르는
  순간 키보드가 올라왔다가 바로 내려간다. delegate 에서 터치가 닿은 뷰의
  조상을 훑어 `UITextField`·`UITextView`·`UIControl` 이 있으면 안 받는다.

설치는 창당 한 번만 되도록 막아뒀으니 여러 화면에 붙어도 괜찮다.
`.scrollDismissesKeyboard(.interactively)` 는 그대로 같이 있다.

### 3-11. 스크린샷 파서는 메일 파서와 **반대 원칙**으로 만든다

메일 파서(§3-2)는 확인된 헤드라인이 정확히 맞을 때만 거래를 만든다 —
틀리면 사용자 모르게 가계부가 오염되기 때문이다.

`Capture/ReceiptScan.swift`는 반대로 **느슨하게 읽고 반드시 사람에게 보여준다.**
저장은 확인 시트에서 사람이 누른다. 그래서 Zelle 전용 규칙을 박지 않고
금액·상대·날짜·메모를 일반적인 규칙으로 뽑는다 — Venmo·Cash App·토스·
종이 영수증까지 같은 코드로 들어온다.

주의 세 가지:

- **잔액 줄을 반드시 걸러야 한다.** 통장 잔고가 송금액보다 큰 게 보통이라
  "가장 큰 금액" 규칙이 그대로 잔고를 집어간다 (`isBalanceLine`).
- **Vision 결과를 위→아래로 다시 정렬해야 한다.** 관측 순서가 화면 순서가
  아니라서, "라벨 다음 줄에 값" 배치를 못 읽게 된다.
- **느슨한 `to` 규칙을 앞으로 당기지 말 것.** 아래 실물 화면 참고.

#### 실물 Chase Zelle 확인 화면 (IMG_0751)

```
Confirmation
We're sending your money now. Uzma Abbas will get it
in a few minutes.
$876.55
U
Uzma Abbas
Registered as UZMA ABBAS
(631) 922-2291
Add a Siri shortcut, such as "Pay Uzma," to save time when
sending money.
Add to Siri
Done
```

이 화면에 **To 라벨도, Amount 라벨도, 날짜도 없다.** 처음엔 있을 거라 가정하고
짰다가 실물 보고 다 고쳤다. 지금 `counterparty(in:)` 의 순서는 이 화면에서
나온 것이다:

1. `Registered as ○○` **윗줄** — 보기 좋은 표기의 이름이 거기 있다
2. `… NAME will get it` — 마침표 뒤 마지막 조각
3. `To` / `Recipient` 라벨
4. 한 줄 안의 `to ○○` — **금액이 같은 줄에 있거나 You sent/You paid 로
   시작할 때만**

4번을 앞으로 당기거나 조건을 풀면 맨 아래 안내 문장의
`"Pay Uzma," **to** save time when sending money.` 를 물어서 받는 사람을
`save time when sending money.` 로 읽는다. 실제로 그랬다.

날짜는 화면에 없으므로 `nil` 이 정상이고, 확인 시트가 현재 시각으로 채운다
(스크린샷은 송금 직후에 찍히니까 맞는 값이다).

출처가 "Zelle" 인 것도 글자가 아니라 **`Registered as` + `will get it` 조합**
으로 알아낸다 — 보라색 Z 는 로고라 OCR 이 못 읽는다.

파서를 고치면 `Tools/tests/receipt_parse_check.py` 를 같이 고칠 것.

---

## 4. Chase 메일 실제 포맷

파서를 고칠 땐 이 문자열들로 회귀 테스트할 것 (`Tools/tests/parser_check.py`).
HTML을 `htmlToText`로 편 뒤의 모습이다.

| 규칙 | 헤드라인 | 유형 |
|---|---|---|
| `chase.card` | `You made a debit card transaction of $27.77 with TST* BB.Q CHICKEN US` | 지출 |
| `chase.transfer` | `You sent $10.69 to TESLA MOTORS` | 지출 |
| `chase.bill` | `Your bill payment of $530.13 to AUTO LEASE 6842` | 지출 |
| `chase.zelle-in` | `Zelle® payment HYEWON LEE sent you money` | 받은 정산 |
| `chase.deposit` | `You received a direct deposit of $X` **(미검증)** | 수입 |

공통 라벨 표: `Account ending in (...9601)` / `Made on Jul 31, 2026 at 5:18 PM ET`
/ `Description <가게>` (송금·청구서는 `Recipient`) / `Amount $27.77`

**`chase.deposit`만 실물 메일로 검증 못 했다.** Chase 알림 설정에서
"Deposit of more than $__ posted"를 켜야 오기 시작한다(임계값 200 권장 —
정산금 $4.50~$183과 겹치지 않게). 실물이 오면 문구를 확인하고 패턴을 확정할 것.

`MailSyncService.SyncResult.unrecognized`가 이걸 위한 신호다. 금액이 적힌
Chase 알림인데 어떤 규칙에도 안 걸리면 카운트해서 요약에 "못 읽은 알림 N통"으로
띄운다. 알려진 비거래 메일은 `TransactionParser.benignPhrases`로 걸러서
카운터가 노이즈로 차지 않게 했다.

---

## 5. 잔액

은행 잔고를 읽을 방법이 없어서 **기준점 + 이후 거래 가감**으로 추정한다.

- `POSBalanceAnchor`(amount, recordedAt, source, note) — 이력을 남긴다
- 현재 잔액 = 앵커 금액 + Σ(앵커 시각 **초과** 거래의 `balanceDelta`)
- 경계가 `>`인 게 중요 — 앵커를 찍는 순간 이미 반영돼 있던 거래를 두 번 빼면 안 됨
- 30일 지나면 `isStale`로 "한 번 맞춰볼 때가 됐어요" 표시

사용자가 고른 방식은 **수동 앵커만**. Chase 잔액 알림 메일 파싱은 일부러 안
넣었다(나중에 원하면 `source: "email"`로 확장할 자리를 남겨둠).

---

## 6. 말씀 시계

12시간제 시각을 장:절로 읽는다 — 07:21 → 마태복음 7:21.

- 데이터: `PersonalOS/Resources/verse-clock.json` (720칸, 140KB)
- 생성기: `Tools/build_verse_clock.py` (pythonbible 필요)
- 위젯: 1시간치 60개 엔트리를 한 번에 넘겨 분 단위로 갱신 (확장은 하루 24번만 깨움)

**25칸은 시각과 안 맞는다** — 4:55~4:59, 5:49~5:59, 10:53~10:59, 11:58~11:59.
성경 66권 중 4장이 55절까지 있는 책이 하나도 없다(제일 긴 4장이 요한복음 54절).
예비 구절로 채우고 `exact: false`로 표시, 화면에선 장:절 배지를 숨긴다.

**본문이 아직 영어(공개도메인 ASV)다.** 사용자는 한글(개역개정 계열)을
원했는데 한글 성경 텍스트를 패키지 레지스트리에서 못 구했다(있는 건 대한성서공회
사이트를 실시간으로 긁는 MCP 서버뿐이라 부적합). 성경 JSON 파일 하나만 있으면
바꿀 수 있다:

```bash
cd Tools && pip install pythonbible
python3 build_verse_clock.py --korean 성경.json --out ../PersonalOS/Resources/verse-clock.json
```

입력 형식 3가지를 다 받는다 (한글 책이름 / 영문 enum / 3글자 약어).
저작권: 개역개정은 대한성서공회 것. TestFlight 범위는 현실적으로 무방하나
App Store 공개 배포엔 허락 필요.

구절 선택은 점수제다. 처음엔 요한복음이 299칸을 먹었고, 다양성 벌점을 주니
이번엔 **9:45에 사사기(아비멜렉이 성을 헐고 소금을 뿌림)**가 떴다. 그래서
전쟁·심판·저주 단어에 큰 벌점, 위로되는 단어에 가산점, 소문자로 시작하는
문장 조각 배제를 넣었다. 최종 57권 사용, 거친 구절 2/720.

---

## 7. 빌드·배포 환경 (여기서 제일 많이 막혔음)

### macOS 27 베타 문제

사용자 맥이 **macOS 27 베타**다. 그래서:

- Xcode 26.x는 "This version of Xcode isn't supported in this version of macOS"로 **실행 자체가 안 됨**
- Xcode 27 베타만 돌아가는데, App Store Connect는 **베타 SDK 업로드를 거부**

로컬에서는 빠져나갈 구멍이 없다. **Xcode Cloud가 해법**이고 이미 동작 확인했다
(Apple 서버가 Xcode 26.6 정식판으로 빌드 → 업로드 성공).

- 워크플로 `Internal TestFlight Build`, 액션은 `Archive - iOS`만 남길 것
- 워크플로를 **새로 만들면 지원 플랫폼마다 액션이 자동 추가된다** — macOS가
  또 붙으면 지우면 됨. 프로젝트에서 macOS를 빼지는 말 것(나중에 Mac 앱 계획 있음)
- 개발자 프로그램에 월 25시간 무료 포함, 빌드당 10~20분

**로컬 ⌘R로 아이폰에 설치하는 건 지금도 문제없다.** 막힌 건 업로드뿐.

### pbxproj에 추가한 것

```
INFOPLIST_KEY_BGTaskSchedulerPermittedIdentifiers = "com.calebsung.PersonalOS.mailrefresh"
INFOPLIST_KEY_UIBackgroundModes[sdk=iphone*] = fetch
INFOPLIST_KEY_NSFaceIDUsageDescription = "..."
INFOPLIST_KEY_NSHealthShareUsageDescription = "..."
INFOPLIST_KEY_NSHealthUpdateUsageDescription = "..."
INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO
SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"   ← xros 제거
```

`BGTaskSchedulerPermittedIdentifiers`가 **배열이 아니라 문자열로 들어갈 수
있다** — Xcode Info 탭에서 확인하고 아니면 수동으로 Array로 고쳐야 한다.
안 고쳐도 앱은 정상, 백그라운드 수집만 안 됨.

### HealthKit purpose string — 에러 90683 (아카이브 실패의 진짜 원인)

`Preparing build for App Store Connect failed` 로만 보이던 실패의 정체는
App Store Connect → TestFlight → 해당 빌드 → Errors 안에 있었다:

```
90683: Missing purpose string in Info.plist.
  ... should contain a NSHealthShareUsageDescription key ...
  ... should contain a NSHealthUpdateUsageDescription key ...
```

원인: `Workout/HealthKitService.swift` 가 `import HealthKit` 하는데
pbxproj에 위 두 키가 없었다. **엔타이틀먼트·아이콘·버전 충돌은 전부
무관했다** — 그쪽을 건드리며 날린 빌드가 여러 개다.

규칙: 민감 API를 하나라도 링크하면 purpose string은 **엔타이틀먼트를 빼도
필요하다.** Apple은 엔타이틀먼트가 아니라 *코드가 그 API를 참조하는지* 를
본다. 그래서 "HealthKit 권한을 껐으니 괜찮겠지"가 통하지 않는다.

이 프로젝트는 `GENERATE_INFOPLIST_FILE = YES` 라 Info.plist 파일이 없다.
purpose string은 반드시 `INFOPLIST_KEY_*` 빌드 설정으로 넣어야 하고,
**Debug/Release 두 블록 모두**에 넣어야 한다.

새 프레임워크를 추가할 때 확인할 것:

```
grep -rho "^import .*" PersonalOS --include=*.swift | sort -u
```

현재 purpose string이 필요한 것: EventKit(NSCalendarsFullAccess),
LocalAuthentication(NSFaceID), HealthKit(NSHealthShare/NSHealthUpdate).

### 앱 아이콘

`AppIcon-1024.png`에 알파 채널이 있어서 업로드가 거부됐다. 값이 243~255라
실제 투명 영역은 없었고 채널만 떼서 해결(RGB 변환). **`-dark`·`-tinted`는
알파가 있어야 정상이니 건드리지 말 것.** 원본은 `_to_delete/icon-backup/`.

### 프로젝트 구조

`PBXFileSystemSynchronizedRootGroup`을 쓴다 → `PersonalOS/` 아래 파일을
추가/삭제하면 타깃에 자동 반영, **pbxproj를 손댈 필요 없음**.

단, **위젯 타깃은 아직 안 만들어져 있다.** 만들 때:

1. 이름은 `PersonalOSWidgetExt` (기존 `PersonalOSWidget` 폴더와 충돌 방지)
2. Live Activity / App Intent 체크 해제
3. 템플릿 .swift 삭제 후 `PersonalOSWidget/PersonalOSWidget.swift` 드래그
4. 아래를 위젯 타깃 멤버십에 **추가**:
   `Core/WidgetSnapshot.swift`, `Core/VerseClock.swift`,
   `Resources/verse-clock.json`(Copy Bundle Resources에도)
5. 앱과 **같은** App Group

### git

마운트된 폴더에서 git 명령을 돌리면 `.git/index.lock`을 지우지 못해 커밋이
막힌다. 실제로 3일간 `HEAD.lock`·`maintenance.lock`이 남아 GitHub Desktop
커밋이 계속 실패하고 있었다. **자동화 세션에서 이 폴더에 git write 명령을
돌리지 말 것.** 읽기만 할 땐 `git --no-optional-locks`.

`.gitignore`에 `*.tar.gz`, `_to_delete/`, `build/`, `DerivedData/`,
`*.xcarchive` 추가함.

---

## 8. 데이터 모델 변경

```swift
// 삭제
POSDatabase.notionDatabaseID / notionDatabaseTitle / notionSyncEnabled / notionLastSyncAt
POSEntry.notionPageID / notionSyncedAt / notionLastEditedAt

// 추가
POSEntry.sourceKind: String      // "" | "email"
POSEntry.sourceMessageID: String?  // RFC5322 Message-ID — 중복 차단 1차 키
POSEntry.sourceRule: String?     // "chase.card" 등

@Model POSMerchantRule      // 학습된 가게→카테고리 규칙
@Model POSBalanceAnchor     // 잔액 기준점
```

Schema에 새 모델 2개 등록됨(`PersonalOSApp.init`). CloudKit 규칙(모든 저장
속성에 기본값 또는 옵셔널, `@Attribute(.unique)` 금지) 유지.

가계부 스키마: 금액 / 카테고리 / 날짜 / **유형** / 결제수단 / 출처 이메일 / 확인됨.
`Templates.migrate()`가 기존 DB에 없는 속성을 채우고 옛 값을 마이그레이션한다.

---

## 9. 검증 방법

**이 컨테이너엔 Swift 툴체인이 없어 컴파일 검증이 불가능하다.** 대신 순수
로직을 Python으로 포팅해 실제 데이터로 회귀 테스트해 왔다. `Tools/tests/`:

| 스크립트 | 커버 |
|---|---|
| `parser_check.py` | Chase 파서 18케이스 (양성 11 + 음성 7), htmlToText |
| `balance_check.py` | 잔액 계산, 앵커 경계, 정산금 통계 제외 |
| `echo_check.py` | 중복 입금 병합 7케이스 |
| `recurring_check.py` | 정기결제 감지 (구독 5 감지 / 비구독 4 무시) |

파서나 임계값을 건드리면 **반드시 해당 스크립트를 먼저 고치고 돌려서**
기존 케이스가 깨지지 않는지 확인할 것. 케이스는 전부 사용자의 실제 Gmail에서
가져온 문자열이다.

---

## 10. 미해결 / 다음 후보

**해야 할 것**

- [ ] 위젯 타깃 생성 (§7)
- [ ] 실기기 검증 — **아직 아무도 실제로 앱을 돌려본 적 없다**
- [ ] `chase.deposit` 패턴을 실물 메일로 확정
- [ ] 한글 성경 JSON 넣기
- [ ] `BGTaskSchedulerPermittedIdentifiers` 배열 여부 확인

**논의됐던 다음 기능**

- 주간/월간 지출 리포트 — 지금 앱엔 차트는 있는데 "지난주 대비", "구독 연간
  환산" 같은 **해석**이 없다. 사용자의 노션 루틴("주간 지출보고")이 하던 역할
- 룸메 정산 추적 — 월별로 누가 얼마 보냈고 누가 미납인지. Zelle 메모가
  제각각이라("utility fee", "rent util", 빈칸) 룸메 명단 등록이 필요
- 카테고리별 예산 / Siri 단축어 / CSV 내보내기

**알려진 제약**

- 자동 동기화는 앱 포그라운드(5분 스로틀)가 실질적 주기. 백그라운드는 best-effort
- 실시간 푸시는 구조상 불가 — 서버 없이 폰이 직접 IMAP을 도는 설계라
- 배포 범위는 TestFlight 내부 테스터. App Store 공개는 Gmail 앱 비밀번호
  방식이 심사에서 문제될 수 있어 OAuth 전환이 선행돼야 함

---

## 11. 다른 세션에서 시작할 때

```
~/Sihoon/Github/Personal-OS-  를 열고 이 문서를 먼저 읽어줘.
Swift 컴파일은 이 환경에서 못 하니, 로직을 바꾸면 Tools/tests/ 의
Python 하네스로 회귀 검증하고, 빌드는 사용자가 Xcode에서 돌린다.
```

주의할 것 세 가지만 다시:

1. **git write 명령을 이 폴더에서 돌리지 말 것** (lock 파일이 남는다)
2. **파서 임계값을 느슨하게 되돌리지 말 것** (§3-2, §3-4에 실패 사례 있음)
3. **`EntryKind` 4종 체계를 3종으로 되돌리지 말 것** (잔액 계산이 깨진다)
