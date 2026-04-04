from pathlib import Path
p=Path('FlyWithLua/Scripts/BravoMultiMode.lua')
text=p.read_text(encoding='utf-8')
lines=text.splitlines()
start=1748
end=1776
for ln in range(start, end+1):
    if ln-1 < len(lines):
        print(f"{ln}: {lines[ln-1]}")
    else:
        print(f"{ln}: <no line>")
