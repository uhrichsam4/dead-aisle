#!/usr/bin/env python3
"""Downsample the textures inside a GLB, in place, without touching geometry.

The prop packs ship ~600 images at 512-1024px. Decoded to RGBA8 with mips that
is ~336 MB of GPU texture memory for set dressing that is a few dozen pixels
tall on screen. Re-exporting through Blender would work but risks perturbing
the meshes, so this rewrites the container directly: every bufferView is copied
across unchanged except the image ones, which are re-encoded smaller.
"""
import json, struct, sys, os, io
from PIL import Image

def load(p):
    d = open(p, 'rb').read()
    assert d[:4] == b'glTF', p
    n, js, bin_ = 12, None, b''
    while n < len(d):
        ln, ty = struct.unpack_from('<II', d, n); n += 8
        if ty == 0x4E4F534A: js = json.loads(d[n:n+ln])
        elif ty == 0x004E4942: bin_ = d[n:n+ln]
        n += ln
    return js, bin_

# glTF requires the JSON chunk padded with SPACES and the BIN chunk with zeros.
# Padding JSON with nulls produces a file whose JSON chunk will not parse
# ("Extra data") - which is exactly what the first run of this tool produced.
def pad_json(b): return b + b'\x20' * ((4 - len(b) % 4) % 4)
def pad_bin(b):  return b + b'\x00' * ((4 - len(b) % 4) % 4)

def shrink(path, cap, quality=85):
    js, bin_ = load(path)
    bvs = js.get('bufferViews', [])
    imgs = js.get('images', [])
    img_bv = {im['bufferView']: i for i, im in enumerate(imgs) if 'bufferView' in im}
    new_blobs = {}
    saved_px = 0
    for bvi, ii in img_bv.items():
        v = bvs[bvi]
        off, ln = v.get('byteOffset', 0), v['byteLength']
        raw = bin_[off:off+ln]
        try: im = Image.open(io.BytesIO(raw))
        except Exception: continue
        w, h = im.size
        if max(w, h) <= cap: continue
        sc = cap / float(max(w, h))
        nw, nh = max(1, int(w*sc)), max(1, int(h*sc))
        im = im.convert('RGBA' if im.mode in ('RGBA','LA','P') and 'A' in im.getbands() else 'RGB')
        im = im.resize((nw, nh), Image.LANCZOS)
        out = io.BytesIO()
        if im.mode == 'RGBA':
            im.save(out, 'PNG', optimize=True); mime = 'image/png'
        else:
            im.save(out, 'JPEG', quality=quality, optimize=True); mime = 'image/jpeg'
        new_blobs[bvi] = (out.getvalue(), mime)
        saved_px += (w*h - nw*nh)
        imgs[ii]['mimeType'] = mime
    if not new_blobs:
        print('%-20s no change' % os.path.basename(path)); return
    # rebuild the BIN with every view re-laid-out, so nothing is left dangling
    buf = bytearray(); 
    for i, v in enumerate(bvs):
        blob = new_blobs[i][0] if i in new_blobs else bin_[v.get('byteOffset',0): v.get('byteOffset',0)+v['byteLength']]
        while len(buf) % 4: buf.append(0)
        v['byteOffset'] = len(buf); v['byteLength'] = len(blob)
        buf += blob
    js['buffers'] = [{'byteLength': len(buf)}]
    jsb = pad_json(json.dumps(js, separators=(',', ':')).encode())
    binb = pad_bin(bytes(buf))
    out = (b'glTF' + struct.pack('<II', 2, 12 + 8 + len(jsb) + 8 + len(binb))
           + struct.pack('<II', len(jsb), 0x4E4F534A) + jsb
           + struct.pack('<II', len(binb), 0x004E4942) + binb)
    before = os.path.getsize(path)
    open(path, 'wb').write(out)
    print('%-20s %6.2f -> %6.2f MB   %d images shrunk, %.1f Mpx removed'
          % (os.path.basename(path), before/1e6, len(out)/1e6, len(new_blobs), saved_px/1e6))

if __name__ == '__main__':
    cap = int(sys.argv[1]); quality = int(sys.argv[2]) if len(sys.argv) > 2 else 85
    for p in sys.argv[3:]:
        shrink(p, cap, quality)
