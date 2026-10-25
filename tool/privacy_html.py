"""docs/privacy.md -> standalone docs/privacy.html (no dependencies).

Run: python tool/privacy_html.py
ponytail: handles only the markdown this file uses (#/##/###, "- " lists,
paragraphs, `code`, bare URLs); swap for a real converter if the policy grows.
"""
import html, pathlib, re

root = pathlib.Path(__file__).resolve().parents[1]
src = (root / "docs" / "privacy.md").read_text(encoding="utf-8")

def inline(s):
    s = html.escape(s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    return re.sub(r"(https?://[^\s<]+)", r'<a href="\1">\1</a>', s)

out, para, in_list = [], [], False
def flush():
    global in_list
    if para:
        out.append("<p>" + "<br>".join(inline(p) for p in para) + "</p>")
        para.clear()
    if in_list:
        out.append("</ul>")
        in_list = False

for line in src.splitlines():
    m = re.match(r"(#{1,3}) (.*)", line)
    if m:
        flush()
        lvl = len(m.group(1))
        text = m.group(2)
        attrs = ' id="en"' if text == "English" else ' id="ja"' if text == "日本語" else ""
        out.append(f"<h{lvl}{attrs}>{inline(text)}</h{lvl}>")
    elif line.startswith("- "):
        if para:
            flush()
        if not in_list:
            out.append("<ul>")
            in_list = True
        out.append(f"<li>{inline(line[2:])}</li>")
    elif line.strip():
        if in_list:
            flush()
        para.append(line)
    else:
        flush()
flush()

title = re.match(r"# (.*)", src).group(1)
page = f"""<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<style>
:root {{ color-scheme: light dark; --fg: #1d2a28; --bg: #fff; --muted: #5c6b69; --accent: #1f5f5b; }}
@media (prefers-color-scheme: dark) {{ :root {{ --fg: #e6ecea; --bg: #121716; --muted: #9fb0ad; --accent: #7fc4bd; }} }}
body {{ margin: 0; padding: 24px 16px 64px; font: 16px/1.75 system-ui, -apple-system, "Segoe UI", "Hiragino Sans", "Noto Sans JP", sans-serif; color: var(--fg); background: var(--bg); }}
main {{ max-width: 44rem; margin: 0 auto; }}
h1 {{ font-size: 1.6rem; line-height: 1.3; }} h2 {{ margin-top: 2.5rem; border-top: 1px solid var(--muted); padding-top: 1rem; }}
h3 {{ font-size: 1.05rem; margin: 1.6rem 0 .4rem; }}
nav a {{ margin-right: 1rem; color: var(--accent); }} a {{ color: var(--accent); overflow-wrap: anywhere; }}
code {{ font-size: .9em; background: rgba(127,127,127,.15); padding: 0 .3em; border-radius: 4px; }}
</style>
</head>
<body><main>
<nav><a href="#ja">日本語</a><a href="#en">English</a></nav>
{chr(10).join(out)}
</main></body>
</html>
"""
(root / "docs" / "privacy.html").write_text(page, encoding="utf-8")
print("docs/privacy.html", len(page), "bytes")
