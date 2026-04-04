from pathlib import Path
p = Path(r'D:\X-Plane 12\Resources\plugins\FlyWithLua\Scripts\BravoMultiMode.lua')
if not p.exists():
    print('MISSING')
else:
    text = p.read_text(encoding='utf-8')
    lines = text.splitlines()
    for i in range(1300, 1335):
        if i < len(lines):
            print(f"{i+1}: {lines[i]}")
        else:
            print(f"{i+1}: <no line>")
