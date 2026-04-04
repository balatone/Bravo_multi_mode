import sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding='utf-8')

out = []
# state machine for Lua strings
in_squote = False
in_dquote = False
in_long = False
long_eq = 0
i = 0
positions = []
while i < len(s):
    ch = s[i]
    # check for start/end of long bracket
    if not in_squote and not in_dquote:
        if s.startswith('[', i):
            # check long bracket
            j = i+1
            eq = 0
            while j < len(s) and s[j] == '=':
                eq += 1; j += 1
            if j < len(s) and s[j] == '[':
                in_long = True; long_eq = eq; i = j+1; continue
        if in_long:
            # check end
            if s.startswith(']', i):
                j = i+1; eq2 = 0
                while j < len(s) and s[j] == '=':
                    eq2 += 1; j += 1
                if j < len(s) and s[j] == ']' and eq2 == long_eq:
                    in_long = False; i = j+1; continue
    # handle quotes
    if not in_long:
        if ch == '"' and not in_squote:
            # check not escaped
            # count preceding backslashes
            k = i-1; esc = 0
            while k >= 0 and s[k] == '\\': esc += 1; k -= 1
            if esc % 2 == 0:
                in_dquote = not in_dquote
        elif ch == "'" and not in_dquote:
            k = i-1; esc = 0
            while k >= 0 and s[k] == '\\': esc += 1; k -= 1
            if esc % 2 == 0:
                in_squote = not in_squote
    # if current char is backslash and not inside any string
    if ch == '\\' and (not in_squote) and (not in_dquote) and (not in_long):
        # record position
        line = s.count('\n', 0, i) + 1
        col = i - s.rfind('\n', 0, i)
        positions.append((line, col, i))
    i += 1

if not positions:
    print('No stray backslashes found outside strings.')
    sys.exit(0)

print('Found backslashes outside strings at:')
for line,col,idx in positions:
    print(f'  line {line} col {col}')

# Make backup
bak = p.with_suffix(p.suffix + '.bak')
if not bak.exists():
    bak.write_text(s, encoding='utf-8')
    print('Backup written to', bak)

# Remove those backslashes
s_list = list(s)
for _,_,idx in reversed(positions):
    del s_list[idx]
new = ''.join(s_list)
# write new file
p.write_text(new, encoding='utf-8')
print('Removed', len(positions), 'backslash(es) and updated file.')
