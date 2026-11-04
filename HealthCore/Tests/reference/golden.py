"""Independent reference implementation for the HealthCore golden-vector tests.

The expected numbers in Tests/HealthCoreTests are produced by this script, not by the Swift code,
so a test failure means the two implementations disagree. Run: python3 golden.py
Fixtures here must match the ones built in Fixtures.swift. Days are integer offsets from "today" (0).
"""
import math
import numpy as np
from scipy.stats import norm


def show(name, value):
    print(f"{name} = {value!r}")


# Stats
x = [2, 4, 4, 4, 5, 5, 7, 9]
show("sd", float(np.std(x, ddof=1)))
q = [3.0, 1.0, 4.0, 1.0, 5.0, 9.0, 2.0, 6.0]
for p in (0.0, 0.1, 0.25, 0.5, 0.9, 1.0):
    show(f"percentile {p}", float(np.percentile(q, p * 100)))  # numpy default is Hyndman-Fan type 7
for z in (0.0, 1.0, -1.96, 2.5):
    show(f"normalCDF {z}", float(norm.cdf(z)))


# Recovery fixture: 120 alternating baseline days, then a bad morning
def hrv(d):   return 40.0 if d == 0 else (50.0 if d % 2 == 0 else 60.0)
def rhr(d):   return 58.0 if d == 0 else (50.0 if d % 2 == 0 else 54.0)
def sleep(d): return 6.0 if d == 0 else (7.0 if d % 2 == 0 else 8.0)
def rr(d):    return 17.0 if d == 0 else (14.0 if d % 2 == 0 else 15.0)
DAYS = range(-120, 1)


def z(series, day, log):
    f = math.log if log else (lambda v: v)
    base = [f(series(d)) for d in range(day - 60, day) if d in DAYS]
    if len(base) < 14:
        return None
    return (f(series(day)) - np.mean(base)) / np.std(base, ddof=1)


def raw(day, with_rr=True):
    hz, rz, sz = z(hrv, day, True), z(rhr, day, False), z(sleep, day, False)
    bz = z(rr, day, False) if with_rr else None
    parts = [(0.55, hz), (0.20, -rz), (0.10, None if bz is None else -bz), (0.15, sz)]
    parts = [(w, v) for w, v in parts if v is not None]
    combined = sum(w * v for w, v in parts) / sum(w for w, _ in parts)
    return 100 * norm.cdf(combined), hz, rz, bz


score, hz, rz, bz = raw(0)
past = [raw(d)[0] for d in range(-30, 0)]
show("recovery score", score)
show("recovery hrvZ", hz)
show("recovery rhrZ", rz)
show("recovery rrZ", bz)
show("recovery score without rr", raw(0, with_rr=False)[0])

# 7-day rolling lnHRV, z against the rolling values of the previous 60 days
def rolling(d):
    return np.mean([math.log(hrv(x)) for x in range(d - 6, d + 1)])
past_roll = [rolling(d) for d in range(-60, 0)]
show("hrv trend z", (rolling(0) - np.mean(past_roll)) / np.std(past_roll, ddof=1))
show("recovery low", float(np.percentile(past, 25)))
show("recovery high", float(np.percentile(past, 75)))
show("sleep p10 of past 60", float(np.percentile([sleep(d) for d in range(-60, 0)], 10)))

# Only resting HR present: weight renormalizes to 1, so score = 100 * Phi(-zRHR)
show("rhr only score", 100 * norm.cdf(-rz))

# Sleep summary over the recovery fixture, need 8 h: nights -6..0 are 7,8,7,8,7,8,6
week = [sleep(d) for d in range(-6, 1)]
show("sleep avg7", float(np.mean(week)))
show("sleep debt7", sum(max(0, 8 - h) for h in week))
# Every fixture night ends 07:00, so the midpoint is 07:00 minus half the duration, in minutes since noon
mid = [(19 * 60 - h * 30) for h in week]
show("sleep consistency", float(np.std(mid, ddof=1)))

# ACWR: 21 days at 400 kcal then 7 days at 600, ending yesterday
active = [400.0] * 21 + [600.0] * 7
show("acwr", np.mean(active[-7:]) / np.mean(active))

# EMA alpha 0.2 and OLS slope of the EMA for a linear weight gain of 0.05 kg/day over 28 days
def ema(v, a=0.2):
    out, prev = [], None
    for x in v:
        prev = x if prev is None else prev + a * (x - prev)
        out.append(prev)
    return out

show("ema", ema([70.0, 71.0, 72.0]))
w = [75.0 + 0.05 * i for i in range(28)]
e = ema(w)
show("body trend last", e[-1])
show("body rate per week", float(np.polyfit(range(28), e, 1)[0]) * 7)

# Journal impact: scores for days -9..0, "Alcohol" tagged on days -9, -7, -5 (so next mornings -8, -6, -4)
scores = {d: v for d, v in zip(range(-9, 1), [70, 40, 72, 45, 68, 50, 75, 71, 69, 73])}
tagged = {-9, -7, -5}
with_ = [scores[d + 1] for d in tagged if d + 1 in scores]
without = [v for d, v in scores.items() if d - 1 not in tagged]
show("impact delta", np.mean(with_) - np.mean(without))

# Vitals: resting HR from the recovery fixture, previous 60 days alternate 50/54, today 58; range is mean +- 2 SD
base = [rhr(d) for d in range(-60, 0)]
m, sd = np.mean(base), np.std(base, ddof=1)
show("vitals rhr low", m - 2 * sd)
show("vitals rhr high", m + 2 * sd)

# Sleep Regularity Index, Phillips et al. 2017. Window: noon day -7 to noon day 0, 1-min epochs.
# Fixture nights end at 07:00 and last sleep(d) hours, so they start at 07:00 - sleep(d).
MIN = 7 * 1440
state = np.zeros(MIN, dtype=bool)
for d in range(-120, 1):
    end_min = (d + 7) * 1440 - 5 * 60           # 07:00 on day d, minutes after noon on day -7
    start_min = end_min - int(sleep(d) * 60)
    a, b = max(0, start_min), min(MIN, end_min)
    if a < b:
        state[a:b] = True
same = np.sum(state[:MIN - 1440] == state[1440:])
sri = -100 + 200 * same / (MIN - 1440)
show("sri", float(sri))

# Sleep score for the bad morning. Sleeping HR fixture: alternating 48/50, today 56. No stage data, so no depth.
def shr(d): return 56.0 if d == 0 else (48.0 if d % 2 == 0 else 50.0)
clamp = lambda x: min(1.0, max(0.0, x))
dur = 100 * clamp((6 / 8 - 0.5) / 0.5)
waso = 100 * clamp(1 - (0 - 30) / 90)
reg = 100 * clamp(sri / 100)
hrv_s = 100 * clamp(1 + min(hz, 0) / 3)
hr_z = z(shr, 0, False)
hr_s = 100 * clamp(1 - max(hr_z, 0) / 3)
parts = [(0.30, dur), (0.20, waso), (0.15, reg), (0.15, hrv_s), (0.10, hr_s)]
show("sleep hr z", hr_z)
show("sleep score", sum(w * v for w, v in parts) / sum(w for w, _ in parts))

# Banister TRIMP (Morton et al. 1990). Workout: one HR sample per minute for 30 min, 100 + 2*i bpm,
# ending at minute 30. Rest 50, max from Tanaka at age 21 = 208 - 0.7*21 = 193.3. Dt capped at 2 min.
def trimp(hr, rest, mx, a, b):
    t, zones = 0.0, [0.0] * 5
    for x in hr:
        hrr = min(1, max(0, (x - rest) / (mx - rest)))
        t += 1.0 * hrr * a * math.exp(b * hrr)
        if hrr >= 0.5:
            zones[min(4, int((hrr - 0.5) * 10))] += 1.0
    return t, zones
hr = [100 + 2 * i for i in range(30)]
t_m, zones = trimp(hr, 50, 193.3, 0.64, 1.92)
t_f, _ = trimp(hr, 50, 193.3, 0.86, 1.67)
show("trimp male", t_m)
show("trimp female", t_f)
show("zone minutes", zones)

# Fitness and fatigue: alternating 0 and 100 load for 60 days, starting at 0
kc, ka = math.exp(-1 / 42), math.exp(-1 / 7)
ctl = atl = 0.0
for i in range(60):
    load = 100.0 if i % 2 else 0.0
    ctl = ctl * kc + load * (1 - kc)
    atl = atl * ka + load * (1 - ka)
show("ctl", ctl)
show("atl", atl)

# Tau calibration: training days with TRIMP 50..90, median 70, tau = 70 / ln 2
show("tau", 70 / math.log(2))

# Strong export: strong_sample.csv, read with Python's csv module. Warm-ups (Set Order W) and rows without reps
# are left out. e1RM is Epley, weight * (1 + reps / 30), only for 1 to 10 reps.
import csv, os
def epley(w, r):
    if w <= 0 or not 1 <= r <= 10:
        return None
    return w if r == 1 else w * (1 + r / 30)
with open(os.path.join(os.path.dirname(__file__), "strong_sample.csv"), newline="") as f:
    rows = [r for r in csv.DictReader(f) if int(r["Reps"] or 0) > 0]
sessions = {}
for r in rows:
    sessions.setdefault((r["Date"], r["Workout Name"]), []).append(r)
for key, sets in sessions.items():
    working = [s for s in sets if s["Set Order"] != "W"]
    show(f"strong {key[1]} sets", len(sets))
    show(f"strong {key[1]} volume load", sum(float(s["Weight"]) * int(s["Reps"]) for s in working))
    for ex in dict.fromkeys(s["Exercise Name"] for s in working):
        e = [epley(float(s["Weight"]), int(s["Reps"])) for s in working if s["Exercise Name"] == ex]
        show(f"strong {ex} best e1rm", max([x for x in e if x is not None], default=None))
show("strong 225 lbs x5 e1rm kg", epley(225 * 0.45359237, 5))

# Adaptive TDEE. Weight 70 + 0.05 kg/day from day -60, no weigh-in when d % 5 == 0. Intake 2700 on even days,
# 2950 on odd, nothing logged when d % 7 == 0. Window is the 28 days ending day -1. TDEE = mean logged intake
# minus the OLS slope (kg/day) of the EMA trend weight in the window times 7700 (Wishnofsky 1958).
wdays = [d for d in range(-60, 0) if d % 5 != 0]
trend = ema([70 + 0.05 * (d + 60) for d in wdays])
win = [(d, t) for d, t in zip(wdays, trend) if -28 <= d <= -1]
slope = np.polyfit([d for d, _ in win], [t for _, t in win], 1)[0]
logged = [2700.0 if d % 2 == 0 else 2950.0 for d in range(-28, 0) if d % 7 != 0]
show("tdee intake", float(np.mean(logged)))
show("tdee slope per week", slope * 7)
show("tdee", float(np.mean(logged)) - slope * 7700)
show("tdee logged days", len(logged))

# Insights: partial correlation with weekday dummies (and a covariate), effective n from lag-1 autocorrelations
# (Bretherton et al. 1999), Fisher z interval and p, median split means. Index i, weekday = i % 7 + 1.
from scipy import stats as sps
N = 90
I = np.arange(N)
X = np.sin(0.7 * I) + 0.3 * (I % 7 == 1) + 0.02 * I
S = 7 + np.sin(0.3 * I)
Y = 0.5 * X + np.cos(1.3 * I) + 0.4 * (I % 7 == 5) - 0.3 * S
def resid(v, cov):
    cols = [np.ones(N)] + [(I % 7 + 1 == w).astype(float) for w in range(2, 8)] + cov
    A = np.column_stack(cols)
    beta, *_ = np.linalg.lstsq(A, v, rcond=None)
    return v - A @ beta
def ac1(v):
    m = v.mean()
    return float(np.sum((v[:-1] - m) * (v[1:] - m)) / np.sum((v - m) ** 2))
for label, cov in (("with sleep", [S]), ("weekday only", [])):
    rx, ry = resid(X, cov), resid(Y, cov)
    r = float(np.corrcoef(rx, ry)[0, 1])
    a, b = ac1(rx), ac1(ry)
    neff = min(N, max(4, N * (1 - a * b) / (1 + a * b)))
    z, se = math.atanh(r), 1 / math.sqrt(neff - 3)
    show(f"insight {label} r", r)
    show(f"insight {label} neff", neff)
    show(f"insight {label} ci", (math.tanh(z - 1.959964 * se), math.tanh(z + 1.959964 * se)))
    show(f"insight {label} p", 2 * (1 - norm.cdf(abs(z) / se)))
med = float(np.median(X))
show("insight median", med)
show("insight low mean", float(Y[X < med].mean()))
show("insight high mean", float(Y[X >= med].mean()))
show("bh q", [float(v) for v in sps.false_discovery_control([0.01, 0.04, 0.03, 0.20, 0.002])])

# Readiness model: Bayesian linear regression with a conjugate Normal prior (Bishop 2006, eq. 3.50-3.51) and an
# empirical Bayes noise variance (var(y), then RSS/(n-k) at the posterior mean, then refit).
# Mornings i = 0..79 on day offsets i - 79. Strength on day j when j % 2 == 0 and j % 10 != 0, other when j % 7 == 3.
def st(j): return 1.0 if j >= 0 and j % 2 == 0 and j % 10 != 0 else 0.0
def ot(j): return 1.0 if j >= 0 and j % 7 == 3 else 0.0
yv = [55 + 8 * math.sin(0.9 * i) - 6 * st(i - 1) + 2 * st(i - 2) - 3 * ot(i - 1) for i in range(80)]
mu = float(np.mean(yv))
Xr = np.array([[yv[i - 1] - mu] + [st(i - k) for k in range(1, 5)] + [ot(i - k) for k in range(1, 5)] for i in range(1, 80)])
Yr = np.array([yv[i] - mu for i in range(1, 80)])
m0 = np.array([0.5] + [0.0] * 8)
s0 = np.array([0.25] + [10.0, 5.0, 2.5, 1.25] * 2)
def post(sig2):
    prec = np.diag(1 / s0 ** 2) + Xr.T @ Xr / sig2
    cov = np.linalg.inv(prec)
    return cov @ (m0 / s0 ** 2 + Xr.T @ Yr / sig2), cov
mean1, _ = post(float(np.var(Yr, ddof=1)))
sig2 = float(np.sum((Yr - Xr @ mean1) ** 2) / (len(Yr) - 9))
meanF, covF = post(sig2)
show("bayes mu", mu)
show("bayes sigma2", sig2)
show("bayes mean", [float(v) for v in meanF])
show("bayes var phi", float(covF[0, 0]))
# Impulse response of one strength session from baseline: d1 = b1, dh = phi * d(h-1) + bh
d, curve = 0.0, []
for h in range(1, 6):
    d = meanF[0] * d + (meanF[h] if h <= 4 else 0.0)
    curve.append(float(d))
show("bayes strength curve", curve)

# Recovery breakdown: exact Shapley values in score points over the four inputs of the bad-morning fixture.
# Value of a coalition = 100 * Phi(sum of its contributions); absent inputs sit at normal (contribution 0).
import itertools
def rec_series(d, a, b, today):   # the recovery fixture: alternating a and b, then today's value
    return today if d == 0 else (a if d % 2 == 0 else b)
def rec_z(f, log):
    g = math.log if log else (lambda v: v)
    base = [g(f(d)) for d in range(-60, 0)]
    return (g(f(0)) - np.mean(base)) / np.std(base, ddof=1)
contrib = {"hrv": 0.55 * rec_z(lambda d: rec_series(d, 50, 60, 40), True),
           "restingHR": -0.20 * rec_z(lambda d: rec_series(d, 50, 54, 58), False),
           "breathing": -0.10 * rec_z(lambda d: rec_series(d, 14, 15, 17), False),
           "sleep": 0.15 * rec_z(lambda d: rec_series(d, 7, 8, 6), False)}
names = list(contrib)
def coalition(members):
    return 100 * norm.cdf(sum(contrib[m] for m in members))
phi = {n: 0.0 for n in names}
orders = list(itertools.permutations(names))
for order in orders:
    members = []
    for n in order:
        before = coalition(members)
        members.append(n)
        phi[n] += coalition(members) - before
for n in names:
    show(f"shapley {n}", phi[n] / len(orders))
show("shapley sum + 50", sum(phi.values()) / len(orders) + 50)
show("what-if hrv normal", 100 * norm.cdf(sum(v for k, v in contrib.items() if k != "hrv")))

# Feel check-in agreement: Spearman's rho (average ranks for ties) between a 1-5 rating and the score over
# 20 mornings, with the Fieller-Hartley-Pearson interval tanh(atanh(rho) +- 1.96 * sqrt(1.06 / (n - 3))).
from scipy.stats import spearmanr
feel = [(i * 7) % 5 + 1 for i in range(20)]
score = [40 + 4 * feel[i] + 2 * ((i * 13) % 11) - 10 for i in range(20)]
rho = float(spearmanr(feel, score).statistic)
se = math.sqrt(1.06 / (20 - 3))
show("feel rho", rho)
show("feel ci", (math.tanh(math.atanh(rho) - 1.959964 * se), math.tanh(math.atanh(rho) + 1.959964 * se)))

# Room air change rate: CO2 decay C(t) = 420 + 1800 * exp(-0.3 t) + 15 sin(7 t), one sample a minute for
# 3 hours. Grid over C_out 300..600 ppm (step 1, only below the last reading - 5): fit ln(C - C_out) = a + b t by
# OLS, score the SSE in ppm, keep the best. lambda = -b, C0 = C_out + exp(a).
ts = [i / 60 for i in range(181)]
cs = [420 + 1800 * math.exp(-0.3 * t) + 15 * math.sin(7 * t) for t in ts]
best = None
for cout in range(300, 601):
    if cout >= cs[-1] - 5:
        continue
    b, a = np.polyfit(ts, [math.log(c - cout) for c in cs], 1)
    sse = sum((c - (cout + math.exp(a) * math.exp(b * t))) ** 2 for t, c in zip(ts, cs))
    if b < 0 and (best is None or sse < best[0]):
        best = (sse, -b, cout + math.exp(a), cout)
show("room ach", best[1])
show("room c0", best[2])
show("room outdoor", best[3])
