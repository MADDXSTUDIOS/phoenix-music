"""Counts how many Lua locals are in scope at once in phoenixmusic.lua.

CC's Lua (Cobalt, ~Lua 5.2) refuses to load a file if any function has more
than 200 locals in scope. This is a rough static count (good enough to warn
well before the limit). Fails (exit 1) at 180 or more.

Usage: python3 tools/localcheck.py phoenixmusic.lua
"""
import re, sys
s=open(sys.argv[1]).read()
tok=re.compile(r'''--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*\'''', re.S)
code=tok.sub(lambda m: re.sub(r'[^\n]',' ',m.group(0)), s)
toks=[(m.group(0), code[:m.start()].count('\n')+1) for m in re.finditer(r'[A-Za-z_]\w*|==|~=|<=|>=|\.\.\.|\.\.|[^\s\w]', code)]
scopes=[0]; pend=0; maxc=(0,0); i=0; N=len(toks)
def bump(ln):
    global maxc
    if sum(scopes)>maxc[0]: maxc=(sum(scopes),ln)
while i<N:
    t,ln=toks[i]
    if t=='local':
        if toks[i+1][0]=='function':
            scopes[-1]+=1; bump(ln); i+=1; continue
        j=i+1; n=1
        while j+1<N and toks[j+1][0]==',':
            n+=1; j+=2
        scopes[-1]+=n; bump(ln); i=j+1; continue
    if t=='function':
        j=i+1
        while toks[j][0]!='(': j+=1
        k=j+1; params=0
        while toks[k][0]!=')':
            if re.match(r'[A-Za-z_]',toks[k][0]) or toks[k][0]=='...': params+=1
            k+=1
        scopes.append(params); bump(ln); i=k+1; continue
    if t=='for':
        j=i+1; n=0
        while toks[j][0] not in('=','in'):
            if re.match(r'[A-Za-z_]',toks[j][0]): n+=1
            j+=1
        scopes.append(n+3); pend+=1; bump(ln); i+=1; continue
    if t=='while': scopes.append(0); pend+=1; i+=1; continue
    if t in('if','repeat'): scopes.append(0); i+=1; continue
    if t=='do':
        if pend: pend-=1
        else: scopes.append(0)
        i+=1; continue
    if t in('end','until'): scopes.pop(); i+=1; continue
    i+=1
print("top-level locals:", scopes[0], "| open scopes left:", len(scopes)-1)
print("worst case locals in scope at once: %d (line %d)" % maxc)

LIMIT = 180
if maxc[0] >= LIMIT:
    print("::error::Too many locals in scope (%d at line %d, limit %d). Move functions into the F/X/P tables or split the file." % (maxc[0], maxc[1], LIMIT))
    sys.exit(1)
