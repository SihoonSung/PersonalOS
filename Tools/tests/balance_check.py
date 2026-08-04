# Port of EntryKind.sign + BalanceService.snapshot, checked against a
# hand-computed scenario built from Sihoon's real Chase alerts.
from datetime import datetime, timedelta

EXPENSE, INCOME, SETTLE_IN, SETTLE_OUT = "지출", "수입", "받은 정산", "보낸 정산"

def sign(kind):
    return 1 if kind in (INCOME, SETTLE_IN) else -1

def snapshot(anchor_amount, anchor_at, entries):
    total, count, spent, received = anchor_amount, 0, 0.0, 0.0
    for date, amount, kind in entries:
        if not (date > anchor_at):          # strictly after, as in Swift
            continue
        delta = sign(kind) * abs(amount)
        if delta == 0:
            continue
        total += delta
        count += 1
        if delta < 0: spent += -delta
        else: received += delta
    return dict(current=round(total, 2), applied=count,
                spent=round(spent, 2), received=round(received, 2))

D = lambda s: datetime.fromisoformat(s)
anchor_at = D("2026-08-02T00:00:00")

# Real transactions from his mailbox, Aug 2–4
entries = [
    (D("2026-08-02T08:00:00"), 134.17, SETTLE_IN),   # JIHEE LEE utility fee
    (D("2026-08-02T08:00:00"), 140.69, SETTLE_IN),   # JUNWOO LEE rent util
    (D("2026-08-02T08:02:00"), 117.00, SETTLE_IN),   # JUNHEE KIM utility fee
    (D("2026-08-02T08:09:00"), 182.94, SETTLE_IN),   # DAYUN LEE utilities
    (D("2026-08-02T08:33:00"), 150.07, SETTLE_IN),   # HANNAH KIM
    (D("2026-08-02T23:49:00"), 25.25,  SETTLE_IN),   # INN KYUNG SEO
    (D("2026-08-03T01:48:00"), 23.00,  EXPENSE),     # BILT PAYMENT (송금)
    (D("2026-08-03T09:01:00"), 4.50,   SETTLE_IN),   # HYEWON LEE youtube
    (D("2026-08-04T05:35:00"), 29.35,  SETTLE_IN),   # YONG SEOK YOO
    (D("2026-08-01T12:00:00"), 999.99, EXPENSE),     # BEFORE anchor — must be ignored
]

got = snapshot(1000.00, anchor_at, entries)
expected_received = 134.17+140.69+117.00+182.94+150.07+25.25+4.50+29.35
expected = dict(current=round(1000.00 + expected_received - 23.00, 2),
                applied=9, spent=23.00, received=round(expected_received, 2))

print("anchor        : $1000.00 @ 2026-08-02 00:00")
print("got           :", got)
print("expected      :", expected)
assert got == expected, "balance mismatch"

# 정산금이 수입 통계에 안 잡히는지
month_income = sum(a for _, a, k in entries if k == INCOME)
month_spend  = sum(a for d, a, k in entries if k == EXPENSE and d > anchor_at)
print(f"월 수입 통계   : ${month_income:.2f}  (정산금 제외 — 의도대로)")
print(f"월 지출 통계   : ${month_spend:.2f}")
assert month_income == 0

# 급여 입금이 들어오면 수입에도, 잔액에도 반영
entries.append((D("2026-08-04T09:00:00"), 2100.00, INCOME))
got2 = snapshot(1000.00, anchor_at, entries)
print("\n급여 $2100 추가 후:", got2)
assert round(got2["current"] - got["current"], 2) == 2100.00
assert got2["received"] == round(got["received"] + 2100.00, 2)

# 새 기준점을 찍으면 이전 거래가 두 번 반영되지 않는지
got3 = snapshot(3500.00, D("2026-08-04T23:59:00"), entries)
print("새 기준점 $3500 @ 8/4 23:59 →", got3)
assert got3 == dict(current=3500.00, applied=0, spent=0.0, received=0.0)

print("\nALL BALANCE CASES PASS")
