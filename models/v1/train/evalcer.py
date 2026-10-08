import sys, glob, subprocess, os, re
tdir=sys.argv[1]; pref=sys.argv[2]   # каталог моделі, префікс рядків (напр. 003_1)
def lev(a,b):
    d=list(range(len(b)+1))
    for i,x in enumerate(a,1):
        p=d[:]; d[0]=i
        for j,y in enumerate(b,1):
            d[j]=min(p[j]+1,d[j-1]+1,p[j-1]+(x!=y))
    return d[-1]
tot=err=0; rows=[]
for f in sorted(glob.glob(f'gt/{pref}_*.png')):
    gt=open(f[:-4]+'.gt.txt',encoding='utf8').read().strip().replace('X','Х').replace('N','Н').replace('`',"'")
    r=subprocess.run(['tesseract',f,'-','-l','ukr','--psm','7','--tessdata-dir',tdir],capture_output=True,text=True)
    hyp=' '.join(r.stdout.split())
    norm=lambda s: re.sub(r'\s+','',s)
    e=lev(norm(hyp),norm(gt)); tot+=len(norm(gt)); err+=e; rows.append((e,gt,hyp))
print(f'{tdir}: CER {100*err/tot:.1f}% ({err}/{tot})')
if len(sys.argv)>3:
    for e,g,h in rows: print(e,'|',g,'|',h)
