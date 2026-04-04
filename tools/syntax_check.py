import os
import subprocess
from pathlib import Path

lua_exe = r"C:\apps\lua\lua55.exe"
root = Path('.')
failed = []
print('Using lua:', lua_exe)
for dirpath, dirnames, filenames in os.walk(root):
    # skip hidden .git etc? we'll include all
    for fn in filenames:
        if fn.endswith('.lua'):
            p = Path(dirpath) / fn
            # convert to absolute posix-like path for Lua
            ap = str(p.resolve()).replace('\\', '/')
            code = "local f,err=loadfile('%s'); if not f then io.write('ERROR: %s\n'..err..'\n') else io.write('OK: %s\n') end" % (ap, ap, ap)
            try:
                proc = subprocess.run([lua_exe, '-e', code], capture_output=True, text=True, timeout=10)
                out = proc.stdout.strip()
                err = proc.stderr.strip()
                if out.startswith('ERROR:'):
                    print(out)
                    failed.append((p, out + ('\n' + err if err else '')))
                else:
                    print(out)
            except Exception as e:
                print('FAILED to run lua on', ap, e)
                failed.append((p, str(e)))

print('\nDone. %d files failed.' % len(failed))
if failed:
    for p,msg in failed:
        print('---')
        print(p)
        print(msg)
