#!/usr/bin/env python3
"""성경 구절 파서 회귀 검증 — PersonalOS/Core/BibleReference.swift 와 같은 로직."""

RAW = [("창세기","창"),("출애굽기","출"),("레위기","레"),("민수기","민"),("신명기","신"),
("여호수아","수"),("사사기","삿"),("룻기","룻"),("사무엘상","삼상"),("사무엘하","삼하"),
("열왕기상","왕상"),("열왕기하","왕하"),("역대상","대상"),("역대하","대하"),
("에스라","스"),("느헤미야","느"),("에스더","에"),("욥기","욥"),("시편","시"),
("잠언","잠"),("전도서","전"),("아가","아"),("이사야","사"),("예레미야","렘"),
("예레미야애가","애"),("에스겔","겔"),("다니엘","단"),("호세아","호"),("요엘","욜"),
("아모스","암"),("오바댜","옵"),("요나","욘"),("미가","미"),("나훔","나"),
("하박국","합"),("스바냐","습"),("학개","학"),("스가랴","슥"),("말라기","말"),
("마태복음","마"),("마가복음","막"),("누가복음","눅"),("요한복음","요"),
("사도행전","행"),("로마서","롬"),("고린도전서","고전"),("고린도후서","고후"),
("갈라디아서","갈"),("에베소서","엡"),("빌립보서","빌"),("골로새서","골"),
("데살로니가전서","살전"),("데살로니가후서","살후"),("디모데전서","딤전"),
("디모데후서","딤후"),("디도서","딛"),("빌레몬서","몬"),("히브리서","히"),
("야고보서","약"),("베드로전서","벧전"),("베드로후서","벧후"),("요한1서","요일"),
("요한2서","요이"),("요한3서","요삼"),("유다서","유"),("요한계시록","계")]

BOOKS = [{"order": i+1, "name": n, "abbr": a} for i, (n, a) in enumerate(RAW)]
INDEX = {}
for b in BOOKS:
    INDEX[b["name"]] = b
    INDEX[b["abbr"]] = b
ALIASES = {"시":"시편","시편서":"시편","아가서":"아가","애가":"예레미야애가",
           "계시록":"요한계시록","요한계시":"요한계시록","요1서":"요한1서",
           "요2서":"요한2서","요3서":"요한3서","고린도전":"고린도전서","고린도후":"고린도후서"}
for alias, target in ALIASES.items():
    INDEX[alias] = next(b for b in BOOKS if b["name"] == target)

def parse(raw):
    text = raw.strip()
    if not text: return None
    compact = text.replace(" ", "")
    book = None; remainder = ""
    for length in range(min(len(compact), 8), 0, -1):
        cand = compact[:length]
        if cand in INDEX:
            book = INDEX[cand]; remainder = compact[length:]; break
    if not book: return None
    numbers, cur = [], ""
    for ch in remainder:
        if ch.isdigit(): cur += ch
        elif cur: numbers.append(int(cur)); cur = ""
    if cur: numbers.append(int(cur))
    if not numbers or numbers[0] <= 0: return None
    return {"book": book, "chapter": numbers[0],
            "start": numbers[1] if len(numbers) > 1 else None,
            "end": numbers[2] if len(numbers) > 2 else None}

def display(r):
    if r is None: return None
    t = f"{r['book']['name']} {r['chapter']}"
    if r["start"]:
        t += f":{r['start']}"
        if r["end"] and r["end"] != r["start"]: t += f"-{r['end']}"
    return t

fails = []
def check(inp, want):
    got = display(parse(inp))
    ok = got == want
    print(f"{'PASS' if ok else 'FAIL'}  {inp:24} → {got!r:28} want {want!r}")
    if not ok: fails.append(inp)

print("── 66권 정경 ──")
print(f"{'PASS' if len(BOOKS)==66 else 'FAIL'}  권 수 = {len(BOOKS)}")
if len(BOOKS)!=66: fails.append("book count")
dups = {b['abbr'] for b in BOOKS if sum(1 for x in BOOKS if x['abbr']==b['abbr'])>1}
print(f"{'PASS' if not dups else 'FAIL'}  약어 중복 없음 {dups or ''}")
if dups: fails.append("abbr dup")

print("\n── 기본 형식 ──")
check("요한복음 3:16", "요한복음 3:16")
check("요 3:16", "요한복음 3:16")
check("롬 8:28-30", "로마서 8:28-30")
check("시편 23", "시편 23")
check("시 23:1", "시편 23:1")

print("\n── 한글 장/절 표기 ──")
check("요한복음 3장 16절", "요한복음 3:16")
check("창세기1장1절", "창세기 1:1")
check("고린도전서 13장 4절-7절", "고린도전서 13:4-7")

print("\n── 긴 이름이 짧은 약어보다 우선 ──")
check("요한계시록 21:4", "요한계시록 21:4")
check("요한1서 4:8", "요한1서 4:8")
check("계 21:4", "요한계시록 21:4")
check("요일 4:8", "요한1서 4:8")

print("\n── 별칭 ──")
check("계시록 22:20", "요한계시록 22:20")
check("애가 3:23", "예레미야애가 3:23")

print("\n── 같은 절 반복은 범위로 안 씀 ──")
check("빌 4:13-13", "빌립보서 4:13")

print("\n── 해석 불가 → None (자유 텍스트로 남긴다) ──")
check("오늘의 말씀", None)
check("John 3:16", None)
check("", None)

print("\n── 정렬 키 ──")
a, b = parse("창세기 1:1"), parse("요한계시록 22:21")
ka = a["book"]["order"]*1000000 + a["chapter"]*1000 + (a["start"] or 0)
kb = b["book"]["order"]*1000000 + b["chapter"]*1000 + (b["start"] or 0)
ok = ka < kb
print(f"{'PASS' if ok else 'FAIL'}  창세기 < 요한계시록 ({ka} < {kb})")
if not ok: fails.append("sort")

print()
if fails:
    print(f"FAILED {len(fails)}: {fails}"); raise SystemExit(1)
print("ALL BIBLE REFERENCE CASES PASS")
