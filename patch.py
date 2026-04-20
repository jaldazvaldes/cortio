import re

with open('InterruptioUI.lua', 'r', encoding='utf-8') as f:
    text = f.read()

# Pattern 1
def rep1(m):
    return m.group(1) + m.group(2) + m.group(3)
P1 = r'([ \t]+)\(InterruptioDB and InterruptioDB\.[a-zA-Z0-9_]+\) or ([\-\w\.\"]+)(,\s*)'
text = re.sub(P1, rep1, text)

# Pattern 2
def rep2(m):
    return m.group(1) + m.group(2) + m.group(3)
P2 = r'([ \t]+)\(not InterruptioDB or InterruptioDB\.[a-zA-Z0-9_]+ == nil\) and ([\w\.]+) or InterruptioDB\.[a-zA-Z0-9_]+(,\s*)'
text = re.sub(P2, rep2, text)

with open('InterruptioUI.lua', 'w', encoding='utf-8') as f:
    f.write(text)
