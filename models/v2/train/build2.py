import cv2, numpy as np, glob, os, sys, random, subprocess, shutil
from concurrent.futures import ThreadPoolExecutor
out, naug = sys.argv[1], int(sys.argv[2]); files = open(sys.argv[3]).read().split()
random.seed(7); np.random.seed(7)
shutil.rmtree(out, ignore_errors=True); os.makedirs(out)
def clean(im):
    # прибрати шматки сусідніх рядків, що торкаються верху/низу
    inv=(im<128).astype(np.uint8)
    n,lab,st,_=cv2.connectedComponentsWithStats(inv,8)
    h=im.shape[0]; res=im.copy()
    for i in range(1,n):
        x,y,w,hh,a=st[i]
        if (y<=1 or y+hh>=h-1) and hh<0.45*h: res[lab==i]=255
    return res
def aug(im):
    g=im.copy()
    s=random.uniform(0.75,1.3); g=cv2.resize(g,None,fx=s,fy=s*random.uniform(0.92,1.08),interpolation=cv2.INTER_AREA if s<1 else cv2.INTER_CUBIC)
    g=cv2.copyMakeBorder(g,12,12,14,14,cv2.BORDER_CONSTANT,value=255)
    h,w=g.shape; ang=random.uniform(-1.2,1.2); sh=random.uniform(-0.06,0.06)
    M=np.float32([[1,sh,0],[ang*0.01745,1,0]]); M[1,0]=np.tan(ang*0.01745)
    g=cv2.warpAffine(g,M,(w,h),borderValue=255)
    if random.random()<0.6: g=cv2.GaussianBlur(g,(0,0),random.uniform(0.5,1.3))
    k=random.random()
    if k<0.25: g=cv2.erode(g,np.ones((2,2),np.uint8))
    elif k<0.45: g=cv2.dilate(g,np.ones((2,2),np.uint8))
    g=g.astype(np.float32); g=g*random.uniform(0.85,1.0)+random.uniform(0,35)
    g+=np.random.normal(0,random.uniform(0,10),g.shape)
    return np.clip(g,0,255).astype(np.uint8)
CH=set()
for l in open('td2/ukr/ukr.unicharset',encoding='utf8').read().split('\n')[1:]:
    p=l.split(' ')
    if p and p[0]: CH.add(p[0])
jobs=[]
LAT=str.maketrans('ABCEHKMOPTXaceopxyiI`','АВСЕНКМОРТХасеорхуіІ\'')
skipped=0
for f in files:
        gt=open(f[:-4]+'.gt.txt',encoding='utf8').read().strip()
        gt=gt.replace('N','Н').translate(LAT)  # латинські двійники -> кириличні (у моделі ukr латиниці нема)
        if any(c not in CH for c in gt if c!=' '): skipped+=1
        if any(c not in CH for c in gt if c!=' '): continue
        base=clean(cv2.imread(f,0))
        for k in range(naug):
            n=f'{out}/{os.path.basename(f)[:-4]}_a{k:02d}'
            im=base if k==0 else aug(base)
            cv2.imwrite(n+'.png',im); open(n+'.gt.txt','w',encoding='utf8').write(gt)
            h,w=im.shape
            with open(n+'.box','w',encoding='utf8') as b:
                for c in gt: b.write(f'{c} 0 0 {w} {h} 0\n')
                b.write(f'\t 0 0 {w} {h} 0\n')
            jobs.append(n)
def mk(n):
    r=subprocess.run(['tesseract',n+'.png',n,'--psm','13','-l','ukr','lstm.train'],capture_output=True,text=True,env=dict(os.environ))
    return n if os.path.exists(n+'.lstmf') else (print('FAIL',n,r.stderr[-200:]) or None)
with ThreadPoolExecutor(2) as ex: ok=[x for x in ex.map(mk,jobs) if x]
open(f'{out}/list.txt','w').write('\n'.join(x+'.lstmf' for x in ok)+'\n')
print(len(jobs),'->',len(ok),'skipped(non-ukr chars)',skipped)
