#!/usr/bin/env python3
"""실효 월 예산 회귀 검증 — PersonalOS/Core/BudgetMath.swift 와 같은 로직.

받은 정산은 지출/수입 통계엔 안 잡히지만(EntryKind §3-1) 그 달에 실제로
더 쓸 수 있는 돈이라 예산을 그만큼 올린다.
"""

from datetime import datetime

EXPENSE, INCOME, SETTLE_IN, SETTLE_OUT = "지출", "수입", "받은 정산", "보낸 정산"


def same_month(a, b):
    return (a.year, a.month) == (b.year, b.month)


def settled_in(entries, month):
    """그 달 받은 정산 합계."""
    return sum(abs(e["amount"]) for e in entries
               if e["kind"] == SETTLE_IN and same_month(e["date"], month))


def effective(base, entries, month):
    """예산 미설정(0)이면 정산이 있어도 0 — '미설정' 안내가 사라지면 더 헷갈린다."""
    if base <= 0:
        return 0.0
    return base + settled_in(entries, month)


def spent(entries, month):
    """지출만 집계 — 정산은 여기 안 들어간다."""
    return sum(abs(e["amount"]) for e in entries
               if e["kind"] == EXPENSE and same_month(e["date"], month))


AUG = datetime(2026, 8, 15)
JUL = datetime(2026, 7, 15)


def e(kind, amount, date=AUG):
    return {"kind": kind, "amount": amount, "date": date}


CASES = [
    ("정산 없으면 그대로", 3000, [e(EXPENSE, 100)], AUG, 3000, 100),

    ("룸메 정산 시나리오 — 공과금 876 내고 438 돌려받음",
     3000, [e(EXPENSE, 876.55), e(SETTLE_IN, 438.28)], AUG, 3438.28, 876.55),

    ("받은 정산 여러 건 합산",
     2000, [e(SETTLE_IN, 50), e(SETTLE_IN, 25.5), e(EXPENSE, 300)], AUG, 2075.5, 300),

    ("보낸 정산은 예산을 올리지 않는다",
     2000, [e(SETTLE_OUT, 500), e(EXPENSE, 100)], AUG, 2000, 100),

    ("수입은 예산을 올리지 않는다 — 월급은 예산과 별개",
     2000, [e(INCOME, 4000), e(EXPENSE, 100)], AUG, 2000, 100),

    ("지난달 정산은 이번 달 예산에 안 낀다",
     2000, [e(SETTLE_IN, 900, JUL), e(EXPENSE, 100)], AUG, 2000, 100),

    ("예산 미설정이면 정산이 있어도 0",
     0, [e(SETTLE_IN, 900), e(EXPENSE, 100)], AUG, 0, 100),

    ("음수로 저장된 정산도 절대값으로 더한다",
     1000, [e(SETTLE_IN, -200)], AUG, 1200, 0),

    ("정산이 지출 집계를 건드리지 않는다 — 예산만 오른다",
     1000, [e(EXPENSE, 400), e(SETTLE_IN, 400)], AUG, 1400, 400),
]


def main():
    failures = 0
    for name, base, entries, month, want_budget, want_spent in CASES:
        got_budget = effective(base, entries, month)
        got_spent = spent(entries, month)
        ok_b = abs(got_budget - want_budget) < 0.005
        ok_s = abs(got_spent - want_spent) < 0.005
        if ok_b and ok_s:
            remaining = got_budget - got_spent if got_budget > 0 else None
            tail = f"남음 {remaining:.2f}" if remaining is not None else "예산 미설정"
            print(f"PASS  {name:52} 예산 {got_budget:8.2f} / 지출 {got_spent:7.2f} / {tail}")
        else:
            failures += 1
            print(f"FAIL  {name}\n      예산 기대 {want_budget} 실제 {got_budget}"
                  f" / 지출 기대 {want_spent} 실제 {got_spent}")
    print()
    print("ALL BUDGET UPLIFT CASES PASS" if not failures else f"{failures}건 실패")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
