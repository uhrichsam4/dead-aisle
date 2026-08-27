import bpy, os, mathutils

SRC='/Users/sam/Downloads/Workspace (1).glb'
DONOR='/Users/sam/Desktop/testtt/assets/hostile.glb'
OUT='/Users/sam/Desktop/testtt/assets/skin_suit.glb'
TARGET_TRIS=int(os.environ.get('RIG_TRIS','18000'))

bpy.ops.wm.read_factory_settings(use_empty=True)

# ---- donor: keep BOTH the armature and its skinned mesh (the weight source) ----
bpy.ops.import_scene.gltf(filepath=DONOR)
arm=next((o for o in bpy.data.objects if o.type=='ARMATURE'), None)
assert arm, 'no armature in donor'
donor=[o for o in bpy.data.objects if o.type=='MESH']
assert donor, 'no skinned mesh in donor'
# Join every donor submesh into one weight source. Using only the largest one
# left the arms poorly covered - whichever submesh carries the sleeves was not
# in the source, so shoulder vertices had nothing sensible to sample and tore.
for o in donor: o.data.calc_loop_triangles()
bpy.ops.object.select_all(action='DESELECT')
for o in donor: o.select_set(True)
big=max(donor, key=lambda o: len(o.data.loop_triangles))
bpy.context.view_layer.objects.active=big
try: bpy.ops.object.make_single_user(object=True, obdata=True)
except Exception: pass
if len(donor)>1: bpy.ops.object.join()
dsrc=bpy.context.view_layer.objects.active
donor=[dsrc]
dsrc.data.calc_loop_triangles()
def zspan(objs):
    zs=[(o.matrix_world @ v.co).z for o in objs for v in o.data.vertices]
    return min(zs), max(zs)
dz0,dz1=zspan(donor); dh=dz1-dz0
dxs=[(o.matrix_world @ v.co).x for o in donor for v in o.data.vertices]
print('DONOR mesh height %.3f  arm span %.3f  bones %d  weight-src %s'%(
      dh, max(dxs)-min(dxs), len(arm.data.bones), dsrc.name))

# ---- the new mesh ----
before=set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=SRC)
new=[o for o in bpy.data.objects if o not in before and o.type=='MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in new: o.select_set(True)
bpy.context.view_layer.objects.active=new[0]
try: bpy.ops.object.make_single_user(object=True, obdata=True)
except Exception: pass
if len(new)>1: bpy.ops.object.join()
m=bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
m.data.calc_loop_triangles(); n0=len(m.data.loop_triangles)
if n0>TARGET_TRIS:
    d=m.modifiers.new('dec','DECIMATE'); d.decimate_type='COLLAPSE'
    d.ratio=TARGET_TRIS/float(n0); d.use_collapse_triangulate=True
    bpy.ops.object.modifier_apply(modifier=d.name)
m.data.calc_loop_triangles()
print('MESH tris %d -> %d'%(n0,len(m.data.loop_triangles)))

# ---- align to the donor BODY, not to the skeleton's padded bounds ----
# Uniform-by-height left his arms 24% wider than the donor's, so shoulder
# vertices sat outside the source silhouette and picked up weights from the
# neck and chest - which is what shredded them. Fit height in Z and arm span
# in X (and Y with X, so he is not flattened) so every limb overlaps its
# counterpart before the transfer runs.
mz0,mz1=zspan([m]); mh=mz1-mz0
mxs0=[(m.matrix_world @ v.co).x for v in m.data.vertices]
msp=max(mxs0)-min(mxs0)
sz=dh/mh
sx=(max(dxs)-min(dxs))/msp
m.scale=(sx,sx,sz); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
mz0,mz1=zspan([m])
mxs=[(m.matrix_world @ v.co).x for v in m.data.vertices]
mys=[(m.matrix_world @ v.co).y for v in m.data.vertices]
dys=[(o.matrix_world @ v.co).y for o in donor for v in o.data.vertices]
m.location=(-(min(mxs)+max(mxs))/2 + (min(dxs)+max(dxs))/2,
            -(min(mys)+max(mys))/2 + (min(dys)+max(dys))/2,
            -mz0 + dz0)
bpy.ops.object.transform_apply(location=True,rotation=False,scale=False)
mz0,mz1=zspan([m]); mxs=[(m.matrix_world @ v.co).x for v in m.data.vertices]
print('ALIGNED height %.3f (donor %.3f)  arm span %.3f'%(mz1-mz0, dh, max(mxs)-min(mxs)))

# ---- reset the rig to its REST pose before binding --------------------------
# The glTF importer assigns the first action ('attack') and leaves the armature
# on frame 1, so all 36 bones sit OFF rest. parent_set(ARMATURE_AUTO) computes
# weights from the bones' CURRENT positions, which baked that attack pose in as
# the bind pose. Idle then looked nearly right (it is close to that pose) while
# run - the furthest from it - tore into flying shards. This is the actual
# cause of the "cuts"; the weight tweaks below only ever nibbled at it.
import mathutils as _mu
_off = sum(1 for pb in arm.pose.bones if pb.matrix_basis != _mu.Matrix())
if arm.animation_data: arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.matrix_basis.identity()
    pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0)
    pb.rotation_euler = (0, 0, 0); pb.scale = (1, 1, 1)
arm.data.pose_position = 'REST'
bpy.context.view_layer.update()
print('BINDPOSE reset: %d/%d bones were off rest' % (_off, len(arm.pose.bones)))

# ---- bind ----
# Try bone heat FIRST now that the mesh is correctly sized. The original
# attempt fed it a mesh scaled to 2.822 m - the donor's padded bounds, not its
# 1.842 m body - so the bones sat nowhere near the geometry and the solver
# produced nothing. Heat handles limbs far better than proximity transfer,
# which jumps the armpit gap and shreds shoulders.
bpy.ops.object.select_all(action='DESELECT')
m.select_set(True); arm.select_set(True)
bpy.context.view_layer.objects.active=arm
heat=0
try:
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    heat=sum(1 for v in m.data.vertices if len(v.groups)>0)
except Exception as e:
    print('HEAT raised:', e)
print('HEAT weighted verts %d / %d'%(heat, len(m.data.vertices)))
USE_HEAT = heat > len(m.data.vertices)*0.9

# ---- fallback: transfer the donor's vertex weights by proximity ----
bpy.ops.object.select_all(action='DESELECT')
m.select_set(True); dsrc.select_set(True)
bpy.context.view_layer.objects.active=m
dt=None if USE_HEAT else m.modifiers.new('xfer','DATA_TRANSFER')
if dt is not None:
    dt.object=dsrc
    dt.use_vert_data=True
    dt.data_types_verts={'VGROUP_WEIGHTS'}
    dt.vert_mapping='POLYINTERP_NEAREST'
    dt.layers_vgroup_select_src='ALL'
    dt.layers_vgroup_select_dst='NAME'
    bpy.ops.object.datalayout_transfer(modifier=dt.name)     # create matching groups
    bpy.ops.object.modifier_apply(modifier=dt.name)
# ---------------------------------------------------------------------------
# Weight cleanup. The order here matters and the previous version had it wrong:
# it smoothed FIRST and then stamped hard-edged head/torso regions on top, so
# the seams those regions created were never blended out.
#
# The symptom to beat is the mesh CUTTING rather than stretching. A surface
# tears when two vertices that share an edge are driven by different bones, so
# every pass below is graded rather than binary, and the weld step at the end
# fixes the single biggest cause.
# ---------------------------------------------------------------------------

def vw(v):
    """current {group_index: weight} for a vertex"""
    return {g.group: g.weight for g in v.groups}

def setw(idx, gi, w):
    m.vertex_groups[gi].add([idx], max(0.0, min(1.0, w)), 'REPLACE')

# --- 1. head: graded, not binary -------------------------------------------
# The skull and hair are effectively rigid, but heat hands them a share of
# neck01..neck03 and even spine05, and the neck chain swings hard in run and
# attack. Ramp the head bone in over a band instead of switching at one plane,
# or the ramp itself becomes the tear.
head_b = arm.data.bones.get('head')
if head_b:
    head_z = (arm.matrix_world @ head_b.head_local).z
    hg = m.vertex_groups.get('head') or m.vertex_groups.new(name='head')
    lo, hi = head_z - 0.10, head_z + 0.04          # blend band across the neck
    n_head = 0
    for v in m.data.vertices:
        z = (m.matrix_world @ v.co).z
        if z < lo: continue
        t = 1.0 if z >= hi else (z - lo) / max(1e-6, hi - lo)
        t = t * t * (3 - 2 * t)                    # smoothstep
        cur = vw(v)
        for gi, w in cur.items():
            if m.vertex_groups[gi].name != 'head':
                setw(v.index, gi, w * (1.0 - t))
        setw(v.index, hg.index, cur.get(hg.index, 0.0) * (1.0 - t) + t)
        n_head += 1
    print('HEAD graded over %d verts, band %.3f..%.3f' % (n_head, lo, hi))

# --- 2. torso vs arm chain: graded falloff ---------------------------------
# A suit jacket is a LOOSE garment, so its back and chest sit well outside the
# donor's bare torso and heat gives them clavicle/shoulder/upperarm weight.
# Removing that outright (what this used to do) just moved the tear to the
# boundary; scale it down with distance from the centreline instead.
ARM_RE = ('clavicle', 'shoulder', 'upperarm', 'lowerarm', 'wrist')
arm_idx = {g.index for g in m.vertex_groups if any(k in g.name.lower() for k in ARM_RE)}
if arm_idx:
    pelvis_b = arm.data.bones.get('spine05') or arm.data.bones.get('spine04')
    neck_b   = arm.data.bones.get('neck01')
    z_lo = (arm.matrix_world @ pelvis_b.head_local).z if pelvis_b else -1e9
    z_hi = (arm.matrix_world @ neck_b.head_local).z   if neck_b   else  1e9
    n_torso = 0
    for v in m.data.vertices:
        w = m.matrix_world @ v.co
        if not (z_lo - 0.10 <= w.z <= z_hi + 0.02): continue
        ax = abs(w.x)
        if ax >= 0.22: continue                    # genuinely out on the arm
        k = 0.0 if ax <= 0.10 else (ax - 0.10) / 0.12
        k = k * k * (3 - 2 * k)                    # 0 at the spine, 1 by the shoulder
        cur = vw(v)
        touched = False
        for gi, wt in cur.items():
            if gi in arm_idx and wt > 0:
                setw(v.index, gi, wt * k); touched = True
        if touched: n_torso += 1
    print('TORSO damped arm weight on %d verts (z %.2f..%.2f)' % (n_torso, z_lo, z_hi))

# --- 3. smooth AFTER the region work, so its seams get blended -------------
bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
SM_F = float(os.environ.get('RIG_SMOOTH_F', '0.65'))
SM_R = int(os.environ.get('RIG_SMOOTH_R', '10'))
bpy.ops.object.vertex_group_smooth(group_select_mode='ALL', factor=SM_F, repeat=SM_R, expand=0)
print('SMOOTH factor=%.2f repeat=%d' % (SM_F, SM_R))
bpy.ops.object.mode_set(mode='OBJECT')

# --- 4. weld coincident vertices — the actual cause of the CUTS ------------
# A game mesh is split at every UV and material seam: two vertices sit at the
# same point in space but are separate in the mesh. Heat weights each of them
# independently, so along a seam the two copies get pulled by different bones
# and the surface rips open into flat shards - exactly the "cuts" rather than
# stretching. Average the weights across every coincident cluster so the
# copies can only ever move together.
from collections import defaultdict
buckets = defaultdict(list)
for v in m.data.vertices:
    buckets[(round(v.co.x, 5), round(v.co.y, 5), round(v.co.z, 5))].append(v.index)
seams = [ix for ix in buckets.values() if len(ix) > 1]
for ix in seams:
    acc = defaultdict(float)
    for i in ix:
        for g in m.data.vertices[i].groups: acc[g.group] += g.weight
    n = float(len(ix))
    for gi, tot in acc.items():
        avg = tot / n
        for i in ix: setw(i, gi, avg)
print('WELD %d seam clusters covering %d verts' % (len(seams), sum(len(i) for i in seams)))

# --- 5. glTF ships at most 4 joints per vertex; the rest are dropped -------
bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)

# --- 6. prove the weld survived the limit pass ----------------------------
bad = 0
for ix in seams:
    ref = None
    for i in ix:
        cur = {g.group: round(g.weight, 4) for g in m.data.vertices[i].groups}
        if ref is None: ref = cur
        elif cur != ref: bad += 1; break
print('SEAMS still divergent after limit+normalize: %d / %d' % (bad, len(seams)))
mx_inf = max((len(v.groups) for v in m.data.vertices), default=0)
print('CLEAN max influences/vert %d' % mx_inf)
weighted=sum(1 for v in m.data.vertices if len(v.groups)>0)
print('TRANSFER groups=%d  weighted verts %d / %d'%(len(m.vertex_groups), weighted, len(m.data.vertices)))

# ---- bind: object parent + armature modifier, no auto weights ----
if not USE_HEAT:
    m.parent=arm
    m.matrix_parent_inverse=arm.matrix_world.inverted()
    am=m.modifiers.new('Armature','ARMATURE'); am.object=arm
arm.data.pose_position = 'POSE'      # clips must drive the rig again 
bpy.context.view_layer.update()
print('BIND via', 'BONE HEAT' if USE_HEAT else 'WEIGHT TRANSFER')
# drop the donor mesh now that its weights have been copied
for o in donor: bpy.data.objects.remove(o, do_unlink=True)

# ---- QC: how badly does the surface tear? --------------------------------
# The eye can be fooled by a render angle, so measure it. For every clip, pose
# the rig and compare each edge's length against its rest length. An edge that
# grows many times over is the surface ripping open rather than stretching -
# which is exactly the artefact to drive to zero.
def tear_report():
    dgraph = bpy.context.evaluated_depsgraph_get()
    rest = m.data.vertices
    worst_overall = 0.0
    total_bad = 0
    for a in bpy.data.actions:
        if not arm.animation_data: arm.animation_data_create()
        arm.animation_data.action = a
        f0, f1 = (int(x) for x in a.frame_range)
        bad = 0; worst = 0.0
        for fr in range(f0, f1 + 1, max(1, (f1 - f0) // 6 or 1)):
            bpy.context.scene.frame_set(fr)
            bpy.context.view_layer.update()
            dgraph = bpy.context.evaluated_depsgraph_get()
            ev = m.evaluated_get(dgraph).to_mesh()
            for e in m.data.edges:
                i, j = e.vertices
                l0 = (rest[i].co - rest[j].co).length
                if l0 < 1e-6: continue
                r = (ev.vertices[i].co - ev.vertices[j].co).length / l0
                if r > 3.0: bad += 1
                if r > worst: worst = r
        print('  QC %-8s torn edges %5d   worst %6.1fx' % (a.name, bad, worst))
        total_bad += bad; worst_overall = max(worst_overall, worst)
    print('QC TOTAL torn %d   worst %.1fx   (of %d edges)' % (total_bad, worst_overall, len(m.data.edges)))
    arm.animation_data.action = None
    bpy.context.scene.frame_set(1)
tear_report()

for im in bpy.data.images:
    if im.size[0]<=0: continue
    w,h=im.size[0],im.size[1]
    if max(w,h)<=512: continue
    if w>=h: nw,nh=512,max(1,int(h*512/w))
    else:    nw,nh=max(1,int(w*512/h)),512
    try: im.scale(nw,nh)
    except Exception: pass

bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_apply=False,
    export_animations=True, export_skins=True, export_morph=False,
    export_image_format='JPEG', export_jpeg_quality=85,
    export_draco_mesh_compression_enable=False)
print('WROTE', OUT)
