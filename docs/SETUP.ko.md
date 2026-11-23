# Jarvis 설치·설정 가이드 (아이패드 Swift Playgrounds 기준)

## 0. 준비물

- **아이패드**: M1 이상 또는 iPad mini(A17 Pro), **iPadOS 26 이상**, Apple Intelligence 켜짐(설정 › Apple Intelligence 및 Siri).
- **Swift Playgrounds 4.7 이상**(App Store, 무료). 4.7부터 iOS 26 SDK(Foundation Models 포함)를 지원합니다.
- 처음 한 번만 Wi-Fi: Kokoro 영국 음성(약 95MB)·선택형 심층 사고 모델(1~2.3GB) 다운로드. 이후 완전 오프라인.

## 1. 설치 (PC 없이)

1. 아이패드 Safari에서 GitHub 저장소를 열고 브랜치 `claude/ios-ipad-jarvis-agent-db6yyi`를 선택 → **Code › Download ZIP**.
2. 파일 앱에서 ZIP을 탭해 압축 해제 → `Jarvis.swiftpm` 폴더가 생깁니다.
3. `Jarvis.swiftpm`을 탭하면 Swift Playgrounds에서 열립니다(또는 Playgrounds › "내 앱" › 파일에서 열기).
4. 오른쪽 위 **▶︎ 실행**. 첫 빌드는 1~3분 걸립니다.
5. 온보딩 화면에서 **권한 허용**(마이크·음성 인식·알림; 카메라·사진은 해당 기능을 처음 쓸 때 요청) → **Kokoro 음성 내려받기** → **시작하기**.

> Playgrounds의 앱 설정(이름·아이콘·권한) 화면에서 값을 바꾸면 `Package.swift`가 다시 쓰여 `additionalInfoPlistContentFilePath: "Info-Extra.plist"` 줄이 지워질 수 있습니다. 지워지면 다시 넣어 주십시오(백그라운드 오디오, `jarvis://` 링크, 파일 앱 노출에 필요).

### 아이폰에 설치하려면
Swift Playgrounds는 아이패드 전용입니다. 아이폰에서는 다음 중 하나가 필요합니다.
- Playgrounds의 **App Store Connect에 업로드** → TestFlight로 아이폰 설치(유료 Apple 개발자 계정, PC 불필요).
- Mac이 있다면 `Jarvis.swiftpm`을 Xcode로 열어 아이폰에 실행.

이렇게 설치한 독립 앱에서는 Siri 앱 단축어("Wake up Jarvis"), 백그라운드 상시 청취, PiP가 완전하게 동작합니다.

## 2. 앱 밖에서 깨우기: "Wake up Jarvis" 단축어 (가장 중요)

1. **단축어** 앱 › **+** › "동작 추가" › **URL 열기** 검색.
2. URL에 `jarvis://wake` 입력.
3. 단축어 이름을 정확히 **Wake up Jarvis** 로 저장.

이제 다음이 모두 가능합니다.
- **"Siri야, Wake up Jarvis"** — 잠금 화면·다른 앱 어디서든 Siri가 단축어를 실행해 자비스를 깨웁니다(단축어 이름이 곧 Siri 명령).
- **항상 떠 있는 버튼**: 설정 › 손쉬운 사용 › 터치 › **AssistiveTouch** 켜기 › 사용자 설정 동작 › **단일 탭 → "Wake up Jarvis"**. 모든 앱 위에 떠 있는 시스템 버튼 한 번으로 자비스가 깨어납니다(비상 웨이크 버튼의 앱 밖 버전).
- **제어 센터**: 제어 센터 편집 › 컨트롤 추가 › 단축어 › "Wake up Jarvis".
- **뒷면 탭**(아이폰): 손쉬운 사용 › 터치 › 뒷면 탭 › 두 번 탭 → "Wake up Jarvis".
- **동작 버튼**(아이폰 15 Pro 이상): 설정 › 동작 버튼 › 단축어 › "Wake up Jarvis".

추가 링크: `jarvis://ask?text=오늘 일정 알려줘`(바로 질문), `jarvis://open3d`(3D 공간), `jarvis://sleep`.

## 3. 자동 실행에 가장 가까운 설정

iOS는 어떤 앱도 전원을 켤 때 자동 실행되도록 허용하지 않습니다. 대신 **단축어 › 자동화 › +** 에서:

| 트리거 | 동작 | 효과 |
|---|---|---|
| 충전기 › 연결됨 | Wake up Jarvis 실행, "즉시 실행" | 충전기를 꽂으면 자비스가 깨어남(밤새 대기에 적합) |
| 특정 시간(예: 오전 7시) | Wake up Jarvis | 매일 아침 자동 기동 |
| 앱 › Safari/YouTube 등 열릴 때 | Wake up Jarvis | 특정 앱과 함께 자동 기동 |
| 집중 모드 › 업무 켜질 때 | Wake up Jarvis | 업무 시작과 함께 기동 |

또한 Jarvis는 백그라운드 작업(BGTask)을 등록해, 재부팅 후 첫 잠금 해제 이후 iOS가 허용하는 시점에 백그라운드에서 깨어나 학습 상태를 저장·정리합니다.

## 4. 3D 공간을 바탕화면으로

1. 3D 공간에서 "**배경화면으로 저장해**" / "set as wallpaper" → 현재 장면이 사진 앨범 **Jarvis Space**와 `파일 › Jarvis › Artifacts`에 저장됩니다.
2. 단축어 › 자동화 › **앱 › Jarvis(또는 Swift Playgrounds) › 닫힐 때** › 동작:
   - **사진 찾기**: 앨범이 "Jarvis Space", 정렬 "최신순", 제한 1장
   - **배경화면 설정**(잠금 화면/홈 화면 선택, "미리보기 표시" 끄기)
3. 이제 자비스를 닫을 때마다 마지막 3D 작업 공간이 바탕화면이 됩니다.

(설치형 앱에서는 "Jarvis 3D workspace image" 단축어 동작이 같은 이미지를 바로 돌려줍니다.)

## 5. Jarvis Bridge: 시스템 설정·다른 앱 제어

와이파이·블루투스·집중 모드·다크 모드·저전력·메시지 전송·홈 장비·다른 앱의 동작은 iOS가 앱에 직접 허용하지 않으므로 단축어를 통해 위임합니다. [SHORTCUTS.ko.md](SHORTCUTS.ko.md)의 레시피대로 **Jarvis Bridge** 단축어를 한 번 만들면 "와이파이 꺼", "다크 모드 켜", "방해 금지 켜" 같은 명령이 동작합니다.

## 6. 음성 품질

- **영어(영국 신사)**: 설정 › 영국 신사 음성에서 Kokoro를 내려받으면 `bm_george`(기본)·Lewis·Daniel·Fable 중 선택. 내려받기 전에는 시스템 영국 남성 음성을 사용합니다.
- **한국어**: 한국어 남성 시스템 음성을 격식체로 사용합니다. 아이패드 설정 › 손쉬운 사용 › 음성 콘텐츠 › 음성 › 한국어에서 **고품질(향상된)** 음성을 내려받으면 자동으로 그 음성을 씁니다.
- 말 속도: "천천히 말해" / "speak faster" (신경 코어의 소뇌가 선호를 학습).

## 7. 첫 실행 체크리스트

| 확인 항목 | 방법 | 기대 결과 |
|---|---|---|
| 음성 웨이크 | "Wake up Jarvis" | 코어가 밝아지고 "Jarvis at your service, sir." |
| 비상 웨이크 | 오른쪽 아래 주황 버튼 | 같은 응답 |
| 한/영 자동 전환 | "What time is it?" → "지금 몇 시야?" | 영어는 영국 음성, 한국어는 한국어 음성·격식체 |
| 끼어들기 | 자비스가 길게 말할 때 "그만" 또는 새 질문 | 즉시 멈추고 새 요청 처리 |
| 3D 공간 | "3D 공간 열어줘" → "빨간 큐브 세 개 만들어" → "두 번 복제해" | 3D 공간이 배경이 되고 큐브 생성·복제 |
| 마우스 | 큐브를 왼쪽 드래그 / 가리킨 채 스크롤 | 이동 / 확대·축소 |
| 손 인식 | "손 인식 켜" → 엄지·검지로 집어 이동, 양손 간격 조절 | 레티클이 따라오고 크기 조절 |
| 음악 | "아이유 노래 틀어줘" → "일시정지" → "다음 곡" | 웹에서 재생·제어 |
| 기록 | "기록 보여줘", 파일 앱 › Jarvis › Logs | 대화·작업·설명·파일 기록 |
| 신경 코어 | "신경망 보여줘" | 2061억 퍼셉트론 3D 홀로그램과 활동 표시 |
| 심층 사고(선택) | 설정에서 모델 내려받기 → "심층 사고 켜" | 더 깊은 답변(속도는 기기에 따라 다름) |

## 8. 문제 해결

- **Apple Intelligence 응답이 없음**: 설정 › Apple Intelligence 및 Siri가 켜져 있고 모델 다운로드가 끝났는지 확인. 그 전에는 기본 명령만 동작하고 대화는 안내 문구로 대체됩니다.
- **영국 음성이 아니라 기본 음성이 나옴**: 설정 패널에서 Kokoro 상태 확인 후 다시 내려받기.
- **와이파이 등 시스템 설정이 안 바뀜**: Jarvis Bridge 단축어가 필요합니다(5장).
- **백그라운드에서 웨이크가 안 됨**: Playgrounds 실행 중에는 iOS가 백그라운드를 보장하지 않습니다. AssistiveTouch/Siri 단축어를 쓰시거나 TestFlight 설치형을 사용하십시오.
- **빌드 오류**: Swift Playgrounds 4.7 이상인지, `Package.swift`의 `platforms: [.iOS("26.0")]`가 유지되는지 확인.
- **실행 중 "Jarvis Crashed / Unknown Crash"**: Jarvis는 비정상 종료의 원인(예외 내용과 직전에 하던 작업)을 기록해 두었다가, **다음 실행 때 채팅창 첫 메시지로 알려 줍니다.** 같은 내용이 파일 앱 › Jarvis › Logs › `previous-crash.txt`에도 저장됩니다. 그 메시지(또는 Playground 크래시 화면에서 **Show Console**을 켰을 때 보이는 `JARVIS CRASH:` 줄)를 캡처해 주시면 정확히 고칠 수 있습니다.
- **"Loading… Crashed / Build failed"**: 앱 코드가 iPad에서 컴파일되지 않았다는 뜻입니다. Swift Playground 4.7의 컴파일러(Xcode 26.2~26.3 세대, Swift 6.2.x)는 Mac의 최신 Xcode보다 복잡한 식을 덜 참아서, 최신 Xcode에서는 되는 코드가 여기서는 "unable to type-check this expression in reasonable time"으로 실패할 수 있습니다. 저장소는 CI에서 Xcode 26.2·26.3·26.4로 실기기용 빌드를 매번 확인하므로, **최신 버전을 다시 내려받으십시오.** 그래도 실패하면 **Show Playground** → 오른쪽 위 빨간 오류 표시를 눌러 나오는 오류 목록을 캡처해 주십시오.
- **열자마자 "Loading failed" / `CouldNotFindNullRecordSeparator`**: Swift Playground가 `Package.swift`를 해석한 결과를 읽지 못했다는 뜻입니다.
  1. 저장소의 **최신 버전**을 다시 내려받으십시오. `Package.swift`를 영문(ASCII)만 쓰도록 고친 버전이어야 합니다. `Package.swift`에는 한글·특수문자(—, “ ” 등)를 넣지 마십시오. 권한 안내문도 영문으로 둡니다.
  2. 저장소 최상위 폴더가 아니라 **`Jarvis.swiftpm`** 을 여십시오.
  3. `Jarvis.swiftpm`을 파일 앱에서 **iCloud Drive › Swift Playground** 폴더(또는 나의 iPad › Swift Playground)로 옮긴 뒤, Swift Playground의 프로젝트 목록에서 여십시오. 예전에 열었던 사본은 지우고 새로 여는 것이 좋습니다.
  4. 그래도 같으면 Swift Playground에서 **새 빈 앱**을 만들어 실행해 보십시오. 빈 앱도 "Failed to load / Loading failed"로 실패한다면 Jarvis가 아니라 **iPadOS 27의 Swift Playground 문제**(Apple이 추적 중인 버그)입니다. iPadOS를 최신 버전으로 업데이트하고 기기를 재시동하십시오.
