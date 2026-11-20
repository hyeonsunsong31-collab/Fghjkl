# Jarvis 아키텍처

```
┌─────────────────────────────── Jarvis.swiftpm (하나의 앱 모듈) ───────────────────────────────┐
│                                                                                               │
│  입력  음성(ko-KR·en-GB 동시 인식, VAD, 웨이크워드) · 텍스트 · 버튼 · 단축어/URL · 손동작        │
│    │                                                                                          │
│    ▼                                                                                          │
│  Orchestrator ── CommandGrammar(한/영 60여 기능, 퍼지·복합 명령)                                 │
│    │                 │                                                                        │
│    │                 ▼                                                                        │
│    │        ┌──────────────────── Brain (시냅스 퍼셉트론 신경 코어) ───────────────────┐        │
│    │        │ Thalamus 맥락 게이팅 · Cortex 의도 · BasalGanglia 행동 선택 ·            │        │
│    │        │ Cerebellum 시간 예측/미세 제어 · Hippocampus 기억 · 신경조절물질          │        │
│    │        └────────────────────────────────────────────────────────────────────────┘        │
│    │                 │ decision: action, gated context, temperature/verbosity/speech rate   │
│    ├── fastCommand ──▶ FastCommandExecutor ─▶ 3D 공간·음악·웹·기기·앱·단축어 브리지            │
│    └── LLM ─────────▶ AppleFMEngine(Foundation Models + 8 tools) / DeepThink(Qwen3) / Fallback │
│                          │ streaming text                                                     │
│                          ▼                                                                    │
│                    OutputController(언어·격식·sir·마크다운·허위 완료 주장 검사 → 교정/재생성)    │
│                          │                                                                    │
│  출력  SpeechOutput(Kokoro bm_george / 한국어 시스템 남성 음성, 문장 단위 스트리밍, 끼어들기)      │
│        홀로그램 UI(채팅·설명/옵션/추천 카드·워크플로)  ·  RecordKeeper(SQLite+JSONL 전 기록)        │
│                          │                                                                    │
│  학습  다음 입력의 반응(칭찬·정정·끼어들기·추가 설명 요청) → Brain.feedback → 도파민/등반섬유 학습  │
└───────────────────────────────────────────────────────────────────────────────────────────────┘
```

## 1. 시냅스 퍼셉트론 (`Core/Neuro/SynapticPerceptron.swift`, `Synapse.swift`)

고전 퍼셉트론 `y = φ(Σ wᵢxᵢ + b)` 에 **시냅스 구성요소**를 추가했습니다.

| 구성 | 수식 / 의미 |
|---|---|
| 시냅스 전달 | `sᵢ = sign(전달물질) · wᵢ · (uᵢRᵢ/Uᵢ) · xᵢ(t − dᵢ)` |
| 단기 가소성(Tsodyks–Markram) | 회복 `u ← u + (U − u)/τ_f`, `R ← R + (1 − R)/τ_d`; 사용 `u ← u + U(1 − u)x`, `R ← R − uRx` |
| 지연 | `dᵢ` = 3D 격자 거리 / 64 틱 (링버퍼) |
| 수상돌기 가지 | `D_b = g_b · σ(k(Σ_{i∈b} sᵢ − θ_b))` → 단일 뉴런이 XOR 계산 가능 |
| 막전위 | `v ← αv + Σ_b D_b + b` (α=0이면 고전 퍼셉트론과 동일 — 테스트로 확인) |
| 항상성 임계 | `θ ← θ + η_θ(r̄ − r_target)` |
| 출력 | `y = φ(v − θ) · gain(ACh)`, φ ∈ {sigmoid, tanh, ReLU, rate, spiking+불응기} |
| 적격흔적 | `eᵢ ← λeᵢ + preᵢ · φ'(v − θ)` (STDP 변형 포함) |
| 3요인 학습 | `Δwᵢ = η · gain(NE) · M · eᵢ`, `M = 수용체·[DA, ACh, NE, 5-HT] + 교사 신호` |
| 소뇌 LTD | 등반섬유 오차 > 0 → 활성 평행섬유 시냅스 억압 (Marr–Albus–Ito, 정규화 LMS) |

**궁극 목표 = 출력 제어**: `OutputController`가 매 응답의 제어 위반(언어 불일치·반말·"sir" 누락·허위 완료 주장·과도한 길이·마크다운)을 측정하고, `Brain.controlScore`(첫 시도 무위반 비율의 이동 평균)와 보상 신호로 모든 가소성을 구동합니다.

## 2. 3D 격자와 절차적 연결 (`Lattice3D.swift`, `ProceduralConnectome.swift`)

- 격자 8192 × 6144 × 4096 = **206,158,430,208** 퍼셉트론, 뉴런 ID = 선형 인덱스. 각 영역의 정확한 개수는 구간 압축 계산으로 산출(테스트로 합계 검증).

| 계통 | 퍼셉트론 수 | 비율 | 세부 |
|---|---:|---:|---|
| 소뇌 | 161,061,273,600 | 78.1% | 과립층·푸르키니에층·분자층(16개 엽 주기), 심부핵 |
| 대뇌 피질 | 38,654,705,664 | 18.75% | L1, L2/3, L4, L5, L6 (7겹으로 접힌 시트) |
| 시상 | 1,610,612,736 | 0.78% | 감각 중계, 운동 중계(VA/VL), 시상침, MD, 망상핵(TRN) |
| 기저핵 | 1,610,612,736 | 0.78% | 선조체, GPe, GPi, STN, SNc |
| 뇌간 | 1,342,177,280 | 0.65% | 교뇌, 하올리브, VTA, 청반, 봉선핵, 망상체, 기저전뇌 |
| 해마 | 1,073,741,824 | 0.52% | 치상회, CA3, CA1 |
| 편도체 | 536,870,912 | 0.26% | |
| 시상하부 | 268,435,456 | 0.13% | |

- 뉴런 n의 k번째 시냅스 = `f(seed, n, k)` (SplitMix64 카운터 해시, 정수 연산만 사용 → CPU·GPU 동일). 규칙: 국소 가우시안 이웃, 영역 간 위상 보존 경로(피질L5→교뇌→과립세포, 과립→푸르키니에(평행섬유), 푸르키니에→심부핵→시상→피질L4, 피질L6↔시상/TRN, 피질→선조체→GPi→시상, SNc→선조체, 하올리브→푸르키니에, 해마↔피질…). 영역별 평균 팬아웃 32~2000, **논리 시냅스 82,257,008,132,096개(8.2×10¹³)**.
- 학습된 변화만 `PlasticityStore`(오픈어드레싱 해시맵)에 Δw로 저장, 해마 리플레이(충전 중/유휴)로 강화.
- `LatticeSimulator`: 활성 뉴런만 팬아웃을 즉석 생성해 전파하는 이벤트 기반 시뮬레이션, 시상하부가 배터리·발열에 맞춰 틱당 이벤트 예산을 조절. 신경망 홀로그램에 실시간 표시.

## 3. 뇌 루프 (`Brain.swift`, `Regions/*`)

| 영역 | 구현 | AI 출력 제어에서의 역할 |
|---|---|---|
| 시상 | 중계 퍼셉트론(맥락 특성 → 점수) + TRN 측면 억제(ACh로 날카로워짐, 토큰 예산) | 대화·기억·장면·기기·도구 결과 중 **무엇을 언어 모델에 보여줄지** 결정 (Foundation Models 4K 창) |
| 피질 | L4 무작위 희소(k-WTA) → L2/3 헤비안 개념 코드+작업기억 → L5 의도 판독, L6 → 시상 피드백 | 의도 인식(문법이 놓친 다른 표현을 자기지도 학습으로 일반화) |
| 기저핵 | D1(Go)/D2(NoGo) + 비평가, 소프트맥스(NE 탐색, 5-HT 인내) | 즉시 명령 / 대화 / 도구 사용 / 되묻기 / 심층 사고 선택, 도파민 RPE 학습 |
| 소뇌 | 이끼섬유 34 → 과립 4096(5% 활성) → 푸르키니에 4 미세영역 → 심부핵 | **소요 시간 예측**(3초 이상이면 안내), 장황함·온도·말 속도 미세 조정(끼어들기/정정/"자세히" 피드백으로 학습) |
| 해마 | 치상회 8192 패턴 분리 + CA3 역색인 완성 | 일화 기억 저장·회상 → 시상 채널 |
| 편도체 | 긴급도·감정가 평가 | NE 상승, 응답 간결화 |
| 시상하부 | 배터리·발열·저전력 → 연산 예산 | 심층 사고 허용 여부, 격자 시뮬레이션 예산 |
| 뇌간 | 각성 상태기계, VTA/LC/봉선핵/기저전뇌, 하올리브 | 웨이크/수면, 신경조절물질 방송 |

모든 가중치는 `Documents/Jarvis/Brain`에 저장되어 앱을 다시 켜도 학습이 이어집니다.

## 4. 언어 모델

- **AppleFMEngine** (`LLM/AppleFMEngine.swift`): `LanguageModelSession` + 페르소나 지시 + 8개 도구(`run_command`, `web_search`, `read_page`, `calendar`, `reminders`, `contacts`, `memory`, `files`) + `@Generable GeneratedReply`(reply·오류 설명·과정 설명·옵션 3개·추천)를 스트리밍. 웨이크 시 `prewarm()`.
- **DeepThink** (`Core/LM/*`, `LLM/DeepThink/*`): 순수 Swift 런타임. safetensors(mmap), 바이트 BPE 토크나이저(실제 Qwen3 어휘와 일치 검증), Qwen3 디코더(RMSNorm, q/k-norm, RoPE, GQA, SwiGLU, KV 캐시), MLX 4비트 affine 역양자화. GPU 백엔드는 런타임 컴파일 Metal 커널, **정렬되지 않은 MLX 파일도 복사 없이** 바이트 단위로 읽음. 로드 시 GPU 결과를 CPU 참조와 비교하는 자가 검증 후 실패하면 CPU로 대체.
- **FallbackEngine**: 모델이 없을 때도 모든 기본 명령은 동작하고, 대화는 기억 회상·안내로 처리.

## 5. 음성 (`Voice/*`)

- `AudioEngineHub`: 하나의 `AVAudioEngine`, 음성 처리 I/O(에코 제거) 켜짐, 다른 앱 오디오 덕킹 최소화. 모든 음성 출력이 같은 엔진을 통과하므로 말하는 중에도 사용자 목소리를 들을 수 있습니다.
- `SpeechInputService`: ko-KR·en-GB 온디바이스 인식기를 동시에 실행, 신뢰도·문자 비율로 언어 선택, 에너지 VAD로 발화 종료 감지, 웨이크워드(발음 변이·한국어 표현 허용).
- `SpeechOutputService`: 문장 단위 스트리밍, 즉시 중단(끼어들기). 영어 = **Kokoro-82M**(`aufklarer/Kokoro-82M-CoreML-INT8`, E2E Core ML: `input_ids`/`attention_mask`/`ref_s`/`speed`/`random_phases` → 24kHz), G2P = misaki 영국 사전(gb_gold/gb_silver) → 접미사 처리 → Core ML BART G2P(미국식→영국식 변환) → 규칙 기반. 한국어 = 최고 품질 남성 시스템 음성.

## 6. 3D 공간 (`Space3D/*`, `Core/Space/*`)

`SceneDocument`(Codable, 실행 취소/다시 실행, 대상 해석 "그거·빨간 큐브·두 번째·전부") → RealityKit `ARView(.nonAR)` 엔티티. 도형 메시는 플랫폼 독립 생성기(모든 삼각형이 바깥을 향하는지 테스트로 검증)에서 만들어 렌더링과 OBJ/USDZ 내보내기에 함께 사용. 조립 모델은 Foundation Models 유도 생성(`GeneratedModelSpec`) 또는 내장 템플릿(헬멧·로봇·자동차·집·나무·로켓 등).

## 7. 기록 (`Memory/RecordKeeper.swift`)

테이블: `commands`, `runs`, `steps`, `messages`, `explanations(kind: error|answer|process|timeEstimate)`, `options`, `recommendations`, `artifacts(path, UTI, size, SHA-256)`, `checkpoints(workflow JSON + 3D 장면)`, `kv`. 모든 쓰기는 일자별 JSONL 저널에도 남습니다.

## 8. 검증

- `swift test` (루트 `Package.swift`, 리눅스·macOS): 신경 코어(퍼셉트론 수식·STP·XOR·지연·학습, 격자 개수·샘플링·연결 해부학, 영역 학습), 문법(한/영 100여 문장), 웨이크워드, 숫자·시간 파싱, 페르소나 출력 제어, G2P, 메시, 장면, LM 런타임(NumPy 참조 로짓 일치, HF 토크나이저 일치).
- GitHub Actions(macOS 26, Xcode 26): iOS 시뮬레이터용 전체 앱 빌드 + iPad 시뮬레이터 실행·스크린샷.
