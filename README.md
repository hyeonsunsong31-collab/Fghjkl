# J.A.R.V.I.S — 아이패드·아이폰 완전 로컬 에이전틱 AI

> "Wake up Jarvis." — "Jarvis at your service, sir."

클라우드·유료 서비스·PC 없이 **아이패드/아이폰 안에서만** 동작하는 영국 신사 집사형 에이전트 AI입니다. 처음 한 번 Wi-Fi로 음성·모델 파일을 받은 뒤에는 완전히 오프라인으로 작동합니다.

- **신경 코어**: 시냅스 구성요소를 가진 새 퍼셉트론(단기가소성·지연·수상돌기·3요인 학습)으로 만든 **206,158,430,208개** 퍼셉트론의 3D 뇌. 소뇌·대뇌 피질·시상과 기저핵·해마·편도체·시상하부·뇌간이 AI의 출력(무엇을 보고, 어떻게 행동하고, 얼마나 길고 어떤 속도로 말할지)을 제어하도록 학습합니다.
- **대화**: Apple Intelligence 온디바이스 모델(기본) + 선택형 Qwen3 4B "심층 사고"(자체 Swift/Metal 런타임).
- **음성**: 한국어·영어 동시 인식, "wake up Jarvis" 웨이크, 말하는 도중 끼어들기, Kokoro 영국 남성 뉴럴 음성(George).
- **홀로그램 UI + 3D 작업 공간**: 마우스 드래그·스크롤 확대, 카메라 손동작(집어서 이동, 양손으로 확대), 복제, 내보내기, 바탕화면 저장.
- **에이전트**: 앱 실행, 웹 검색·브라우저 제어, 웹 음악, 캘린더·미리 알림·연락처·파일, 손전등·밝기·음량·타이머, 단축어 브리지로 시스템 설정과 다른 앱까지.
- **전 기록**: 명령·작업·대화·설명(오류/답변/과정/소요 시간)·옵션·추천·생성 파일·워크플로 체크포인트를 모두 저장(파일 앱 › Jarvis).

## 빠른 시작 (아이패드, PC 불필요)

1. Swift Playgrounds 4.7 이상 설치, 아이패드는 iPadOS 26 이상 + Apple Intelligence 켜기.
2. 이 저장소(브랜치 `claude/ios-ipad-jarvis-agent-db6yyi`)를 **Download ZIP** → 파일 앱에서 압축 해제.
3. **`Jarvis.swiftpm`** 을 열고 ▶︎ 실행 → 온보딩에서 권한 허용·Kokoro 음성 내려받기.
4. "**Wake up Jarvis**"라고 말하거나 오른쪽 아래 주황색 **비상 웨이크 버튼**을 누르십시오.

앱 밖에서 깨우기(Siri·AssistiveTouch), 자동 실행에 가까운 설정, 바탕화면 자동화, 아이폰 설치 방법은 **[docs/SETUP.ko.md](docs/SETUP.ko.md)** 에 있습니다.

## 말해 보기

| 한국어 | English |
|---|---|
| 3D 공간 열어줘 · 빨간 큐브 세 개 만들어 · 두 번 복제해 | Open the 3D space · Make three red cubes · Clone it twice |
| 두 배로 키워 · 왼쪽으로 30cm 옮겨 · 헬멧 만들어 | Make it twice as big · Move it left 30 cm · Build a helmet |
| 손 인식 켜 / 꺼 · 배경화면으로 저장해 · 모델 내보내기 | Hand tracking on / off · Set as wallpaper · Export the model |
| 아이유 노래 틀어줘 · 일시정지 · 다음 곡 | Play Bohemian Rhapsody · Pause · Next song |
| 서울 날씨 검색해줘 · 카카오톡 열어줘 · 5분 타이머 | Search for ramen in Seoul · Open Spotify · Timer for 5 minutes |
| 마이크 꺼 · 음성 꺼 · 심층 사고 켜 · 천천히 말해 | Mute the mic · Text only · Deep think on · Speak slower |
| 기록 보여줘 · 신경망 보여줘 · 하던 작업 계속해 | Show history · Show the neural core · Resume the task |

복합 명령("3D 공간 열고 큐브 만들어서 복제해")과 자유로운 표현도 처리합니다. 화면의 모든 버튼은 같은 명령을 실행합니다.

## iOS가 허용하지 않는 부분

전원을 켜면 앱이 자동 실행되는 기능, 다른 앱 위에 임의의 버튼을 띄우는 기능, 시스템 바탕화면 직접 변경, 다른 앱 데이터에 대한 전면 접근, 2000억 개 퍼셉트론 전체의 동시 계산은 **iOS(또는 기기 메모리)가 허용하지 않습니다.** Jarvis는 각각을 공식적으로 가능한 가장 가까운 방법(단축어 자동화, AssistiveTouch·PiP, 사진 앨범+배경화면 자동화, 단축어 브리지, 절차적 연결)으로 구현했습니다. 요구사항별 대조표: **[docs/LIMITATIONS.ko.md](docs/LIMITATIONS.ko.md)**

## 구조

```
Jarvis.swiftpm/                 ← Swift Playgrounds에서 여는 앱 (iPad·iPhone 겸용, iOS 26+)
  Package.swift, Info-Extra.plist
  Sources/Core/                 플랫폼 독립 핵심(리눅스·macOS에서 단위 테스트)
    Neuro/                      시냅스 퍼셉트론, 3D 격자, 절차적 연결, 뇌 영역, 출력 제어기
    Language/                   한/영 명령 문법, 웨이크워드, 언어 감지, 숫자·시간 파싱
    Agent/  Gesture/  Audio/    워크플로·페르소나·추천, 손동작 해석, 음성 활동 감지
    TTS/  LM/  Space/           영국식 G2P, Qwen3 런타임(CPU·Metal), 3D 메시·장면
  Sources/App · Agent · LLM · Voice · Tools · Memory · Hologram · Space3D · Presence · Support
Package.swift, Tests/           개발용 테스트 패키지 (swift test)
tools/reference/                NumPy·HF tokenizers 참조 데이터 생성 스크립트
docs/                           아키텍처·설정·단축어·제약 문서
```

자세한 설계(퍼셉트론 수식, 격자 개수, 뇌 루프, 런타임): **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**

## 개발·검증

```bash
swift test          # 67개 단위 테스트 (신경 코어, 문법, G2P, 3D, Qwen3 런타임 vs NumPy·HF 참조)
```

GitHub Actions가 매 커밋마다 리눅스·macOS 단위 테스트, iOS 시뮬레이터용 전체 앱 빌드(Xcode 26), iPad 시뮬레이터 실행 스모크 테스트를 수행합니다.

## 사용한 공개 모델·데이터 (모두 기기에 1회 다운로드)

| 구성 | 출처 | 라이선스 |
|---|---|---|
| Kokoro-82M Core ML (영국 남성 음성 `bm_george` 등) | [aufklarer/Kokoro-82M-CoreML-INT8](https://huggingface.co/aufklarer/Kokoro-82M-CoreML-INT8), 원본 [hexgrad/Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) | Apache-2.0 |
| 영국식 발음 사전 gb_gold / gb_silver | [hexgrad/misaki](https://github.com/hexgrad/misaki) | Apache-2.0 |
| 심층 사고 모델(선택) | [mlx-community/Qwen3-4B-Instruct-2507-4bit](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit), [Qwen3-1.7B-4bit](https://huggingface.co/mlx-community/Qwen3-1.7B-4bit) | Apache-2.0 |
| 대화 기본 모델 | Apple Foundation Models (iOS 내장) | Apple |

"Jarvis"는 이 개인 프로젝트에서 사용자가 지정한 비서 이름이며, 홀로그램 디자인은 영화 에셋을 쓰지 않은 독자 디자인입니다.
