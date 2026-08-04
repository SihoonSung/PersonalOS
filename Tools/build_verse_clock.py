#!/usr/bin/env python3
"""
성경 구절 시계 데이터 생성기.

12시간제 시각 HH:MM 을 성경의 장:절 로 읽는다 — 07:21 이면 "마태복음 7:21".
720칸(1:00~12:59) 전부에 대응하는 구절을 고르고, 위젯이 읽을 JSON을 만든다.

사용법:
    # 공개도메인 영어(ASV)로 생성 — 기본
    python3 build_verse_clock.py --out ../PersonalOS/Resources/verse-clock.json

    # 한글 성경 파일을 넣어 생성
    python3 build_verse_clock.py --korean korean-bible.json --out ...

--korean 에 넣을 JSON 형식 (아래 셋 중 아무거나 됨):
    1) {"창세기": {"1": {"1": "태초에 하나님이..."}}}
    2) [{"book":"창세기","chapter":1,"verse":1,"text":"태초에..."}, ...]
    3) {"gen": {"1": {"1": "..."}}}   # 영문 약어 키도 허용

구절 선택 기준(점수가 낮을수록 우선):
    - 잘 알려진 책(시편·복음서·서신서)을 앞세운다
    - 위젯에 들어가야 하므로 짧은 구절을 선호한다
    - 족보·인구조사·제사 규정처럼 낭독해도 감흥 없는 장은 뒤로 민다
"""

import argparse
import json
import re
import sys
from pathlib import Path

try:
    import pythonbible as bible
except ImportError:
    sys.exit("pythonbible이 필요해요:  pip install pythonbible")

# ── 개신교 66권만 (외경 제외) ──────────────────────────────────────────
KOREAN_NAMES = {
    "GENESIS": "창세기", "EXODUS": "출애굽기", "LEVITICUS": "레위기",
    "NUMBERS": "민수기", "DEUTERONOMY": "신명기", "JOSHUA": "여호수아",
    "JUDGES": "사사기", "RUTH": "룻기", "SAMUEL_1": "사무엘상",
    "SAMUEL_2": "사무엘하", "KINGS_1": "열왕기상", "KINGS_2": "열왕기하",
    "CHRONICLES_1": "역대상", "CHRONICLES_2": "역대하", "EZRA": "에스라",
    "NEHEMIAH": "느헤미야", "ESTHER": "에스더", "JOB": "욥기",
    "PSALMS": "시편", "PROVERBS": "잠언", "ECCLESIASTES": "전도서",
    "SONG_OF_SONGS": "아가", "ISAIAH": "이사야", "JEREMIAH": "예레미야",
    "LAMENTATIONS": "예레미야애가", "EZEKIEL": "에스겔", "DANIEL": "다니엘",
    "HOSEA": "호세아", "JOEL": "요엘", "AMOS": "아모스", "OBADIAH": "오바댜",
    "JONAH": "요나", "MICAH": "미가", "NAHUM": "나훔", "HABAKKUK": "하박국",
    "ZEPHANIAH": "스바냐", "HAGGAI": "학개", "ZECHARIAH": "스가랴",
    "MALACHI": "말라기", "MATTHEW": "마태복음", "MARK": "마가복음",
    "LUKE": "누가복음", "JOHN": "요한복음", "ACTS": "사도행전",
    "ROMANS": "로마서", "CORINTHIANS_1": "고린도전서",
    "CORINTHIANS_2": "고린도후서", "GALATIANS": "갈라디아서",
    "EPHESIANS": "에베소서", "PHILIPPIANS": "빌립보서",
    "COLOSSIANS": "골로새서", "THESSALONIANS_1": "데살로니가전서",
    "THESSALONIANS_2": "데살로니가후서", "TIMOTHY_1": "디모데전서",
    "TIMOTHY_2": "디모데후서", "TITUS": "디도서", "PHILEMON": "빌레몬서",
    "HEBREWS": "히브리서", "JAMES": "야고보서", "PETER_1": "베드로전서",
    "PETER_2": "베드로후서", "JOHN_1": "요한일서", "JOHN_2": "요한이서",
    "JOHN_3": "요한삼서", "JUDE": "유다서", "REVELATION": "요한계시록",
}

# 낮을수록 먼저 뽑힌다.
BOOK_RANK = {
    "PSALMS": 0, "PROVERBS": 0, "JOHN": 0, "MATTHEW": 1, "LUKE": 1,
    "ROMANS": 1, "ISAIAH": 1, "PHILIPPIANS": 1, "JAMES": 1, "JOHN_1": 1,
    "MARK": 2, "ACTS": 2, "CORINTHIANS_1": 2, "CORINTHIANS_2": 2,
    "EPHESIANS": 2, "COLOSSIANS": 2, "HEBREWS": 2, "PETER_1": 2,
    "GALATIANS": 2, "ECCLESIASTES": 2, "GENESIS": 3, "EXODUS": 3,
    "DEUTERONOMY": 3, "JOSHUA": 3, "DANIEL": 3, "JEREMIAH": 3,
    "REVELATION": 3, "TIMOTHY_1": 3, "TIMOTHY_2": 3,
}
DEFAULT_RANK = 5

# 족보·인구조사·제사 규정 — 시계에 띄워봐야 감흥이 없다.
DULL_BOOKS = {"CHRONICLES_1", "CHRONICLES_2", "NUMBERS", "LEVITICUS", "EZRA", "NEHEMIAH"}
DULL_PATTERNS = re.compile(
    r"(begat|the son of|by their generations|were numbered|shekels of|"
    r"cubits|and his sons|according to their families)",
    re.IGNORECASE,
)

PROTESTANT = [b for b in bible.Book if b.name in KOREAN_NAMES]

IDEAL_LENGTH = 85  # 위젯 한 화면에 편하게 들어가는 길이

# 앞뒤 문맥이 있어야 말이 되는 구절은 시계에 띄우기 나쁘다.
DANGLING_START = re.compile(r"^(And|But|For|Then|Therefore|So|Now|Yet|Also|Thus)\b", re.IGNORECASE)

# 머리맡에 띄워둘 시계다. 전쟁·심판·저주 구절은 세게 밀어낸다.
HARSH = re.compile(
    r"\b(slew|slay|slain|smote|smite|kill|killed|sword|blood|bloodshed|destroy|"
    r"destroyed|destruction|curse|cursed|wrath|vengeance|avenge|perish|plague|"
    r"pestilence|famine|leprosy|harlot|whoredom|adulter|fornicat|dung|carcase|"
    r"burnt|consume[ds]?|utterly|smitten|captivity|desolate|desolation|"
    r"abomination|torment|hell|devour)\b",
    re.IGNORECASE,
)

# 반대로 시계에 띄우면 좋은 말들.
GENTLE = re.compile(
    r"\b(love|loved|peace|hope|faith|light|grace|rest|joy|joyful|comfort|mercy|"
    r"merciful|trust|bless|blessed|shepherd|refuge|strength|still|quiet|glad|"
    r"gracious|kindness|patient|gentle|good|goodness|forgive|heal|healed|"
    r"everlasting|morning|remember|abide|dwell|glory|thanks|praise)\b",
    re.IGNORECASE,
)


def asv_text(book, chapter, verse):
    """pythonbible에 들어있는 공개도메인 ASV 본문."""
    try:
        verse_id = bible.get_verse_id(book, chapter, verse)
    except Exception:
        return None
    try:
        raw = bible.get_verse_text(verse_id)
    except Exception:
        return None
    if not raw:
        return None
    return re.sub(r"\s+", " ", raw).strip()


def text_quality(book, text):
    """본문 자체의 점수. 낮을수록 좋다."""
    if not text:
        return 60
    value = abs(len(text) - IDEAL_LENGTH) / 10
    if len(text) < 30:
        value += 12
    if len(text) > 170:
        value += 14
    if DULL_PATTERNS.search(text):
        value += 45
    if HARSH.search(text):
        value += 38
    if DANGLING_START.match(text):
        value += 7
    # 소문자로 시작하면 앞 절에서 이어지는 문장 조각이다
    # ("that I may make it manifest, as I ought to speak" 같은 것).
    if text[:1].islower():
        value += 22
    # 마침표로 안 끝나면 말이 잘린 느낌이 든다.
    if not text.rstrip().endswith((".", "!", "?", '"', "'")):
        value += 8
    if book.name in DULL_BOOKS:
        value += 18
    # 위로가 되는 단어가 있으면 끌어올린다 (최대 3개까지만 인정).
    value -= min(len(GENTLE.findall(text)), 3) * 7
    return value


def build_slots():
    """720칸 각각에 대해 (book, chapter, verse, asv) 를 고른다.

    한 책이 화면을 독차지하지 않도록, 이미 뽑힌 횟수만큼 벌점을 준다.
    벌점이 없으면 점수 1위 책(요한복음·잠언)이 300칸씩 가져가 버린다.
    """
    used = {}
    slots = {}
    misses = []

    # 후보가 적은 칸부터 배정해야 희귀한 칸이 좋은 구절을 먼저 고른다.
    plan = []
    for hour in range(1, 13):
        for minute in range(0, 60):
            verse = minute if minute > 0 else 1
            candidates = []
            for book in PROTESTANT:
                try:
                    if hour > bible.get_number_of_chapters(book):
                        continue
                    if verse > bible.get_number_of_verses(book, hour):
                        continue
                except Exception:
                    continue
                candidates.append(book)
            plan.append((len(candidates), hour, minute, verse, candidates))
    plan.sort(key=lambda row: row[0])

    for _, hour, minute, verse, candidates in plan:
        key = f"{hour:02d}:{minute:02d}"
        if not candidates:
            misses.append(key)
            continue

        best = None
        for book in candidates:
            text = asv_text(book, hour, verse)
            if not text:
                continue
            value = (
                text_quality(book, text)
                + BOOK_RANK.get(book.name, DEFAULT_RANK) * 5
                + used.get(book.name, 0) * 0.9
            )
            if best is None or value < best[0]:
                best = (value, book, text)

        if best is None:
            misses.append(key)
            continue

        _, book, text = best
        used[book.name] = used.get(book.name, 0) + 1
        slots[key] = {
            "book": book.name,
            "bookKo": KOREAN_NAMES[book.name],
            "chapter": hour,
            "verse": verse,
            "text": text,
            "exact": True,
        }

    # 장:절이 시:분과 맞는 구절이 아예 없는 칸(4:55~4:59 등 25칸).
    # 어느 책에도 4장 55절이 없으니 만들어낼 수가 없다 — 대신 짧고 좋은
    # 구절을 돌려 쓰고, exact=false 로 표시해 화면에서 구분할 수 있게 한다.
    for key in misses:
        pick = FALLBACK[len(slots) % len(FALLBACK)]
        book = getattr(bible.Book, pick[0])
        slots[key] = {
            "book": pick[0],
            "bookKo": KOREAN_NAMES[pick[0]],
            "chapter": pick[1],
            "verse": pick[2],
            "text": asv_text(book, pick[1], pick[2]) or "",
            "exact": False,
        }

    return slots, misses


# 시:분과 맞아떨어지는 구절이 없는 칸에 쓸 예비 구절.
FALLBACK = [
    ("PSALMS", 23, 1), ("PSALMS", 46, 10), ("PSALMS", 121, 1),
    ("ISAIAH", 40, 31), ("ISAIAH", 41, 10), ("JEREMIAH", 29, 11),
    ("MATTHEW", 6, 34), ("MATTHEW", 11, 28), ("JOHN", 14, 27),
    ("ROMANS", 8, 28), ("PHILIPPIANS", 4, 13), ("PROVERBS", 16, 9),
]


# ── 한글 본문 주입 ────────────────────────────────────────────────────

def normalize_korean(raw):
    """세 가지 입력 형태를 {(책이름, 장, 절): 본문} 하나로 편다."""
    table = {}

    def put(book, chapter, verse, text):
        if not text:
            return
        table[(str(book).strip(), int(chapter), int(verse))] = re.sub(r"\s+", " ", str(text)).strip()

    if isinstance(raw, list):
        for row in raw:
            if not isinstance(row, dict):
                continue
            book = row.get("book") or row.get("book_name") or row.get("bookName")
            chapter = row.get("chapter") or row.get("chapter_number")
            verse = row.get("verse") or row.get("verse_number")
            text = row.get("text") or row.get("content") or row.get("verse_text")
            if book and chapter and verse:
                put(book, chapter, verse, text)
    elif isinstance(raw, dict):
        for book, chapters in raw.items():
            if not isinstance(chapters, dict):
                continue
            for chapter, verses in chapters.items():
                if isinstance(verses, dict):
                    for verse, text in verses.items():
                        put(book, chapter, verse, text)
                elif isinstance(verses, list):
                    for index, text in enumerate(verses, start=1):
                        put(book, chapter, index, text)
    return table


# 흔히 쓰이는 영문 약어 → 우리 enum 이름
ABBREV = {
    "gen": "GENESIS", "exo": "EXODUS", "lev": "LEVITICUS", "num": "NUMBERS",
    "deu": "DEUTERONOMY", "jos": "JOSHUA", "jdg": "JUDGES", "rut": "RUTH",
    "1sa": "SAMUEL_1", "2sa": "SAMUEL_2", "1ki": "KINGS_1", "2ki": "KINGS_2",
    "1ch": "CHRONICLES_1", "2ch": "CHRONICLES_2", "ezr": "EZRA", "neh": "NEHEMIAH",
    "est": "ESTHER", "job": "JOB", "psa": "PSALMS", "pro": "PROVERBS",
    "ecc": "ECCLESIASTES", "sng": "SONG_OF_SONGS", "sos": "SONG_OF_SONGS",
    "isa": "ISAIAH", "jer": "JEREMIAH", "lam": "LAMENTATIONS", "ezk": "EZEKIEL",
    "eze": "EZEKIEL", "dan": "DANIEL", "hos": "HOSEA", "jol": "JOEL",
    "joe": "JOEL", "amo": "AMOS", "oba": "OBADIAH", "jon": "JONAH",
    "mic": "MICAH", "nam": "NAHUM", "nah": "NAHUM", "hab": "HABAKKUK",
    "zep": "ZEPHANIAH", "hag": "HAGGAI", "zec": "ZECHARIAH", "mal": "MALACHI",
    "mat": "MATTHEW", "mrk": "MARK", "mar": "MARK", "luk": "LUKE",
    "jhn": "JOHN", "joh": "JOHN", "act": "ACTS", "rom": "ROMANS",
    "1co": "CORINTHIANS_1", "2co": "CORINTHIANS_2", "gal": "GALATIANS",
    "eph": "EPHESIANS", "php": "PHILIPPIANS", "phi": "PHILIPPIANS",
    "col": "COLOSSIANS", "1th": "THESSALONIANS_1", "2th": "THESSALONIANS_2",
    "1ti": "TIMOTHY_1", "2ti": "TIMOTHY_2", "tit": "TITUS", "phm": "PHILEMON",
    "heb": "HEBREWS", "jas": "JAMES", "jam": "JAMES", "1pe": "PETER_1",
    "2pe": "PETER_2", "1jn": "JOHN_1", "1jo": "JOHN_1", "2jn": "JOHN_2",
    "2jo": "JOHN_2", "3jn": "JOHN_3", "3jo": "JOHN_3", "jud": "JUDE",
    "rev": "REVELATION",
}


def lookup_korean(table, slot):
    """한글 책이름 → 영문 enum → 약어 순으로 찾아본다."""
    for key in (slot["bookKo"], slot["book"], slot["book"].lower()):
        hit = table.get((key, slot["chapter"], slot["verse"]))
        if hit:
            return hit
    for abbrev, enum_name in ABBREV.items():
        if enum_name != slot["book"]:
            continue
        for variant in (abbrev, abbrev.upper(), abbrev.capitalize()):
            hit = table.get((variant, slot["chapter"], slot["verse"]))
            if hit:
                return hit
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--korean", help="한글 성경 JSON 경로 (없으면 ASV 영어로만 생성)")
    parser.add_argument("--out", required=True, help="출력 JSON 경로")
    args = parser.parse_args()

    slots, misses = build_slots()
    print(f"슬롯 {len(slots)}/720 생성" + (f", 누락 {misses}" if misses else ", 누락 없음"))

    filled = 0
    if args.korean:
        raw = json.loads(Path(args.korean).read_text(encoding="utf-8"))
        table = normalize_korean(raw)
        print(f"한글 본문 {len(table)}절 읽음")
        for slot in slots.values():
            text = lookup_korean(table, slot)
            if text:
                slot["textKo"] = text
                filled += 1
        print(f"한글 채움 {filled}/{len(slots)}")
        if filled < len(slots):
            missing = [k for k, v in slots.items() if not v.get("textKo")][:10]
            print(f"  못 채운 예: {missing}")

    payload = {
        "format": "verse-clock/1",
        "hourCycle": 12,
        "language": "ko" if filled else "en",
        "source": "ASV (public domain)" if not filled else "user-supplied",
        "slots": slots,
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"→ {out}  ({out.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
