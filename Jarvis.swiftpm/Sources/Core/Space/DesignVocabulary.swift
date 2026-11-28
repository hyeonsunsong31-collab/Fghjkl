import Foundation

/// Words for design subjects, components, colours, materials, styles and sizes
/// (English and Korean), used to read the details of a design request.
enum DesignVocabulary {
    /// Objects the parametric library builds (key → words).
    static let subjects: [(key: String, words: [String])] = [
        ("car", ["car", "automobile", "sedan", "coupe", "supercar", "sports car", "race car", "racecar", "racing car", "vehicle", "jeep", "suv",
                 "taxi", "police car", "truck", "lorry", "pickup", "fire truck", "bus", "van", "minivan",
                 "자동차", "승용차", "차량", "스포츠카", "레이싱카", "경주용차", "슈퍼카", "택시", "경찰차", "지프", "트럭", "소방차", "버스", "밴", "차"]),
        ("robot", ["robot", "android", "mech", "mecha", "cyborg", "humanoid", "로봇", "안드로이드", "메카", "사이보그", "휴머노이드"]),
        ("helmet", ["helmet", "헬멧", "투구"]),
        ("house", ["house", "home", "cottage", "hut", "log cabin", "villa", "mansion", "bungalow", "집", "주택", "오두막", "별장", "저택", "이층집", "단독주택", "전원주택"]),
        ("building", ["building", "skyscraper", "high rise", "highrise", "tower block", "apartment", "office building",
                      "빌딩", "건물", "아파트", "고층빌딩", "마천루", "오피스"]),
        ("castle", ["castle", "fortress", "palace", "citadel", "성", "성채", "궁전", "요새", "궁궐"]),
        ("tower", ["tower", "lighthouse", "clock tower", "watchtower", "탑", "타워", "등대", "시계탑", "망루"]),
        ("tree", ["tree", "pine", "palm", "oak", "christmas tree", "bonsai", "나무", "소나무", "야자수", "야자나무", "크리스마스트리", "크리스마스 트리", "전나무", "벚나무", "참나무", "분재"]),
        ("flower", ["flower", "rose", "tulip", "sunflower", "daisy", "꽃", "장미", "튤립", "해바라기", "데이지", "꽃송이"]),
        ("rocket", ["rocket", "missile", "로켓", "미사일"]),
        ("spaceship", ["spaceship", "space ship", "starship", "spacecraft", "ufo", "flying saucer", "우주선", "비행접시", "유에프오", "우주 비행선"]),
        ("airplane", ["airplane", "aeroplane", "jet", "aircraft", "airliner", "fighter jet", "fighter", "jet plane", "비행기", "제트기", "여객기", "전투기", "항공기"]),
        ("helicopter", ["helicopter", "chopper", "헬리콥터", "헬기"]),
        ("drone", ["drone", "quadcopter", "드론"]),
        ("boat", ["boat", "ship", "yacht", "sailboat", "sailing boat", "speedboat", "canoe", "보트", "배", "요트", "선박", "범선", "돛단배", "모터보트", "여객선"]),
        ("table", ["table", "desk", "테이블", "책상", "탁자", "식탁"]),
        ("chair", ["chair", "stool", "throne", "armchair", "의자", "스툴", "왕좌"]),
        ("sofa", ["sofa", "couch", "settee", "소파"]),
        ("bed", ["bed", "침대"]),
        ("lamp", ["lamp", "desk lamp", "floor lamp", "table lamp", "램프", "스탠드", "전등", "조명등"]),
        ("mug", ["mug", "cup", "teacup", "coffee cup", "머그", "머그컵", "컵", "찻잔", "커피잔"]),
        ("bottle", ["bottle", "flask", "병", "물병", "와인병", "유리병"]),
        ("snowman", ["snowman", "snow man", "눈사람"]),
        ("sword", ["sword", "katana", "saber", "sabre", "longsword", "검", "칼", "장검", "대검"]),
        ("shield", ["shield", "방패"]),
        ("crown", ["crown", "tiara", "왕관", "티아라"]),
        ("computer", ["computer", "monitor", "pc", "desktop computer", "laptop", "컴퓨터", "모니터", "노트북", "데스크톱"]),
        ("windmill", ["windmill", "wind turbine", "풍차", "풍력발전기", "풍력 발전기"]),
        ("reactor", ["reactor", "arc reactor", "power core", "energy core", "리액터", "아크 리액터", "에너지 코어"]),
        ("bridge", ["bridge", "교량"]),
    ]

    /// Variants refine a subject (subject, variant, words).
    static let variants: [(subject: String, variant: String, words: [String])] = [
        ("car", "truck", ["truck", "lorry", "pickup", "fire truck", "트럭", "소방차", "픽업"]),
        ("car", "bus", ["bus", "minibus", "버스"]),
        ("car", "van", ["van", "minivan", "밴", "승합차"]),
        ("car", "suv", ["suv", "jeep", "off road", "offroad", "지프", "오프로드"]),
        ("car", "police", ["police", "cop", "경찰"]),
        ("car", "taxi", ["taxi", "cab", "택시"]),
        ("car", "sports", ["sports", "sport", "sporty", "racing", "race", "racecar", "supercar", "super car", "스포츠", "레이싱", "경주", "슈퍼카"]),
        ("tree", "pine", ["pine", "fir", "spruce", "conifer", "christmas", "소나무", "전나무", "침엽수", "크리스마스"]),
        ("tree", "palm", ["palm", "coconut", "야자", "야자수", "코코넛"]),
        ("tree", "cherry", ["cherry blossom", "sakura", "cherry", "벚꽃", "벚나무"]),
        ("tree", "round", ["oak", "apple tree", "maple", "round", "참나무", "사과나무", "단풍"]),
        ("house", "cottage", ["cottage", "hut", "log cabin", "오두막"]),
        ("house", "mansion", ["mansion", "villa", "저택", "별장"]),
        ("building", "skyscraper", ["skyscraper", "high rise", "highrise", "마천루", "고층"]),
        ("boat", "sail", ["sailboat", "sailing", "sail", "yacht", "돛단배", "범선", "요트", "돛"]),
        ("boat", "speed", ["speedboat", "motorboat", "speed boat", "모터보트", "쾌속정"]),
        ("airplane", "fighter", ["fighter", "fighter jet", "jet fighter", "전투기"]),
        ("airplane", "airliner", ["airliner", "passenger", "여객기"]),
        ("spaceship", "ufo", ["ufo", "flying saucer", "saucer", "비행접시", "유에프오"]),
        ("tower", "lighthouse", ["lighthouse", "등대"]),
        ("tower", "clock", ["clock tower", "clock", "시계탑", "시계"]),
        ("flower", "sunflower", ["sunflower", "해바라기"]),
        ("flower", "tulip", ["tulip", "튤립"]),
        ("flower", "rose", ["rose", "장미"]),
        ("chair", "stool", ["stool", "스툴"]),
        ("chair", "throne", ["throne", "왕좌"]),
        ("chair", "office", ["office chair", "swivel", "사무용"]),
        ("lamp", "floor", ["floor lamp", "standing lamp", "플로어", "장스탠드"]),
        ("computer", "laptop", ["laptop", "notebook", "노트북"]),
        ("robot", "cute", ["cute", "chibi", "toy", "baby", "귀여운", "아기", "장난감"]),
        ("robot", "spider", ["spider", "거미"]),
        ("sword", "katana", ["katana", "카타나", "일본도"]),
    ]

    /// Components (key → words). Keys are the part names the library and the language model use.
    static let components: [(key: String, words: [String])] = [
        ("body", ["body", "chassis", "hull", "fuselage", "torso", "몸체", "차체", "몸통", "동체", "선체", "본체"]),
        ("cabin", ["cabin", "cab", "캐빈", "운전석"]),
        ("cargo", ["cargo", "container", "trailer", "짐칸", "화물칸", "적재함", "컨테이너"]),
        ("stage", ["stage", "단"]),
        ("wheel", ["wheel", "tire", "tyre", "rim", "바퀴", "타이어", "휠", "앞바퀴", "뒷바퀴"]),
        ("window", ["window", "windshield", "windscreen", "창문", "유리창", "앞유리", "창"]),
        ("door", ["door", "entrance", "문", "도어", "출입문", "현관문", "현관"]),
        ("roof", ["roof", "rooftop", "지붕"]),
        ("wall", ["wall", "벽", "외벽", "벽면"]),
        ("chimney", ["chimney", "굴뚝"]),
        ("floor", ["story", "storey", "floor", "level", "층"]),
        ("spoiler", ["spoiler", "rear wing", "스포일러", "리어윙"]),
        ("light", ["light", "headlight", "headlamp", "taillight", "led", "라이트", "헤드라이트", "전조등", "불빛", "미등", "조명"]),
        ("leg", ["leg", "다리"]),
        ("arm", ["arm", "팔"]),
        ("hand", ["hand", "claw", "gripper", "손", "집게"]),
        ("head", ["head", "머리"]),
        ("eye", ["eye", "눈", "눈동자"]),
        ("antenna", ["antenna", "antennae", "aerial", "안테나", "더듬이"]),
        ("visor", ["visor", "faceplate", "face plate", "바이저", "얼굴판", "안면"]),
        ("horn", ["horn", "뿔"]),
        ("wing", ["wing", "날개"]),
        ("fin", ["fin", "지느러미", "핀"]),
        ("engine", ["engine", "thruster", "booster", "jet engine", "nozzle", "엔진", "추진기", "부스터", "분사구"]),
        ("propeller", ["propeller", "rotor", "prop", "프로펠러", "로터"]),
        ("seat", ["seat", "cushion", "좌석", "시트", "방석", "쿠션"]),
        ("backrest", ["backrest", "back rest", "chair back", "등받이"]),
        ("armrest", ["armrest", "arm rest", "팔걸이"]),
        ("tabletop", ["tabletop", "table top", "top surface", "상판"]),
        ("drawer", ["drawer", "서랍"]),
        ("trunk", ["trunk", "줄기", "나무 기둥", "밑동"]),
        ("leaves", ["leaves", "leaf", "foliage", "canopy", "잎", "나뭇잎", "잎사귀"]),
        ("fruit", ["fruit", "apple", "열매", "과일", "사과"]),
        ("petal", ["petal", "꽃잎"]),
        ("stem", ["stem", "stalk", "꽃대", "꽃줄기"]),
        ("pot", ["pot", "flowerpot", "planter", "화분"]),
        ("shade", ["shade", "lampshade", "갓", "전등갓"]),
        ("bulb", ["bulb", "light bulb", "전구"]),
        ("handle", ["handle", "grip", "hilt", "손잡이", "자루"]),
        ("lid", ["lid", "cap", "cork", "뚜껑", "마개"]),
        ("label", ["label", "라벨", "상표"]),
        ("blade", ["blade", "칼날", "날"]),
        ("guard", ["guard", "crossguard", "cross guard", "코등이", "가드"]),
        ("gem", ["gem", "jewel", "diamond", "ruby", "sapphire", "emerald", "보석", "다이아몬드", "다이아", "루비", "사파이어", "에메랄드"]),
        ("cockpit", ["cockpit", "canopy glass", "조종석", "캐노피"]),
        ("tail", ["tail", "꼬리"]),
        ("mast", ["mast", "돛대"]),
        ("sail", ["sail", "돛"]),
        ("tower", ["tower", "turret", "spire", "탑", "첨탑", "망루", "포탑"]),
        ("flag", ["flag", "banner", "pennant", "깃발", "깃대"]),
        ("gate", ["gate", "portcullis", "성문", "대문"]),
        ("screen", ["screen", "display", "화면", "스크린", "디스플레이"]),
        ("keyboard", ["keyboard", "키보드", "자판"]),
        ("stand", ["stand", "pedestal", "받침대", "거치대"]),
        ("base", ["base", "plinth", "받침", "베이스", "밑판"]),
        ("pillow", ["pillow", "베개"]),
        ("blanket", ["blanket", "duvet", "quilt", "이불", "담요"]),
        ("headboard", ["headboard", "헤드보드", "머리판"]),
        ("nose", ["nose", "코"]),
        ("mouth", ["mouth", "smile", "입"]),
        ("hat", ["hat", "top hat", "모자"]),
        ("scarf", ["scarf", "muffler", "목도리", "스카프"]),
        ("button", ["button", "단추", "버튼"]),
        ("porthole", ["porthole", "둥근 창"]),
        ("stripe", ["stripe", "racing stripe", "줄무늬", "스트라이프"]),
        ("trim", ["trim", "accent", "detail", "장식", "테두리", "포인트"]),
        ("crest", ["crest", "plume", "mohawk", "볏", "깃털"]),
        ("garage", ["garage", "차고"]),
        ("fence", ["fence", "울타리"]),
        ("stairs", ["stairs", "steps", "staircase", "계단"]),
        ("balcony", ["balcony", "발코니", "베란다"]),
        ("gear", ["landing gear", "skid", "착륙장치", "스키드"]),
        ("camera", ["camera", "카메라"]),
        ("solar", ["solar panel", "solar", "태양광", "태양전지"]),
        ("dish", ["satellite dish", "dish", "접시 안테나"]),
        ("cannon", ["cannon", "gun", "blaster", "laser", "weapon", "대포", "포신", "레이저", "무기"]),
        ("core", ["core", "chest light", "reactor core", "코어"]),
        ("exhaust", ["exhaust", "muffler pipe", "배기구", "머플러"]),
        ("bumper", ["bumper", "범퍼"]),
        ("mirror", ["mirror", "side mirror", "사이드미러", "거울"]),
        ("grille", ["grille", "grill", "그릴"]),
        ("siren", ["siren", "light bar", "lightbar", "사이렌", "경광등"]),
        ("ladder", ["ladder", "사다리"]),
        ("funnel", ["funnel", "smokestack", "연통"]),
        ("clock", ["clock", "clock face", "시계"]),
        ("lantern", ["lantern", "beacon", "등명기", "랜턴"]),
    ]

    static let colors: [(key: String, words: [String])] = [
        ("navy", ["navy blue", "navy", "dark blue", "남색", "네이비", "진한 파란"]),
        ("cyan", ["sky blue", "light blue", "cyan", "aqua", "turquoise", "하늘색", "청록", "시안", "민트"]),
        ("darkgreen", ["dark green", "forest green", "진녹색", "짙은 초록"]),
        ("darkgray", ["dark gray", "dark grey", "charcoal", "gunmetal", "진회색", "차콜"]),
        ("red", ["red", "crimson", "scarlet", "빨간", "빨강", "붉은", "레드", "빨갛", "적색"]),
        ("maroon", ["maroon", "burgundy", "버건디", "자주색", "와인색"]),
        ("orange", ["orange", "주황", "오렌지"]),
        ("yellow", ["yellow", "노란", "노랑", "옐로", "노랗", "황색"]),
        ("lime", ["lime", "chartreuse", "연두", "라임"]),
        ("green", ["green", "초록", "녹색", "그린", "푸른 잎"]),
        ("teal", ["teal", "틸"]),
        ("blue", ["blue", "파란", "파랑", "블루", "파랗", "푸른", "청색"]),
        ("purple", ["purple", "violet", "magenta", "lavender", "보라", "퍼플", "라벤더"]),
        ("pink", ["pink", "rose pink", "분홍", "핑크"]),
        ("white", ["white", "snow white", "하얀", "흰", "화이트", "하얗", "백색"]),
        ("black", ["black", "검은", "검정", "블랙", "까만", "흑색"]),
        ("silver", ["silver", "은색", "실버", "은빛"]),
        ("gray", ["gray", "grey", "회색", "그레이", "잿빛"]),
        ("gold", ["gold", "golden", "금색", "골드", "황금", "금빛"]),
        ("brown", ["brown", "chocolate", "tan", "갈색", "브라운", "밤색"]),
        ("beige", ["beige", "cream", "ivory", "베이지", "크림", "아이보리"]),
    ]

    static let materials: [(key: String, words: [String])] = [
        ("wood", ["wooden", "wood", "timber", "oak", "bamboo", "목재", "원목", "나무로 된", "나무"]),
        ("metal", ["metal", "metallic", "steel", "iron", "aluminium", "aluminum", "copper", "brass", "bronze", "금속", "강철", "철제", "스틸", "메탈", "쇠"]),
        ("chrome", ["chrome", "chromed", "polished", "mirror finish", "크롬", "광택"]),
        ("glass", ["glass", "transparent", "crystal", "see through", "유리", "투명", "크리스탈", "수정"]),
        ("stone", ["stone", "brick", "marble", "concrete", "granite", "돌", "벽돌", "대리석", "콘크리트", "석조"]),
        ("rubber", ["rubber", "고무"]),
        ("fabric", ["fabric", "leather", "velvet", "cloth", "wool", "가죽", "패브릭", "천", "벨벳"]),
        ("emissive", ["glowing", "glow", "neon", "luminous", "light up", "lit", "빛나는", "발광", "네온", "야광"]),
    ]

    static let styles: [(key: String, words: [String])] = [
        ("futuristic", ["futuristic", "sci fi", "scifi", "science fiction", "cyber", "cyberpunk", "high tech", "hi tech", "space age",
                        "미래", "미래형", "미래적", "sf", "사이버", "첨단", "하이테크"]),
        ("classic", ["classic", "vintage", "retro", "antique", "old fashioned", "클래식", "빈티지", "레트로", "고풍"]),
        ("cute", ["cute", "chibi", "adorable", "toy", "kawaii", "귀여운", "깜찍한", "아기자기"]),
        ("medieval", ["medieval", "gothic", "ancient", "중세", "고딕", "고대"]),
        ("modern", ["modern", "sleek", "minimal", "minimalist", "simple", "clean", "모던", "심플", "깔끔", "세련"]),
        ("luxury", ["luxury", "luxurious", "fancy", "royal", "elegant", "고급", "럭셔리", "화려한", "우아한"]),
        ("military", ["military", "army", "armored", "armoured", "tactical", "군용", "전투용", "장갑"]),
    ]

    /// Size words: multiplier.
    static let sizes: [(factor: Float, words: [String])] = [
        (2.2, ["giant", "gigantic", "huge", "enormous", "massive", "colossal", "거대한", "엄청 큰", "초대형"]),
        (1.5, ["big", "large", "tall", "long", "great", "커다란", "대형", "큰", "높은", "긴"]),
        (0.45, ["tiny", "miniature", "mini", "minuscule", "아주 작은", "초소형", "미니", "꼬마"]),
        (0.7, ["small", "little", "short", "compact", "작은", "조그만", "짧은", "소형"]),
    ]

    static let englishNumbers: [String: Int] = [
        "one": 1, "single": 1, "two": 2, "twin": 2, "pair": 2, "couple": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "dozen": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "eighteen": 18, "twenty": 20,
    ]

    /// Native Korean numbers (longest first so "열두" wins over "열").
    static let koreanNumbers: [(String, Int)] = [
        ("열두", 12), ("열한", 11), ("하나", 1), ("다섯", 5), ("여섯", 6), ("일곱", 7), ("여덟", 8), ("아홉", 9),
        ("둘", 2), ("셋", 3), ("넷", 4), ("한", 1), ("두", 2), ("세", 3), ("석", 3), ("네", 4), ("넉", 4), ("열", 10),
    ]

    static let koreanCounters = ["개", "층", "단", "쌍", "장", "대", "그루", "송이", "줄", "마리", "칸"]

    /// Korean particles and endings that may follow a short (one-syllable) noun.
    static let particles = ["", "을", "를", "이", "가", "은", "는", "의", "도", "로", "으로", "과", "와", "랑", "이랑", "에", "에는", "만", "들", "들이", "들을", "들은", "하나", "처럼"]

    // MARK: Matching

    /// Does a part called `partName` represent `component`? ("front_wheel" → wheel, "Windows" → window.)
    static func nameMatches(_ partName: String, component: String) -> Bool {
        let tokens = Set(nameTokens(partName))
        guard !tokens.isEmpty else { return false }
        let key = component.lowercased()
        if tokens.contains(singular(key)) { return true }
        guard let entry = components.first(where: { $0.key == key }) else { return false }
        for word in entry.words where !containsHangul(word) {
            let wordTokens = word.split(separator: " ").map { singular(String($0)) }
            if wordTokens.allSatisfy({ tokens.contains($0) }) { return true }
        }
        return false
    }

    /// Lowercased, singular word tokens of a part name ("frontWheelLeft" → ["front", "wheel", "left"]).
    static func nameTokens(_ name: String) -> [String] {
        var spaced = ""
        var previous: Character = " "
        for ch in name {
            if ch.isUppercase && previous.isLowercase { spaced.append(" ") }
            if ch.isNumber && previous.isLetter { spaced.append(" ") }
            spaced.append(ch)
            previous = ch
        }
        return spaced.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map { singular(String($0)) }
    }

    static func singular(_ word: String) -> String {
        let irregular = ["leaves": "leaves", "antennae": "antenna", "stories": "story", "storeys": "storey", "glasses": "glass", "boxes": "box"]
        if let s = irregular[word] { return s }
        if word.hasSuffix("ies") && word.count > 4 { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("ches") || word.hasSuffix("shes") || word.hasSuffix("sses") { return String(word.dropLast(2)) }
        if word.hasSuffix("s") && !word.hasSuffix("ss") && word.count > 3 { return String(word.dropLast()) }
        return word
    }

    static func containsHangul(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
    }

    /// Component key for a word as it appears in the text, if any.
    static func componentKey(forWord word: String) -> String? {
        components.first { $0.words.contains(word) }?.key
    }
}
