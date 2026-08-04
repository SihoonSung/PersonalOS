# Port of MailSyncService.isEcho, exercised on real scenarios from Sihoon's mailbox.
from datetime import datetime, timedelta

def sign(kind): return 1 if kind in ("수입", "받은 정산") else -1
WINDOW = timedelta(hours=36)

def is_echo(tx, existing):
    """tx / existing rows: dict(amount, date, kind, rule)"""
    if sign(tx["kind"]) <= 0:
        return False
    for o in existing:
        if (sign(o["kind"]) > 0
                and o["rule"] != tx["rule"]
                and abs(o["amount"] - tx["amount"]) < 0.005
                and abs(o["date"] - tx["date"]) < WINDOW):
            return True
    return False

D = datetime.fromisoformat
ZI, DEP, CARD = "chase.zelle-in", "chase.deposit", "chase.card"

cases = [
    # name, new tx, existing rows, expect_echo
    ("Zelle $150.07 → Deposit alert도 같은 돈",
     dict(amount=150.07, date=D("2026-08-02T12:33:00"), kind="받은 정산", rule=DEP),
     [dict(amount=150.07, date=D("2026-08-02T12:33:00"), kind="받은 정산", rule=ZI)], True),

    ("급여 $2143.88 — 겹치는 게 없음",
     dict(amount=2143.88, date=D("2026-08-04T07:02:00"), kind="수입", rule=DEP),
     [dict(amount=150.07, date=D("2026-08-02T12:33:00"), kind="받은 정산", rule=ZI)], False),

    ("룸메 둘이 각자 $4.50 (같은 규칙) — 별개 거래",
     dict(amount=4.50, date=D("2026-07-08T11:50:00"), kind="받은 정산", rule=ZI),
     [dict(amount=4.50, date=D("2026-07-08T04:08:00"), kind="받은 정산", rule=ZI)], False),

    ("MTA $3.00 하루 두 번 (지출) — 절대 병합 안 함",
     dict(amount=3.00, date=D("2026-07-25T13:22:00"), kind="지출", rule=CARD),
     [dict(amount=3.00, date=D("2026-07-25T10:02:00"), kind="지출", rule=CARD)], False),

    ("같은 금액이지만 3일 차이 — 별개",
     dict(amount=60.00, date=D("2026-07-06T08:00:00"), kind="받은 정산", rule=DEP),
     [dict(amount=60.00, date=D("2026-07-03T08:17:00"), kind="받은 정산", rule=ZI)], False),

    ("Deposit 먼저 들어오고 Zelle 메일이 나중 (순서 반대)",
     dict(amount=29.35, date=D("2026-08-04T05:35:00"), kind="받은 정산", rule=ZI),
     [dict(amount=29.35, date=D("2026-08-04T09:00:00"), kind="수입", rule=DEP)], True),

    ("지출과 입금이 같은 금액 — 방향 다르면 무관",
     dict(amount=100.00, date=D("2026-07-07T08:37:00"), kind="받은 정산", rule=DEP),
     [dict(amount=100.00, date=D("2026-07-07T08:37:00"), kind="지출", rule="chase.transfer")], False),
]

ok = True
for name, tx, existing, expect in cases:
    got = is_echo(tx, existing)
    mark = "PASS" if got == expect else "FAIL"
    if got != expect: ok = False
    print(f"{mark}  {'병합' if got else '유지':4}  {name}")

print("\nALL ECHO CASES PASS" if ok else "\n*** FAILED ***")
