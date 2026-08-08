# 공유 익스텐션 — 남은 배선

타겟(`ChoiceOS`)은 이미 만들어져 있고, 코드·plist·엔타이틀먼트·빌드 설정은
넣어놨다. **손으로 남은 건 아래 두 개뿐이다.**

## 1. 공유 파일의 타겟 멤버십 ← 이거 안 하면 컴파일 안 됨

아래 **다섯 개**를 하나씩 선택하고, 오른쪽 File Inspector →
**Target Membership** 에서 `ChoiceOS` 도 체크한다.

```
PersonalOS/Capture/ReceiptScan.swift
PersonalOS/Capture/ReceiptOCR.swift
PersonalOS/Capture/PendingCapture.swift
PersonalOS/Core/EntryKind.swift        ← EntryKind · TemplateKey
PersonalOS/Core/AppGroup.swift         ← WidgetShared.appGroupID
```

다섯 개 전부 **import Foundation 밖에 없다.** 그래서 익스텐션에 넣어도
아무것도 딸려오지 않는다. 원래 `EntryKind` 는 `Templates.swift` 안에,
`WidgetShared` 는 `WidgetSnapshot.swift` 안에 있었는데, 그대로 넣으면
SwiftData 모델 레이어가 통째로 끌려와서 떼어냈다.

`PersonalOS/` 는 동기화 폴더라 Xcode 가 예외 목록으로 기록한다. 정상이다.

**아래는 체크하지 말 것**

- `Capture/CaptureIntent.swift` — App Intent 는 앱 타겟에만
- `Core/Templates.swift` · `Core/WidgetSnapshot.swift` — 이제 필요 없다

이건 pbxproj 를 손으로 고치면 조용히 틀리기 쉬운 부분이라 남겨뒀다.
Xcode 가 예외 항목을 정확히 써준다.

## 2. 앱 그룹 승인

Signing & Capabilities → `ChoiceOS` 타겟에 App Groups 가
`group.com.calebsung.PersonalOS` 로 잡혀 있는지 확인. 엔타이틀먼트 파일은
이미 연결돼 있으니 대개 자동으로 프로파일이 갱신된다. 빨간 줄이 뜨면
"Try Again" 한 번.

---

## 이미 되어 있는 것 (참고)

- `ChoiceOS/ShareViewController.swift` — 템플릿(SLComposeServiceViewController)
  대신 직접 만든 컨트롤러. 원본은 `_to_delete/share-ext-template/` 에 있다.
- `ChoiceOS/Info.plist` — 스토리보드 대신 `NSExtensionPrincipalClass`,
  활성화 규칙은 **이미지 1장**으로 좁혔다(TRUEPREDICATE 였음).
- `ChoiceOS/ChoiceOS.entitlements` — 앱 그룹
- 빌드 설정: `CODE_SIGN_ENTITLEMENTS`, `SWIFT_DEFAULT_ACTOR_ISOLATION =
  MainActor`(앱과 동일), `IPHONEOS_DEPLOYMENT_TARGET 27.0 → 26.0`(앱과 동일)
- 앱 타겟: `INFOPLIST_FILE = Config/PersonalOS-Info.plist` — URL 스킴
  `personalos://` 등록용. `GENERATE_INFOPLIST_FILE` 은 YES 그대로 두고 병합된다.
  (익스텐션 타겟도 원래 이 조합이라 안전한 방식이다.)

### 버전은 앱과 같아야 한다

익스텐션의 `MARKETING_VERSION` 이 앱과 다르면 App Store 업로드에서 반려된다.
지금 둘 다 `1.0`. **앱 버전을 올릴 때 익스텐션도 같이 올릴 것.**

### 실행할 때

스킴이 `ChoiceOS` 로 잡혀 있으면 "Choose an app to run" 이 뜬다. 익스텐션은
단독으로 못 도니까 호스트 앱을 고르라는 뜻이다. **스킴을 `PersonalOS` 로
바꿔서 실행하면 된다** — 익스텐션은 앱에 같이 담겨 빌드된다.

### 확인

실기기 설치 → 아무 스크린샷 → 공유 → 위쪽 앱 아이콘 줄에 뜬다.
누르면 "화면을 읽는 중…" 이 잠깐 보이고 앱이 열리면서 확인 시트가 채워져 있어야
한다. 안 보이면 앱 줄 맨 끝 "더 보기"에서 켜면 된다.

공유 시트에 보이는 이름은 `INFOPLIST_KEY_CFBundleDisplayName = ChoiceOS` 다.
바꾸고 싶으면 익스텐션 타겟 빌드 설정에서 고치면 된다.

## 왜 익스텐션에서 저장까지 하지 않나

SwiftData 저장소가 앱 컨테이너에 있어서 익스텐션은 같은 DB 를 못 본다.
앱 그룹으로 옮기면 되지만 CloudKit 이 붙은 운영 데이터를 이사시키는 일이라
위험 대비 이득이 없다. 카테고리 학습·중복 검사도 DB 가 있어야 제대로 되므로
확인·저장은 앱 쪽 `CaptureReviewSheet` 가 맡는다.

익스텐션은 **OCR → 앱 그룹에 적기 → `personalos://capture` 로 앱 열기** 까지만.
