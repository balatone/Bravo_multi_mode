import os
for root, dirs, files in os.walk('.'):
    for f in files:
        if f.endswith('.lua'):
            p = os.path.join(root, f)
            with open(p, 'r', encoding='utf-8', errors='ignore') as fh:
                s = fh.read()
                if 'bravo_hid_poll_task' in s:
                    print(p)
                    for i, line in enumerate(s.splitlines(), start=1):
                        if 'bravo_hid_poll_task' in line:
                            print(f'  {i}: {line}')
