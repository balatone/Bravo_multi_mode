from pathlib import Path
p=Path(r'D:\X-Plane 12\Resources\plugins\FlyWithLua\Scripts\BravoMultiMode.lua')
if not p.exists():
    print('MISSING')
    raise SystemExit(1)
s=p.read_text(encoding='utf-8')
start = s.find('local function refresh_selector_hid(')
if start == -1:
    print('start not found')
    raise SystemExit(1)
# find the 'end' that closes the function by searching for '\nend\n' after start
endpos = s.find('\nend\n', start)
if endpos == -1:
    print('end not found')
    raise SystemExit(1)
endpos += len('\nend\n')
new_func = '''local function refresh_selector_hid()
    -- Use decoded selector state from the modular decoder/state instead of calling hid_read()
    local sel = bravo_state.get_selector()
    if sel and type(sel) == "number" and sel > 0 then
        -- Map decoded raw selector to index if known
        if sel >= 1 and sel <= 5 then
            set_current_selector(sel)
        else
            -- Unknown raw, log for later mapping
            log.debug("refresh_selector_hid: decoded selector raw=" .. tostring(sel))
        end
    end
end
'''
new = s[:start] + new_func + s[endpos:]
backup = p.with_suffix('.lua.bak')
if not backup.exists():
    backup.write_text(s, encoding='utf-8')
    print('backup written to', backup)
p.write_text(new, encoding='utf-8')
print('replaced')
