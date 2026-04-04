from pathlib import Path
p=Path('FlyWithLua/Scripts/BravoMultiMode.lua')
s=p.read_text(encoding='utf-8')
start_token='on_trim_changed = function(v)'
idx=s.find(start_token)
if idx==-1:
    print('start token not found')
    raise SystemExit(1)
# find the 'end' that closes this function by searching for a line that is '    end' after idx
lines=s.splitlines(True)
# find line index containing start_token
line_no=0
char_count=0
for i,l in enumerate(lines):
    if s.find(start_token, char_count, char_count+len(l))!=-1 or start_token in l:
        # but safer: check if this line contains start_token
        if start_token in l:
            line_no=i
            break
    char_count+=len(l)
else:
    # fallback: search by char index
    cum=0
    for i,l in enumerate(lines):
        cum+=len(l)
        if cum>idx:
            line_no=i
            break
# now find the next line equal to '    end' (4 spaces then end) or a line that is 'end' with similar indent
end_line=None
for j in range(line_no+1, len(lines)):
    if lines[j].strip()== 'end':
        # ensure it's the function's closing by checking next non-empty char maybe
        end_line=j
        break
if end_line is None:
    print('end not found')
    raise SystemExit(1)
# replace lines from line_no to end_line inclusive
new_block = '''on_trim_changed = function(v)
        if v == "down" then
            pcall(handle_bravo_trim_nose_down, true)
        elseif v == "up" then
            pcall(handle_bravo_trim_nose_up, true)
        else
            log.info('Decoder: trim change raw=' .. tostring(v))
        end
    end'''
lines[line_no:end_line+1]=[new_block+'\n']
new=''.join(lines)
# write backup
bak=p.with_suffix('.lua.bak')
if not bak.exists():
    bak.write_text(s, encoding='utf-8')
    print('backup created', bak)
p.write_text(new, encoding='utf-8')
print('patched')
