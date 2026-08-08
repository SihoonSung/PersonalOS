#!/usr/bin/env python3
"""스크린샷 OCR 파서 회귀 검증 — PersonalOS/Capture/ReceiptScan.swift 와 같은 로직.

Swift 를 이 환경에서 컴파일할 수 없어서 파서 규칙만 파이썬으로 옮겨 돌린다.
ReceiptTextParser 를 고치면 여기도 같이 고칠 것.
"""

import re
from datetime import datetime, timedelta

EXPENSE, INCOME, SETTLE_IN, SETTLE_OUT = "지출", "수입", "받은 정산", "보낸 정산"

AMOUNT_RE = re.compile(r"\$?\s?([0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)\.([0-9]{2})(?![0-9])")
AMOUNT_LABELS = ["AMOUNT", "TOTAL", "YOU SENT", "YOU PAID", "SENT", "금액", "합계", "송금액", "보낸 금액"]
BALANCE_TOKENS = ["BALANCE", "AVAILABLE", "LIMIT", "REMAINING", "잔액", "잔고", "한도"]
PARTY_LABELS = ["TO", "RECIPIENT", "SENT TO", "PAID TO", "PAY TO", "받는 사람", "받는사람", "수취인", "받는분"]
MEMO_LABELS = ["MEMO", "NOTE", "FOR", "WHAT'S IT FOR", "메모", "내용", "적요"]
CHROME_EXACT = {
    "DONE", "OK", "CLOSE", "BACK", "CANCEL", "SHARE", "VIEW", "SEND", "SEND AGAIN",
    "CONTINUE", "NEXT", "HOME", "ACCOUNTS", "ZELLE", "VENMO", "PAY", "REQUEST",
    "CONFIRMATION", "ADD TO SIRI", "SEE DETAILS", "MEMO", "AMOUNT", "RECIPIENT",
    "확인", "닫기", "완료", "취소", "공유", "홈", "송금", "요청",
}
CHROME_TOKENS = ["ACCOUNT ENDING", "AVAILABLE BALANCE", "TAP ", "SWIPE ", "WILL BE",
                 "USUALLY", "SIRI SHORTCUT", "SAVE TIME", "A FEW MINUTES", "SENDING MONEY"]
MONTHS = {m: i + 1 for i, m in enumerate(
    ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"])}


def amounts(line):
    out = []
    for whole, frac in AMOUNT_RE.findall(line):
        out.append(float(whole.replace(",", "") + "." + frac))
    return out


def has(line, tokens):
    upper = line.upper()
    return any(t in upper for t in tokens)


def amount(lines):
    labelled, others = [], []
    for i, line in enumerate(lines):
        values = amounts(line)
        if not values or has(line, BALANCE_TOKENS):
            continue
        previous = lines[i - 1] if i > 0 else ""
        if has(line, AMOUNT_LABELS) or has(previous, AMOUNT_LABELS):
            labelled += values
        else:
            others += values
    if labelled:
        return max(labelled)
    return max(others) if others else None


def after_label(line, labels):
    upper = line.upper()
    for label in labels:
        if not upper.startswith(label):
            continue
        rest = line[len(label):]
        if rest and (rest[0].isalpha() or rest[0].isdigit()):
            continue  # "TODAY" 가 "TO" 로 잡히는 것 방지
        return rest.strip(" \t:：-–—")
    return None


def clean(raw):
    text = raw.strip()
    text = re.sub(r"\(\.*\.\.\.[0-9]+\)", "", text)
    text = re.sub(r"[•*]{2,}[0-9]*", "", text)
    text = re.sub(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+", "", text)
    text = re.sub(r"\+?[0-9]{3}[-. ][0-9]{3}[-. ][0-9]{4}", "", text)
    text = text.strip(" \t:-–—,·")
    if not (2 <= len(text) <= 60):
        return None
    upper = text.upper()
    if upper in CHROME_EXACT or any(t in upper for t in CHROME_TOKENS):
        return None
    if not re.search(r"[A-Za-z가-힣]", text):
        return None
    return text


INLINE_TO = re.compile(r"\bto\s+([^\n]+?)(?:\s+Account ending|\s+on\s|\s+with Zelle|$)", re.I)
SENTENCE_MARKERS = [" will get it", " will receive it", " 님이 받", "에게 보내"]


def registered_name(lines):
    for i, line in enumerate(lines):
        if not line.upper().startswith("REGISTERED AS"):
            continue
        if i > 0:
            c = clean(lines[i - 1])
            if c:
                return c
        c = clean(line[len("Registered as"):])
        if c:
            return c
    return None


def recipient_from_sentence(lines):
    for line in lines:
        low = line.lower()
        for marker in SENTENCE_MARKERS:
            idx = low.find(marker.lower())
            if idx < 0:
                continue
            head = line[:idx]
            tail = head.split(". ")[-1]
            c = clean(tail)
            if c:
                return c
    return None


def labelled_name(lines):
    for i, line in enumerate(lines):
        rest = after_label(line, PARTY_LABELS)
        if rest is None:
            continue
        c = clean(rest)
        if c:
            return c
        for j in range(i + 1, min(i + 4, len(lines))):
            c = clean(lines[j])
            if c:
                return c
    return None


def inline_to_name(lines):
    for line in lines:
        upper = line.upper()
        looks = bool(amounts(line)) or upper.startswith(("YOU SENT", "YOU PAID", "SENT TO", "PAID TO"))
        if not looks:
            continue
        m = INLINE_TO.search(line)
        if not m:
            continue
        c = clean(m.group(1))
        if c:
            return c
    return None


def counterparty(lines):
    return (registered_name(lines) or recipient_from_sentence(lines)
            or labelled_name(lines) or inline_to_name(lines))


def memo(lines):
    for i, line in enumerate(lines):
        rest = after_label(line, MEMO_LABELS)
        if rest is None:
            continue
        if len(rest.strip()) >= 2:
            return rest.strip()
        if i + 1 < len(lines):
            nxt = lines[i + 1].strip()
            if len(nxt) >= 2 and not has(nxt, AMOUNT_LABELS):
                return nxt
    return None


def make(year, month, day, now):
    if month is None or day is None or not (1 <= month <= 12) or not (1 <= day <= 31):
        return None
    y = year if year is not None else now.year
    try:
        date = datetime(y, month, day, 12, 0)
    except ValueError:
        return None
    if year is None and date > now + timedelta(days=1):
        try:
            date = datetime(y - 1, month, day, 12, 0)
        except ValueError:
            return date
    if date.date() == now.date():
        return now
    return date


def parse_date(lines, now):
    for line in lines:
        upper = line.upper()
        if "TODAY" in upper or "오늘" in upper:
            return now
        if "YESTERDAY" in upper or "어제" in upper:
            return now - timedelta(days=1)
        m = re.search(r"([0-9]{4})-([0-9]{2})-([0-9]{2})", line)
        if m:
            d = make(int(m.group(1)), int(m.group(2)), int(m.group(3)), now)
            if d:
                return d
        m = re.search(r"([0-9]{4})년\s*([0-9]{1,2})월\s*([0-9]{1,2})일", line)
        if m:
            d = make(int(m.group(1)), int(m.group(2)), int(m.group(3)), now)
            if d:
                return d
        m = re.search(r"([A-Za-z]{3,9})\s+([0-9]{1,2})(?:,\s*([0-9]{4}))?", line)
        if m:
            month = MONTHS.get(m.group(1)[:3].upper())
            if month:
                year = int(m.group(3)) if m.group(3) else None
                d = make(year, month, int(m.group(2)), now)
                if d:
                    return d
        m = re.search(r"([0-9]{1,2})/([0-9]{1,2})(?:/([0-9]{2,4}))?", line)
        if m:
            year = int(m.group(3)) if m.group(3) else None
            if year is not None and year < 100:
                year += 2000
            d = make(year, int(m.group(1)), int(m.group(2)), now)
            if d:
                return d
    return None


def source(text):
    upper = text.upper()
    for token, name in [("ZELLE", "Zelle"), ("VENMO", "Venmo"), ("CASH APP", "Cash App"),
                        ("PAYPAL", "PayPal"), ("APPLE CASH", "Apple Cash"),
                        ("TOSS", "토스"), ("토스", "토스")]:
        if token in upper:
            return name
    if "REGISTERED AS" in upper and "WILL GET IT" in upper:
        return "Zelle"
    return ""


def kind(text, src):
    upper = text.upper()
    for token in ["YOU RECEIVED", "RECEIVED MONEY", "받았습니다", "입금"]:
        if token in upper:
            return INCOME if not src else SETTLE_IN
    return EXPENSE


def parse(raw_lines, now):
    lines = [l.strip() for l in raw_lines if l.strip()]
    joined = "\n".join(lines)
    src = source(joined)
    return {
        "amount": amount(lines),
        "counterparty": counterparty(lines),
        "date": parse_date(lines, now),
        "memo": memo(lines),
        "source": src,
        "kind": kind(joined, src),
    }


# --------------------------------------------------------------------------
NOW = datetime(2026, 8, 6, 10, 30)

CASES = [
    ("Chase Zelle 송금 완료", [
        "Zelle®",
        "You sent $876.55",
        "To",
        "Uzma Abbas",
        "From",
        "TOTAL CHECKING (...9601)",
        "Memo",
        "1394 Final utility payment",
        "Sent on Aug 3, 2026",
        "Done",
    ], {"amount": 876.55, "counterparty": "Uzma Abbas", "memo": "1394 Final utility payment",
        "source": "Zelle", "kind": EXPENSE, "date": datetime(2026, 8, 3, 12, 0)}),

    ("Chase 이체 알림 형식 (한 줄 안에 상대)", [
        "Transfer alert",
        "You sent $23.00 to BILT PAYMENT",
        "Account ending in (...9601)",
        "Sent on Aug 3, 2026 at 1:48 AM ET",
        "Recipient BILT PAYMENT",
        "Amount",
        "$23.00",
    ], {"amount": 23.00, "counterparty": "BILT PAYMENT", "source": "",
        "kind": EXPENSE, "date": datetime(2026, 8, 3, 12, 0)}),

    ("잔액이 송금액보다 클 때 잔액을 집지 않는다", [
        "Zelle®",
        "Amount",
        "$45.00",
        "Recipient: Jane Doe",
        "Available balance $3,241.19",
        "Today",
    ], {"amount": 45.00, "counterparty": "Jane Doe", "source": "Zelle", "date": NOW}),

    ("라벨 없이 금액만 — 가장 큰 값", [
        "Payment complete",
        "$12.50",
        "Fee $0.00",
        "To Marco Silva",
    ], {"amount": 12.50, "counterparty": "Marco Silva"}),

    ("Venmo 스타일", [
        "Venmo",
        "You paid Chris Park",
        "$8.75",
        "Note",
        "dinner split",
        "Yesterday",
    ], {"amount": 8.75, "memo": "dinner split", "source": "Venmo",
        "date": NOW - timedelta(days=1)}),

    ("입금 화면은 받은 정산", [
        "Zelle®",
        "You received money",
        "Amount $50.00",
        "From Daniel Kim",
    ], {"amount": 50.00, "source": "Zelle", "kind": SETTLE_IN}),

    ("천 단위 쉼표", [
        "You sent $2,465.51 to TESLA MOTORS",
        "Aug 3, 2026",
    ], {"amount": 2465.51, "counterparty": "TESLA MOTORS"}),

    ("연도 없는 날짜는 올해, 미래면 작년", [
        "Amount $10.00",
        "Dec 20",
        "To Sam Lee",
    ], {"amount": 10.00, "date": datetime(2025, 12, 20, 12, 0)}),

    ("슬래시 날짜", [
        "Amount $31.20",
        "8/3/2026",
        "To Corner Market",
    ], {"amount": 31.20, "date": datetime(2026, 8, 3, 12, 0)}),

    ("한국어 화면", [
        "송금 완료",
        "금액",
        "35000.00",
        "받는 사람",
        "김철수",
        "메모",
        "회비",
        "2026년 8월 3일",
    ], {"amount": 35000.00, "counterparty": "김철수", "memo": "회비",
        "date": datetime(2026, 8, 3, 12, 0)}),

    ("메모 숫자를 금액으로 오인하지 않는다", [
        "Memo",
        "1394 utility",
        "Amount",
        "$88.00",
        "To Uzma Abbas",
    ], {"amount": 88.00, "memo": "1394 utility", "counterparty": "Uzma Abbas"}),

    ("'Today'가 'To' 라벨로 오인되지 않는다", [
        "Amount $9.99",
        "Today",
        "Recipient Anna Ruiz",
    ], {"amount": 9.99, "counterparty": "Anna Ruiz", "date": NOW}),

    ("버튼 글자를 이름으로 삼지 않는다", [
        "$15.00",
        "To",
        "Done",
        "Nina Patel",
    ], {"amount": 15.00, "counterparty": "Nina Patel"}),

    # 실물 — Chase Zelle 송금 확인 화면 (IMG_0751, 2026-08-06 08:50).
    # 라벨이 하나도 없고, 맨 아래 안내 문장에 "to save time..." 이 있다.
    ("실물 Chase Zelle 확인 화면", [
        "08:50",
        "90",
        "Confirmation",
        "We're sending your money now. Uzma Abbas will get it",
        "in a few minutes.",
        "$876.55",
        "U",
        "Uzma Abbas",
        "Registered as UZMA ABBAS",
        "(631) 922-2291",
        "Add a Siri shortcut, such as \u201cPay Uzma,\u201d to save time when",
        "sending money.",
        "Add to Siri",
        "Done",
    ], {"amount": 876.55, "counterparty": "Uzma Abbas", "memo": None,
        "date": None, "source": "Zelle", "kind": EXPENSE}),

    # 같은 화면에서 아바타 이니셜 줄이 없을 때도 같아야 한다.
    ("실물 화면 — Registered as 줄이 없을 때", [
        "Confirmation",
        "We're sending your money now. Uzma Abbas will get it",
        "in a few minutes.",
        "$876.55",
        "Add a Siri shortcut, such as \u201cPay Uzma,\u201d to save time when",
        "sending money.",
        "Done",
    ], {"amount": 876.55, "counterparty": "Uzma Abbas"}),

    ("아무것도 못 읽어도 죽지 않는다", [
        "Loading...",
    ], {"amount": None, "counterparty": None, "date": None, "memo": None}),
]


def main():
    failures = 0
    checks = 0
    for name, lines, expected in CASES:
        got = parse(lines, NOW)
        for key, want in expected.items():
            checks += 1
            have = got[key]
            if isinstance(want, float) and isinstance(have, float):
                ok = abs(want - have) < 0.005
            else:
                ok = want == have
            if not ok:
                failures += 1
                print(f"FAIL  {name}\n      {key}: 기대 {want!r} / 실제 {have!r}")
    print(f"\n{checks - failures}/{checks} 통과")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
