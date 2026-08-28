"""Rig an unrigged OBJ against the Mixamo skeleton from a donor GLB.

The generator that produced the OBJ emits no skeleton - OBJ cannot carry one -
but it does emit a clean, symmetric T-pose, which is the best case for bone
heat. So: take the donor's armature and its animation set, fit it to the new
body, and bind. The donor MESH is discarded; only its skeleton and clips are
reused, and both rigs are Z-up so no reorientation is involved.

Alignment uses the donor mesh's BIND-pose bounds (raw vertex data, armature
modifier not evaluated) rather than the armature's bone extents: bones stop at
the wrist and the neck joint, so fitting to them would scale the new body by
whatever margin its skull and shoes happen to add.

env: OBJ_SRC OBJ_TEX RIG_DONOR RIG_OUT RIG_TRIS RIG_TEXCAP RIG_JPEGQ
"""
import bpy, mathutils, os, sys

SRC   = os.environ['OBJ_SRC']
TEX   = os.environ.get('OBJ_TEX','')
DONOR = os.environ['RIG_DONOR']
OUT   = os.environ['RIG_OUT']
TRIS  = int(os.environ.get('RIG_TRIS','80000'))
TEXCAP= int(os.environ.get('RIG_TEXCAP','2048'))
JPEGQ = int(os.environ.get('RIG_JPEGQ','94'))

for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)

# ---- donor: keep the armature and the 18 clips, drop its mesh -------------
bpy.ops.import_scene.gltf(filepath=DONOR)
arm = next(o for o in bpy.data.objects if o.type=='ARMATURE')
donor = max((o for o in bpy.data.objects if o.type=='MESH'),
            key=lambda o: len(o.data.vertices))
print('DONOR bones %d  clips %d  donorverts %d'
      % (len(arm.data.bones), len(bpy.data.actions), len(donor.data.vertices)))

def raw_bbox(o):
    """bind-pose bounds: mesh data as stored, no modifier evaluation"""
    mw = o.matrix_world
    lo = [ 1e30]*3; hi = [-1e30]*3
    for v in o.data.vertices:
        w = mw @ v.co
        for i in range(3):
            lo[i]=min(lo[i],w[i]); hi[i]=max(hi[i],w[i])
    return lo, hi
dlo, dhi = raw_bbox(donor)
print('DONOR bind bbox size', [round(dhi[i]-dlo[i],3) for i in range(3)])

# Which way is UP, with a sign. Bounding boxes are sign-blind, and this rig's
# object transform maps bone-space up onto world -Y, so matching extents alone
# imported the body head-down. Ask the skeleton instead.
_hips = arm.matrix_world @ arm.data.bones['mixamorigHips'].head_local
_head = arm.matrix_world @ arm.data.bones['mixamorigHead'].head_local
UPW = (_head - _hips).normalized()
print('RIG up vector', [round(v,3) for v in UPW])

def span_along(o, axis):
    mw = o.matrix_world
    lo, hi = 1e30, -1e30
    for v in o.data.vertices:
        d = (mw @ v.co).dot(axis)
        lo = min(lo, d); hi = max(hi, d)
    return lo, hi
DUL, DUH = span_along(donor, UPW)
DCEN = mathutils.Vector([(dlo[i]+dhi[i])/2 for i in range(3)])
print('DONOR height along up %.3f' % (DUH-DUL))

for o in [donor] + [x for x in bpy.data.objects if x.type=='MESH' and x is not donor]:
    bpy.data.objects.remove(o, do_unlink=True)

# ---- the new body --------------------------------------------------------
before = set(bpy.data.objects)
bpy.ops.wm.obj_import(filepath=SRC)
new = next(o for o in bpy.data.objects if o not in before and o.type=='MESH')
new.name = 'body'
print('NEW verts %d  polys %d' % (len(new.data.vertices), len(new.data.polygons)))

bpy.context.view_layer.objects.active = new
bpy.ops.object.select_all(action='DESELECT'); new.select_set(True)

# weld and clean before binding: bone heat solves over the surface, and split
# vertices or stray doubles are what make it fail on one bone and leave a limb
# unweighted
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=1e-5)
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode='OBJECT')

# The OBJ carries no vn lines at all, so Blender gives every face flat normals
# and the glTF exporter then splits every single vertex - 240k verts for 80k
# triangles, three per face with nothing shared, which is what made the first
# export 14 MB. Smooth shading lets them weld back down.
try: bpy.ops.mesh.customdata_custom_splitnormals_clear()
except Exception: pass
bpy.ops.object.shade_smooth()
print('after weld: verts %d' % len(new.data.vertices))

# decimate before binding, not after: fewer, better-shaped faces for the heat
# solve, and the weights then come out already at the shipping resolution
tris = sum(len(p.vertices)-2 for p in new.data.polygons)
if tris > TRIS:
    m = new.modifiers.new('dec','DECIMATE'); m.decimate_type='COLLAPSE'
    m.ratio = TRIS/float(tris)
    bpy.ops.object.modifier_apply(modifier=m.name)
    tris = sum(len(p.vertices)-2 for p in new.data.polygons)
print('after decimate: tris %d' % tris)

# ---- fit the new body onto the donor's bind bounds -----------------------
# Align the body's own up axis onto the rig's up VECTOR, then match height and
# stand it on the rig's feet. Working from a direction rather than from bbox
# extents keeps this correct whichever way round the next donor is authored.
import math
def xform(M):
    new.matrix_world = M @ new.matrix_world
    bpy.context.view_layer.update()

nlo, nhi = raw_bbox(new)
nsz = [nhi[i]-nlo[i] for i in range(3)]
nup = nsz.index(max(nsz))
# Blender's OBJ importer lands these Y-up sources as Z-up with the head at +Z
nupv = mathutils.Vector((1 if nup==0 else 0, 1 if nup==1 else 0, 1 if nup==2 else 0))
xform(nupv.rotation_difference(UPW).to_matrix().to_4x4())
print('ROT %s -> %s' % ([round(v,2) for v in nupv], [round(v,2) for v in UPW]))

nul, nuh = span_along(new, UPW)
s_ = (DUH-DUL)/max(nuh-nul, 1e-9)
xform(mathutils.Matrix.Scale(s_, 4))

nul, nuh = span_along(new, UPW)
nlo, nhi = raw_bbox(new)
ncen = mathutils.Vector([(nlo[i]+nhi[i])/2 for i in range(3)])
t = (DCEN - ncen)                       # centre up laterally...
t -= UPW * t.dot(UPW)                   # ...but not along up
t += UPW * (DUL - nul)                  # then stand it on the rig's feet
xform(mathutils.Matrix.Translation(t))

nul, nuh = span_along(new, UPW)
nlo, nhi = raw_bbox(new)
print('FIT scale %.4f  height %.3f (donor %.3f)  size %s'
      % (s_, nuh-nul, DUH-DUL, [round(nhi[i]-nlo[i],3) for i in range(3)]))

# glTF ignores the node transform of a SKINNED mesh - the mesh is placed
# entirely by the joints and inverse bind matrices. Blender's own importer
# reapplies it, so a round trip there looks right while three.js drops it and
# lays the body flat on the floor. Bake the fit into the vertices instead.
bpy.ops.object.select_all(action='DESELECT')
new.select_set(True); bpy.context.view_layer.objects.active = new
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
print('APPLIED transform; matrix is identity: %s'
      % all(abs(new.matrix_world[i][j]-(1.0 if i==j else 0.0))<1e-6
            for i in range(4) for j in range(4)))

# ---- bind ----------------------------------------------------------------
# bone heat binds against the armature's CURRENT pose; the glTF importer leaves
# it on frame 1 of the first action, so force rest before parenting or the
# first clip's pose is baked into the bind
for a in bpy.data.actions: a.use_fake_user = True     # survive the clear below
arm.animation_data_clear()
for pb in arm.pose.bones: pb.matrix_basis.identity()
arm.data.pose_position = 'REST'
bpy.context.view_layer.update()

bpy.ops.object.select_all(action='DESELECT')
new.select_set(True); arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
arm.data.pose_position = 'POSE'

wv = sum(1 for v in new.data.vertices if len(v.groups))
print('BIND weighted %d / %d verts across %d groups'
      % (wv, len(new.data.vertices), len(new.vertex_groups)))

# glTF allows 4 joints per vertex and silently drops the rest
bpy.context.view_layer.objects.active = new
bpy.ops.object.select_all(action='DESELECT'); new.select_set(True)
bpy.ops.object.vertex_group_limit_total(limit=4)
bpy.ops.object.vertex_group_normalize_all(lock_active=False)

# ---- put the clips back --------------------------------------------------
# animation_data_clear() above was needed to get the rig to rest for the heat
# solve, but it also unlinks every action, and the exporter then writes a GLB
# with zero animations. Re-link each one as its own NLA track.
arm.animation_data_create()
for tr in list(arm.animation_data.nla_tracks):
    arm.animation_data.nla_tracks.remove(tr)
for a in bpy.data.actions:
    tr = arm.animation_data.nla_tracks.new(); tr.name = a.name
    tr.strips.new(a.name, int(a.frame_range[0]), a)
print('RELINKED %d clips' % len(arm.animation_data.nla_tracks))

# ---- material ------------------------------------------------------------
if TEX and os.path.exists(TEX):
    img = bpy.data.images.load(TEX)
    if max(img.size) > TEXCAP:
        w,h = img.size
        if w>=h: img.scale(TEXCAP, max(1,int(h*TEXCAP/w)))
        else:    img.scale(max(1,int(w*TEXCAP/h)), TEXCAP)
    mat = bpy.data.materials.new('body'); mat.use_nodes=True
    bsdf = mat.node_tree.nodes['Principled BSDF']
    tn = mat.node_tree.nodes.new('ShaderNodeTexImage'); tn.image = img
    mat.node_tree.links.new(bsdf.inputs['Base Color'], tn.outputs['Color'])
    bsdf.inputs['Roughness'].default_value = 0.62
    bsdf.inputs['Metallic'].default_value = 0.0
    new.data.materials.clear(); new.data.materials.append(mat)
    print('TEX %s -> %s' % (os.path.basename(TEX), tuple(img.size)))

bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_apply=False,
    export_animations=True, export_skins=True, export_morph=False,
    export_image_format='JPEG', export_jpeg_quality=JPEGQ,
    export_draco_mesh_compression_enable=False)
print('WROTE %s  %.2f MB' % (OUT, os.path.getsize(OUT)/1e6))
