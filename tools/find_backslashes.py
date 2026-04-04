from pathlib import Path

paths = [
    Path('FlyWithLua/Scripts/BravoMultiMode.lua'),
    Path(r'D:\X-Plane 12\Resources\plugins\FlyWithLua\Scripts\BravoMultiMode.lua')
]

for p in paths:
    print('---', p)
    if not p.exists():
        print('MISSING')
        continue
    text = p.read_bytes()
    found = False
    for i, b in enumerate(text):
        if b == 0x5C: # backslash
            found = True
            # compute line number
            prefix = text[:i]
            line = prefix.count(b'\n') + 1
            # show context
            start = max(0, i-20)
            end = min(len(text), i+20)
            ctx = text[start:end]
            print(f'pos={i} line={line} ctx={ctx!r}')
    if not found:
        print('No backslash (0x5C) bytes found in file')
