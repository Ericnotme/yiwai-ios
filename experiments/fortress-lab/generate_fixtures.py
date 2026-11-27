# Run with path to the reviewed V2 Python verifier as argv[1]. No internet.
import sys, importlib.util
from itertools import product
sp=importlib.util.spec_from_file_location('corner',sys.argv[1]); m=importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
def sq(s): return chr(97+s%8)+str(s//8+1)
def fen(k,b,p,t,prom=None):
    board={k:'K',t:'k'}
    if b!=-1: board[b]='B'
    if p!=-1: board[p]=prom or 'P'
    rows=[]
    for r in range(7,-1,-1):
        text=''; n=0
        for x in range(8):
            c=board.get(r*8+x)
            if c:
                if n: text+=str(n); n=0
                text+=c
            else:n+=1
        if n:text+=str(n)
        rows.append(text)
    return '/'.join(rows)+' b - - 0 1'
for k,b,p,t in product(m.S,(m.NONE,*m.DARK),range(8,49,8),m.Z):
    if m.valid(k,b,p,t,False):
        moves=sorted(sq(t)+sq(u) for _,_,_,u in m.bmoves(k,b,p,t))
        expected=(sq(t)+'a8') if t!=m.C else (moves[0] if moves else 'terminal')
        print(fen(k,b,p,t),','.join(moves),expected,'regular',sep='\t')
    if p==48 and m.valid(k,b,p,t,True):
        for _,(kk,bb,pp,tt),promo in m.wmoves(k,b,p,t):
            if promo:
                move=sq(tt)+'a8'
                # A certified legal immediate capture is sufficient. We pass it as a singleton fixture,
                # not as a claim that it is the full legal reply set for the promoted piece.
                print(fen(kk,bb,pp,tt,promo),move,move,'promotion',sep='\t')
