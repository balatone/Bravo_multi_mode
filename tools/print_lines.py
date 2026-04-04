from pathlib import Path
import sys
p=Path('FlyWithLua/Scripts/BravoMultiMode.lua')
text=p.read_text(encoding='utf-8')
lines=text.splitlines()
start=1315
end=1325
for ln in range(start, end+1):
    if ln-1 < len(lines):
        line=lines[ln-1]
        bytes_list=[f"0x{ord(c):02X}" for c in line]
        print(f"{ln}: {line}")
        print('BYTES:', ' '.join(bytes_list))
    else:
        print(f"{ln}: <no line>")
