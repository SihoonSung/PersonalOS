# Python port of the Swift parser logic, tested against real Chase email text.
import re

PROCESSOR_PREFIXES = ["TST*","TST *","SQ *","SQ*","SP ","SP*","MDC*","PY *","PAYPAL *",
                      "IN *","WWW.","GOOGLE *","AMZN MKTP","TOAST*"]

def html_to_text(html):
    for p in [r"<!--.*?-->", r"<style[^>]*>.*?</style>", r"<script[^>]*>.*?</script>", r"<head[^>]*>.*?</head>"]:
        html = re.sub(p, " ", html, flags=re.S|re.I)
    html = re.sub(r"<[^>]+>", " ", html, flags=re.S|re.I)
    named = {"&nbsp;":" ","&amp;":"&","&lt;":"<","&gt;":">","&quot;":'"',"&apos;":"'","&#39;":"'",
             "&#34;":'"',"&reg;":"®","&copy;":"©","&trade;":"™","&hellip;":"…","&mdash;":"—",
             "&ndash;":"–","&middot;":"·","&bull;":"•"}
    for k,v in named.items():
        html = re.sub(re.escape(k), v, html, flags=re.I)
    html = re.sub(r"&#(x?)([0-9A-Fa-f]+);",
                  lambda m: chr(int(m.group(2), 16 if m.group(1) else 10)), html)
    return collapse(html)

def collapse(t):
    t = t.replace(" "," ").replace("​","").replace("͏","").replace("ㅤ"," ")
    return re.sub(r"\s+", " ", t).strip()

def clean(raw):
    v = raw.strip()
    u = v.upper()
    for p in PROCESSOR_PREFIXES:
        if u.startswith(p):
            v = v[len(p):].strip(); break
    for s in [" PENDING"," Pending"]:
        if v.endswith(s): v = v[:-len(s)]
    v = re.sub(r"\s+#\d+$", "", v)
    v = re.sub(r"\s+\d{3}[\s-]\d{3}[\s-]?\d*$", "", v)
    v = collapse(v)
    return v or raw

def cap(pattern, text, group=1):
    m = re.search(pattern, text, flags=re.I)
    if not m: return None
    g = m.group(group)
    return g.strip() if g else None

def first_match(text, patterns):
    for p in patterns:
        m = re.search(p, text, flags=re.I)
        if m:
            return [m.group(0)] + [ (g.strip() if g else None) for g in m.groups() ]
    return None

def num(s):
    return float(s.replace(",", "")) if s else None

def parse_chase(text):
    account = cap(r"Account ending in \(?\D{0,4}(\d{4})\)?", text)
    method = f"Chase ···{account}" if account else "Chase"

    payer = cap(r"payment\s+(.+?)\s+sent you money", text)
    amt = cap(r"Amount \$([0-9,]+\.[0-9]{2})", text)
    if payer and amt:
        note = cap(r"Memo\s+(.+?)\s+is registered", text) or ""
        note = note.replace(payer, "").strip()
        return dict(rule="chase.zelle-in", title=clean(payer), amount=num(amt),
                    kind="받은 정산", method=method+" · Zelle", note=note, date=chase_date(text))

    h = first_match(text, [
        r"You received an? (?:direct )?deposit of \$([0-9,]+\.[0-9]{2})",
        r"Your (?:direct )?deposit of \$([0-9,]+\.[0-9]{2})",
        r"An? (?:direct )?deposit of \$([0-9,]+\.[0-9]{2}) (?:was|has been) (?:posted|made|credited)",
    ])
    if h:
        payer = cap(r"(?:Description|From|Payer|Received from)\s+(.+?)\s+Amount \$", text) or "입금"
        value = num(cap(r"Amount \$([0-9,]+\.[0-9]{2})", text)) or num(h[1])
        if value:
            return dict(rule="chase.deposit", title=clean(payer), amount=value,
                        kind="수입", method=method+" · 입금", date=chase_date(text))

    h = first_match(text, [
        r"You made an? (?:debit card |credit card )?transaction of \$([0-9,]+\.[0-9]{2}) with (.+?)(?= Account ending| Card ending| Made on|$)",
        r"You made an? \$([0-9,]+\.[0-9]{2}) transaction with (.+?)(?= Account ending| Card ending| Made on|$)",
    ])
    if h:
        merchant = cap(r"Description\s+(.+?)\s+Amount \$", text) or h[2] or ""
        value = num(cap(r"Amount \$([0-9,]+\.[0-9]{2})", text)) or num(h[1])
        if value and merchant:
            return dict(rule="chase.card", title=clean(merchant), raw=merchant, amount=value,
                        kind="지출", method=method, date=chase_date(text))

    h = first_match(text, [r"Your bill payment of \$([0-9,]+\.[0-9]{2}) to (.+?)(?= Account ending| Made on|$)"])
    if h:
        r_ = cap(r"Recipient\s+(.+?)\s+Amount \$", text) or h[2] or ""
        value = num(cap(r"Amount \$([0-9,]+\.[0-9]{2})", text)) or num(h[1])
        if value and r_:
            return dict(rule="chase.bill", title=clean(r_), amount=value, kind="지출",
                        method=method+" · 청구서", date=chase_date(text))

    h = first_match(text, [r"You sent \$([0-9,]+\.[0-9]{2}) to (.+?)(?= Account ending| Sent on| with Zelle|$)"])
    if h:
        r_ = cap(r"Recipient\s+(.+?)\s+Amount \$", text) or h[2] or ""
        value = num(cap(r"Amount \$([0-9,]+\.[0-9]{2})", text)) or num(h[1])
        if value and r_:
            return dict(rule="chase.transfer", title=clean(r_), amount=value, kind="지출",
                        method=method+" · 송금", date=chase_date(text))
    return None

def chase_date(text):
    m = first_match(text, [r"(?:Made|Sent|Posted|Received) on ([A-Z][a-z]{2} [0-9]{1,2}, [0-9]{4})(?: at ([0-9]{1,2}:[0-9]{2} [AP]M) ([A-Z]{2,4}))?"])
    if not m: return None
    return (m[1], m[2], m[3])

TAIL = ("You are receiving this alert because this transaction is more than the $1.00 limit you set. "
        "Visit chase.com/alerts to view or manage your settings. Review account Securely access your "
        "accounts with the Chase Mobile ® app or chase.com . About this message Chase Mobile ® app is "
        "available for select mobile devices. Message and data rates may apply. © 2026 JPMorgan Chase & Co.")

CASES = [
 ("card", "Transaction alert You made a debit card transaction of $27.77 with TST* BB.Q CHICKEN US "
          "Account ending in (...9601) Made on Jul 31, 2026 at 5:18 PM ET Description TST* BB.Q CHICKEN US "
          "Amount $27.77 " + TAIL),
 ("card-uber", "Transaction alert You made a debit card transaction of $20.35 with UBER * EATS PENDING "
          "Account ending in (...9601) Made on Jul 27, 2026 at 7:24 PM ET Description UBER * EATS PENDING "
          "Amount $20.35 " + TAIL),
 ("card-365", "Transaction alert You made a debit card transaction of $2.19 with 365 MARKET 888 432-3 "
          "Account ending in (...9601) Made on Jul 27, 2026 at 2:08 PM ET Description 365 MARKET 888 432-3 "
          "Amount $2.19 " + TAIL),
 ("card-tjmaxx", "Transaction alert You made a debit card transaction of $97.00 with TJ MAXX #1371 "
          "Account ending in (...9601) Made on Jul 28, 2026 at 6:49 PM ET Description TJ MAXX #1371 "
          "Amount $97.00 " + TAIL),
 ("transfer", "Transfer alert You sent $10.69 to TESLA MOTORS Account ending in (...9601) "
          "Sent on Jul 28, 2026 at 4:18 AM ET Recipient TESLA MOTORS Amount $10.69 " + TAIL),
 ("bill", "Bill payment Your bill payment of $530.13 to AUTO LEASE 6842 Account ending in (...9601) "
          "Made on Jul 24, 2026 at 5:15 AM ET Recipient AUTO LEASE 6842 Amount $530.13 " + TAIL),
 ("zelle-in", "Zelle® payment HYEWON LEE sent you money Here are the details: Amount $60.72 "
          "Sent on Jul 27, 2026 Transaction number 30163882248 Memo fedex HYEWON LEE is registered with "
          "a Zelle® member bank that offers Zelle® " + TAIL),
 ("zelle-in-nomemo", "Zelle® payment INN KYUNG SEO sent you money Here are the details: Amount $72.00 "
          "Sent on Jul 20, 2026 Transaction number 30088434816 Memo INN KYUNG SEO is registered with a "
          "Zelle® member bank " + TAIL),
 ("deposit-payroll", "Deposit alert You received a direct deposit of $2,143.88 Account ending in (...9601) "
          "Posted on Aug 4, 2026 at 3:02 AM ET Description HL GA PAYROLL Amount $2,143.88 " + TAIL),
 ("deposit-plain", "Deposit alert Your deposit of $500.00 was posted Account ending in (...9601) "
          "Posted on Aug 4, 2026 Description MOBILE CHECK DEPOSIT Amount $500.00 " + TAIL),
 ("deposit-a", "Deposit alert A deposit of $75.00 has been credited to your account Account ending in (...9601) "
          "Posted on Aug 4, 2026 Amount $75.00 " + TAIL),
 # --- negatives ---
 ("NEG-autopay", "Payment scheduled Thank you for setting up automatic payments Here are the details of "
          "your automatic payments for your auto lease account: Pay from (...9601) Pay to (...6842) "
          "Payment amount $530.13 Pay date the 24th of every month " + TAIL),
 ("NEG-zelle-recipient", "Zelle ® settings You added Rm as a recipient or edited their details We'll use "
          "the mobile number, 9127241629, you added whenever you send or request money from them. Go to Zelle®"),
 ("NEG-promo", "Sihoon, cash back offers are expiring soon Activate and earn before these offers are off "
          "the table Get up to $1,000 cash bonus when you invest for your future"),
 ("NEG-creditscore", "You set a new score goal. Congrats! See details about your credit report activity"),
 ("NEG-zelle-canceled", "Zelle® payment Your payment to Uzma Abbas was canceled Here are the details: "
          "Amount $876.55 Send-on date Aug 02, 2026 Memo 1394 Final utility payment Sign in to Zelle® and "
          "try sending the money again."),
 ("NEG-statement", "Statement notification Your latest statement is now available Here are the details: "
          "Account ending in (...9601) If you aren't enrolled to receive paperless statements"),
 ("NEG-connected", "Connected Banking You agreed to share data with American Express American Express will "
          "access your account information securely"),
]

print(f"{'case':22} {'rule':18} {'amount':>9}  title / date")
print("-"*88)
ok = True
for name, text in CASES:
    r = parse_chase(text)
    expect_none = name.startswith("NEG")
    if expect_none:
        status = "PASS" if r is None else "FAIL"
        if r is not None: ok = False
        print(f"{name:22} {'(none expected)':18} {'':>9}  {status}  {r if r else ''}")
    else:
        if r is None:
            ok = False
            print(f"{name:22} {'NO MATCH':18} {'':>9}  FAIL")
        else:
            print(f"{name:22} {r['rule']:18} {r['amount']:>9.2f}  {r['title']!r} {r['kind']} {r['method']} {r.get('date')} {('memo='+repr(r['note'])) if r.get('note') is not None else ''}")

# html_to_text feature check
SAMPLE = ('<html><head><style type="text/css">td { color: #414042; } .x { font-size:12px !important; }'
          '</style></head><body><!-- Start of Content -->'
          '<table><tr><td>Transaction alert</td></tr><tr><td>You made a debit card transaction of $27.77'
          ' with TST* BB.Q CHICKEN US</td></tr></table>'
          '<table><tr><td>Account ending in</td><td>(...9601)</td></tr>'
          '<tr><td>Amount</td><td>$27.77</td></tr></table>'
          '<a href="#">Review&nbsp;account</a> Chase&nbsp;Mobile<span>&reg;</span> app &copy; 2026 '
          'JPMorgan Chase &amp; Co. &#169; &#x2014;</body></html>')
print("\nhtmlToText →", html_to_text(SAMPLE))
assert "color" not in html_to_text(SAMPLE), "CSS leaked into text"
assert "Review account" in html_to_text(SAMPLE)
print("\nALL PARSER CASES PASS" if ok else "\n*** SOME CASES FAILED ***")
