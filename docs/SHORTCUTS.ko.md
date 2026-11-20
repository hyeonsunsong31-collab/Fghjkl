# Jarvis Bridge 단축어 레시피

iOS는 앱이 와이파이·블루투스·집중 모드 같은 시스템 설정을 직접 바꾸거나 다른 앱을 조작하는 것을 허용하지 않습니다. 대신 **단축어(Shortcuts)** 는 이런 동작을 공식적으로 지원하므로, Jarvis는 `Jarvis Bridge`라는 단축어에 JSON 명령을 보내 실행을 위임합니다.

Jarvis가 보내는 형식(텍스트 입력):

```json
{"action": "setting", "setting": "wifi", "value": "off"}
```

| action | 추가 키 | 예시 음성 명령 |
|---|---|---|
| `setting` | `setting` = `wifi` · `bluetooth` · `doNotDisturb` · `darkMode` · `lowPower` · `airplaneMode` · `hotspot` · `cellular`, `value` = `on` · `off` · `toggle` | "와이파이 꺼", "turn on dark mode", "방해 금지 켜" |
| (사용자 정의) | 원하는 키 | 아래 "확장하기" 참조 |

> 동작 이름은 iOS 버전에 따라 조금씩 다를 수 있습니다. 단축어 편집기의 검색창에 괄호 안의 영어 이름이나 핵심 단어("Wi-Fi", "블루투스", "모양")를 입력하면 찾을 수 있습니다.

## 만들기 (약 5분)

1. **단축어** 앱 › **+** › 이름을 정확히 **Jarvis Bridge** 로 지정.
2. 단축어 설정(ⓘ)에서 "공유 시트에 표시"는 꺼도 됩니다. 입력 유형은 **텍스트**.
3. 다음 동작을 차례로 추가합니다.

```
① 입력에서 사전 가져오기            (Get Dictionary from Input)   입력: 단축어 입력
② 사전 값 가져오기                  (Get Dictionary Value)        키: action   → 변수 이름 "Action"
③ 사전 값 가져오기                  키: setting                  → 변수 "Setting"
④ 사전 값 가져오기                  키: value                    → 변수 "Value"
⑤ 만약 Action 이(가) setting 과 같음 (If)
     ⑥ 만약 Setting 이(가) wifi 와 같음
          만약 Value 가 off 와 같음 → Wi-Fi 설정: 끔        (Set Wi-Fi)
          그렇지 않으면           → Wi-Fi 설정: 켬
     ⑦ 만약 Setting 이(가) bluetooth 와 같음
          만약 Value 가 off → 블루투스 설정: 끔 / 그렇지 않으면 켬   (Set Bluetooth)
     ⑧ 만약 Setting 이(가) doNotDisturb 와 같음
          집중 모드 설정: 방해 금지, Value 에 따라 켬/끔             (Set Focus)
     ⑨ 만약 Setting 이(가) darkMode 와 같음
          모양 설정: Value 가 on 이면 다크, 아니면 라이트             (Set Appearance)
     ⑩ 만약 Setting 이(가) lowPower 와 같음 → 저전력 모드 설정          (Set Low Power Mode)
     ⑪ 만약 Setting 이(가) airplaneMode 와 같음 → 에어플레인 모드 설정  (Set Airplane Mode)
     ⑫ 만약 Setting 이(가) hotspot 와 같음 → 개인용 핫스팟 설정        (Set Personal Hotspot)
     ⑬ 만약 Setting 이(가) cellular 와 같음 → 셀룰러 데이터 설정       (Set Cellular Data)
⑭ (마지막) URL 열기: jarvis://bridge?status=success   ← Jarvis로 돌아가기
```

`toggle` 값을 쓰려면 각 "설정" 동작의 옵션에서 **토글**을 선택한 분기를 하나 더 추가하십시오.

## 확장하기 (다른 앱·홈 장비·메시지)

브리지는 `action` 값에 따라 무엇이든 실행할 수 있습니다. 예를 들어 다음 분기를 추가하면:

| action | 분기 안의 동작 | Jarvis에게 말하기 |
|---|---|---|
| `home` | 홈 제어(Control Home) › 원하는 장면/액세서리 | "단축어 Jarvis Bridge 실행" 대신 개별 단축어를 쓰는 편이 간단합니다(아래) |
| `message` | 메시지 보내기(Send Message): 받는 사람 = 사전 값 `to`, 내용 = `body` | 문자 보내기는 Jarvis가 메시지 앱을 미리 채워 열어 줍니다 |
| `wallpaper` | 사진 찾기(Jarvis Space, 최신 1) → 배경화면 설정 | "배경화면으로 저장해" 후 자동화로 처리하는 것을 권장 |

가장 쉬운 확장 방법은 **원하는 동작마다 단축어를 하나씩 만들고 이름을 붙이는 것**입니다. Jarvis는 "단축어 '거실 불 켜기' 실행해" / "run the shortcut 'Morning Routine'"처럼 **이름으로 어떤 단축어든 실행**할 수 있습니다. 다른 앱이 제공하는 단축어 동작(App Intents)도 이런 방식으로 모두 Jarvis가 쓸 수 있습니다.

## "Wake up Jarvis" 단축어 (복습)

`URL 열기: jarvis://wake` 하나만 넣고 이름을 **Wake up Jarvis** 로 저장하십시오. Siri·AssistiveTouch·제어 센터·자동화에서 자비스를 깨우는 데 쓰입니다. 자세한 설정은 [SETUP.ko.md](SETUP.ko.md) 2·3장을 참고하십시오.
