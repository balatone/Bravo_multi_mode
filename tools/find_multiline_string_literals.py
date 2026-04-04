import sys
from pathlib import Path
import re

p = Path(r'D:\X-Plane 12\Resources\plugins\FlyWithLua\Scripts\BravoMultiMode.lua')
s = p.read_text(encoding='utf-8')

pairs = []
 i = 0
length = len(s)

# find single-line quoted strings (handles escaped quotes)
pattern = re.compile(r"(?P<quote>['\"])((?:\\.|(?!\1).)*?)\1", re.DOTALL)
for m in pattern.finditer(s):
    quote = m.group('quote')
    content = m.group(2)
    if '\n' in content or '\r' in content or '\n' in m.group(0):
        # actual unescaped newlines unlikely inside single-line strings, but check
        start = s.count('\n', 0, m.start()) + 1
        col = m.start() - s.rfind('\n', 0, m.start())
        print(f"Found quoted string starting at line {start} col {col} with length {len(content)}")
        snippet = m.group(0)
        print('SNIPPET:', repr(snippet[:200]))

# find long bracket strings [[...]] with optional equal signs
lb_pattern = re.compile(r"\[(=*)\[(.*?)\]\1\]", re.DOTALL)
for m in lb_pattern.finditer(s):
    content = m.group(2)
    if '\n' in content:
        start = s.count('\n', 0, m.start()) + 1
        print(f"Found long-bracket string at line {start}, length {len(content)}")
        print('SNIPPET:', repr(content[:200]))

print('Done')
