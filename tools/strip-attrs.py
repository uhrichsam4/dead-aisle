#!/usr/bin/env python3
"""Drop vertex attributes three.js never reads, and rebuild the GLB.

car.glb ships COLOR_1/COLOR_2 that nothing samples - about 1 MB on the wire and
the same again in VRAM. TEXCOORD_1 is only read for aoMap/lightMap; if no
material references one, it is dead weight too.
"""
import json, struct, sys, os
KEEP_ALWAYS = {'POSITION','NORMAL','TANGENT','TEXCOORD_0','JOINTS_0','WEIGHTS_0','COLOR_0'}

def load(p):
    d=open(p,'rb').read(); n=12; js=None; bin_=b''
    while n<len(d):
        ln,ty=struct.unpack_from('<II',d,n); n+=8
        if ty==0x4E4F534A: js=json.loads(d[n:n+ln])
        elif ty==0x004E4942: bin_=d[n:n+ln]
        n+=ln
    return js,bin_

def run(path):
    js,bin_=load(path)
    uses_uv1=False
    for m in js.get('materials',[]):
        for slot in ('occlusionTexture','emissiveTexture'):
            t=m.get(slot)
            if isinstance(t,dict) and t.get('texCoord',0)==1: uses_uv1=True
    keep=set(KEEP_ALWAYS)
    if uses_uv1: keep.add('TEXCOORD_1')
    dropped=set(); used=set()
    for me in js.get('meshes',[]):
        for pr in me['primitives']:
            for a in list(pr['attributes'].keys()):
                if a not in keep and not a.startswith('_'):
                    dropped.add(a); del pr['attributes'][a]
    for me in js.get('meshes',[]):
        for pr in me['primitives']:
            used.update(pr['attributes'].values())
            if 'indices' in pr: used.add(pr['indices'])
    for sk in js.get('skins',[]):
        if 'inverseBindMatrices' in sk: used.add(sk['inverseBindMatrices'])
    for an in js.get('animations',[]):
        for sm in an.get('samplers',[]): used.update([sm['input'],sm['output']])
    keepbv={js['accessors'][i]['bufferView'] for i in used if 'bufferView' in js['accessors'][i]}
    for im in js.get('images',[]):
        if 'bufferView' in im: keepbv.add(im['bufferView'])
    bvs=js['bufferViews']; buf=bytearray(); remap={}
    for i,v in enumerate(bvs):
        if i not in keepbv: continue
        blob=bin_[v.get('byteOffset',0): v.get('byteOffset',0)+v['byteLength']]
        while len(buf)%4: buf.append(0)
        remap[i]=len(buf); v['byteOffset']=len(buf); buf+=blob
    newbv=[]; idxmap={}
    for i,v in enumerate(bvs):
        if i in remap: idxmap[i]=len(newbv); newbv.append(v)
    js['bufferViews']=newbv
    for a in js['accessors']:
        if 'bufferView' in a and a['bufferView'] in idxmap: a['bufferView']=idxmap[a['bufferView']]
    for im in js.get('images',[]):
        if 'bufferView' in im and im['bufferView'] in idxmap: im['bufferView']=idxmap[im['bufferView']]
    js['buffers']=[{'byteLength':len(buf)}]
    jsb=json.dumps(js,separators=(',',':')).encode(); jsb+=b'\x20'*((4-len(jsb)%4)%4)
    binb=bytes(buf); binb+=b'\x00'*((4-len(binb)%4)%4)
    out=(b'glTF'+struct.pack('<II',2,12+8+len(jsb)+8+len(binb))
         +struct.pack('<II',len(jsb),0x4E4F534A)+jsb
         +struct.pack('<II',len(binb),0x004E4942)+binb)
    before=os.path.getsize(path)
    if len(out)>=before:
        print('%-20s no gain'%os.path.basename(path)); return
    open(path,'wb').write(out)
    print('%-20s %6.2f -> %6.2f MB   dropped: %s'%(os.path.basename(path),before/1e6,len(out)/1e6,
          ', '.join(sorted(dropped)) or 'unused bufferViews'))

for p in sys.argv[1:]: run(p)
