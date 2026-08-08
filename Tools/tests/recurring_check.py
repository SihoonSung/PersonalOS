# Port of RecurringDetector, run against Sihoon's real merchants + synthetic subscriptions.
import re, statistics
from datetime import datetime, timedelta

def normalize(t):
    v = t.upper()
    v = re.sub(r"[0-9]+", " ", v)
    v = re.sub(r"[^A-Z가-힣 ]+", " ", v)
    return re.sub(r"\s+", " ", v).strip()

def median(xs): return statistics.median(xs) if xs else None

def detect(rows, now):
    groups = {}
    for date, amount, title in rows:
        groups.setdefault(normalize(title), []).append((date, amount, title))
    out = []
    for key, obs in groups.items():
        obs.sort()
        if len(obs) < 3: continue
        collapsed = []
        for o in obs:
            if collapsed and collapsed[-1][0].date() == o[0].date(): continue
            collapsed.append(o)
        if len(collapsed) < 3: continue
        gaps = [(b[0]-a[0]).total_seconds()/86400 for a,b in zip(collapsed, collapsed[1:])]
        interval = median(gaps)
        if not interval or not (5 <= interval <= 400): continue
        drift = median([abs(g-interval) for g in gaps])
        if drift > max(2.5, interval*0.15): continue
        amounts = [o[1] for o in collapsed]
        typical = median(amounts)
        if not typical or typical <= 0: continue
        within = sum(1 for a in amounts if abs(a-typical)/typical <= 0.08)
        if within/len(amounts) < 0.6: continue
        out.append(dict(name=collapsed[-1][2], typical=round(typical,2),
                        n=len(collapsed), interval=round(interval), 
                        next=(collapsed[-1][0]+timedelta(days=interval)).strftime("%m/%d")))
    return sorted(out, key=lambda c: c["next"])

D = lambda s: datetime.fromisoformat(s)
now = D("2026-08-04T12:00:00")

rows = []
# --- 진짜 구독 (감지돼야 함) ---
for m in (5,6,7):  rows.append((D(f"2026-0{m}-23T22:04"), 20.00, "OPENAI CHATGPT SUBS"))
for m in (5,6,7):  rows.append((D(f"2026-0{m}-10T12:29"), 19.99, "APPLECARE ONE"))
for m in (5,6,7):  rows.append((D(f"2026-0{m}-16T17:56"),  5.99, "APPLE MUSIC"))
for m in (5,6,7):  rows.append((D(f"2026-0{m}-24T05:15"), 530.13, "AUTO LEASE 6842"))
# 가격 인상된 구독
rows += [(D("2026-05-01T10:00"), 9.99, "NETFLIX"), (D("2026-06-01T10:00"), 9.99, "NETFLIX"),
         (D("2026-07-01T10:00"), 12.99, "NETFLIX")]
# --- 실제 그의 데이터 (감지되면 안 되는 것들) ---
rows += [(D("2026-07-23T15:30"), 2.19, "365 MARKET 888 432-3"),
         (D("2026-07-27T07:55"), 3.35, "365 MARKET 888 432-3"),
         (D("2026-07-27T14:08"), 2.19, "365 MARKET 888 432-3")]
rows += [(D("2026-07-25T10:02"), 3.00, "MTA*NYCT PAYGO"),
         (D("2026-07-25T13:22"), 3.00, "MTA*NYCT PAYGO")]
rows += [(D("2026-06-23T04:16"), 82.59, "TESLA MOTORS"),
         (D("2026-06-23T04:16"), 2465.51, "TESLA MOTORS"),
         (D("2026-06-26T03:26"), 82.59, "TESLA MOTORS"),
         (D("2026-07-28T04:18"), 10.69, "TESLA MOTORS")]
# 자주 가는 식당 — 간격 불규칙
rows += [(D("2026-07-02T12:00"), 14.20, "CAFFE BENE"), (D("2026-07-05T18:00"), 22.10, "CAFFE BENE"),
         (D("2026-07-19T13:00"), 13.89, "CAFFE BENE"), (D("2026-07-26T13:53"), 20.79, "CAFFE BENE")]

found = detect(rows, now)
print(f"{'감지':4} {'가게':24} {'대표금액':>9} {'주기':>5} {'횟수':>4}  다음")
print("-"*66)
for c in found:
    print(f"{'✅':4} {c['name']:24} {c['typical']:>9.2f} {c['interval']:>4}일 {c['n']:>4}  {c['next']}")

names = {c['name'] for c in found}
expect_yes = ["OPENAI CHATGPT SUBS","APPLECARE ONE","APPLE MUSIC","AUTO LEASE 6842","NETFLIX"]
expect_no  = ["365 MARKET 888 432-3","MTA*NYCT PAYGO","TESLA MOTORS","CAFFE BENE"]
print()
ok = True
for n in expect_yes:
    hit = any(n in x for x in names)
    print(("PASS  감지됨   " if hit else "FAIL  놓침     ") + n); ok &= hit
for n in expect_no:
    hit = any(normalize(n) == normalize(x) for x in names)
    print(("FAIL  오탐     " if hit else "PASS  무시됨   ") + n); ok &= not hit
print("\nALL RECURRING CASES PASS" if ok else "\n*** FAILED ***")
