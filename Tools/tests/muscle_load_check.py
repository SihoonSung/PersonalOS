#!/usr/bin/env python3
"""부하·회복 모델 v1 회귀 검증 — PersonalOS/Workout/MuscleLoad.swift 와 같은 로직.

Swift 를 이 컨테이너에서 컴파일할 수 없어서, 순수 로직만 파이썬으로 옮겨
실제 시나리오로 검증한다. MuscleLoad.swift 를 고치면 이 파일을 먼저 고칠 것.
"""

RECOVERY_H = {"가슴": 72, "등": 72, "하체": 72, "어깨": 48, "팔": 48, "코어": 48, "심폐": 24}
SECONDARY_W = 0.5
DEFAULT_SCORE_NO_SETS = 6
READY, FATIGUED = 20, 60

CATALOG = {
    "bench-press":   (["가슴"], ["팔", "어깨"], True),
    "back-squat":    (["하체"], ["코어", "등"], True),
    "leg-curl":      (["하체"], [], True),
    "lateral-raise": (["어깨"], [], True),
    "pull-up":       (["등"], ["팔"], False),
    "running":       (["심폐"], ["하체"], False),
}

def epley(weight, reps):
    return weight * (1 + reps / 30) if weight > 0 and reps > 0 else 0

def coefficient(best_weight, reps, known_1rm=None):
    one_rm = known_1rm if (known_1rm and known_1rm > 0) else epley(best_weight, reps)
    if one_rm <= 0 or best_weight <= 0:
        return 1.0
    r = best_weight / one_rm
    return 1.5 if r >= 0.85 else (1.0 if r >= 0.70 else 0.7)

def scores(sets, manual_groups=(), one_rms=None):
    one_rms = one_rms or {}
    working = [s for s in sets if not s.get("warmup")]
    if not working:
        return {g: DEFAULT_SCORE_NO_SETS for g in manual_groups}
    by_ex = {}
    for s in working:
        by_ex.setdefault(s["ex"], []).append(s)
    out = {}
    for ex_id, rows in by_ex.items():
        if ex_id not in CATALOG:
            continue
        primary, secondary, uses_load = CATALOG[ex_id]
        if uses_load:
            heaviest = max(rows, key=lambda r: r["w"])
            coef = coefficient(heaviest["w"], heaviest["reps"], one_rms.get(ex_id)) if heaviest["w"] > 0 else 1.0
        else:
            coef = 1.0
        score = len(rows) * coef
        for g in primary:
            out[g] = out.get(g, 0) + score
        for g in secondary:
            out[g] = out.get(g, 0) + score * SECONDARY_W
    return out

def intensity_fatigue(score):
    if score >= 9:  return 100
    if score >= 4:  return 70
    return 40

def decayed(fatigue, hours, group):
    return fatigue * max(0, 1 - hours / RECOVERY_H[group])

def status(f):
    return "피로" if f >= FATIGUED else ("회복 중" if f >= READY else "준비됨")

def weekly_sets(sets, group, manual_groups=()):
    working = [s for s in sets if not s.get("warmup")]
    if not working:
        return 1 if group in manual_groups else 0
    total = 0
    for s in working:
        if s["ex"] not in CATALOG:
            continue
        primary, secondary, _ = CATALOG[s["ex"]]
        if group in primary:     total += 1
        elif group in secondary: total += SECONDARY_W
    return total

def states(sessions, one_rms=None):
    cur, weekly = {}, {}
    for sess in sessions:
        sc = scores(sess["sets"], sess.get("manual", ()), one_rms)
        for g, score in sc.items():
            cur[g] = cur.get(g, 0) + decayed(intensity_fatigue(score), sess["h_ago"], g)
            if sess["h_ago"] <= 7 * 24:
                weekly[g] = weekly.get(g, 0) + weekly_sets(sess["sets"], g, sess.get("manual", ()))
    return {g: (min(v, 100), status(min(v, 100)), weekly.get(g, 0)) for g, v in cur.items()}

fails = []
def check(label, got, want, tol=0.01):
    ok = abs(got - want) < tol if isinstance(want, (int, float)) else got == want
    print(f"{'PASS' if ok else 'FAIL'}  {label:50} got={got} want={want}")
    if not ok: fails.append(label)

print("── 강도계수 (1RM 미기록 → Epley 자기추정) ──")
check("5회 → 저반복 고강도 1.5", coefficient(135, 5), 1.5)
check("8회 → 중강도 1.0",        coefficient(135, 8), 1.0)
check("12회 → 중강도 1.0",       coefficient(90, 12), 1.0)
check("15회 → 저강도 0.7",       coefficient(90, 15), 0.7)
print("\n── 강도계수 (실제 1RM 있음) ──")
check("1RM225 / 135x5 = 60% → 0.7", coefficient(135, 5, 225), 0.7)
check("1RM160 / 135x5 = 84% → 1.0", coefficient(135, 5, 160), 1.0)
check("1RM150 / 135x5 = 90% → 1.5", coefficient(135, 5, 150), 1.5)

print("\n── 세션 점수 (주 부위 그대로, 보조 0.5) ──")
bench5 = [{"ex": "bench-press", "w": 135, "reps": 5} for _ in range(5)]
sc = scores(bench5)
check("벤치 5x5 → 가슴 7.5", sc["가슴"], 7.5)
check("벤치 5x5 → 팔 3.75",  sc["팔"], 3.75)
check("벤치 5x5 → 어깨 3.75", sc["어깨"], 3.75)

leg = [{"ex": "back-squat", "w": 185, "reps": 8} for _ in range(3)] + \
      [{"ex": "leg-curl", "w": 90, "reps": 12} for _ in range(3)]
sc2 = scores(leg)
check("스쿼트3+레그컬3 → 하체 6.0", sc2["하체"], 6.0)
check("스쿼트3 → 코어 1.5",         sc2["코어"], 1.5)

warm = [{"ex": "bench-press", "w": 45, "reps": 10, "warmup": True}] + bench5
check("워밍업 제외 → 가슴 7.5", scores(warm)["가슴"], 7.5)

print("\n── 등급 → 부여 피로도 ──")
check("7.5 → 보통 70",    intensity_fatigue(7.5), 70)
check("9.0 → 빡세게 100", intensity_fatigue(9.0), 100)
check("3.75 → 가볍게 40", intensity_fatigue(3.75), 40)

print("\n── 감쇠 & 상태 (가슴 T=72h) ──")
check("직후 70",      decayed(70, 0, "가슴"), 70)
check("36h 후 35",    decayed(70, 36, "가슴"), 35)
check("36h 상태",     status(decayed(70, 36, "가슴")), "회복 중")
check("60h 후 11.67", decayed(70, 60, "가슴"), 11.666, tol=0.01)
check("60h 상태",     status(decayed(70, 60, "가슴")), "준비됨")
check("72h 후 0",     decayed(70, 72, "가슴"), 0)

print("\n── 세트 없는 세션 (워치 러닝, 심폐 T=24h) ──")
check("기본점수6 → 보통 70", intensity_fatigue(scores([], ["심폐"])["심폐"]), 70)
check("12h 후 심폐 35",      decayed(70, 12, "심폐"), 35)
check("24h 후 심폐 0",       decayed(70, 24, "심폐"), 0)

print("\n── 누적 & 상한 ──")
st = states([{"h_ago": 0, "sets": bench5}, {"h_ago": 1, "sets": bench5}])
check("가슴 2세션 → 140 아닌 100", st["가슴"][0], 100)
check("상한 후 상태 피로",         st["가슴"][1], "피로")

print("\n── 주간 세트 (보조 0.5) ──")
check("벤치 5세트 → 가슴 5", weekly_sets(bench5, "가슴"), 5)
check("벤치 5세트 → 팔 2.5", weekly_sets(bench5, "팔"), 2.5)
check("맨몸 풀업도 셈",       weekly_sets([{"ex": "pull-up", "w": 0, "reps": 8}] * 4, "등"), 4)

print("\n── 회복 예상 시각 ──")
check("부여70 가슴 → 51.43h 뒤", RECOVERY_H["가슴"] * (1 - READY / 70), 51.428, tol=0.01)

print("\n── 실사용 시나리오: 월 가슴 / 수 하체 / 금 오늘 ──")
week = [
    {"h_ago": 96, "sets": bench5},                                   # 4일 전
    {"h_ago": 48, "sets": leg},                                      # 2일 전
    {"h_ago": 2,  "sets": [{"ex": "lateral-raise", "w": 20, "reps": 12}] * 4},
]
st = states(week)
check("4일 전 가슴 → 완전 회복", st.get("가슴", (0,))[0], 0)
check("2일 전 하체 → 회복 중",   st["하체"][1], "회복 중")
check("방금 어깨 → 피로",        st["어깨"][1], "피로")

print()
if fails:
    print(f"FAILED {len(fails)}: {fails}")
    raise SystemExit(1)
print("ALL MUSCLE LOAD CASES PASS")
