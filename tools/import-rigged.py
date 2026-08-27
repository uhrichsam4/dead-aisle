#!/usr/bin/env python3
"""Bring an externally-rigged character into the game at a sane budget.

Decimate COLLAPSE preserves vertex groups, so a rigged mesh can be reduced
without losing its skinning - which is what makes this safe to do after the
rig rather than before.
"""
import bpy, os, sys, mathutils

SRC = os.environ.get('RIG_SRC', '/Users/sam/Downloads/rigged-model.glb')
OUT = os.environ.get('RIG_OUT', '/Users/sam/Desktop/testtt/assets/skin_suit.glb')
TARGET = int(os.environ.get('RIG_TRIS', '20000'))
TEXCAP = int(os.environ.get('RIG_TEXCAP', '512'))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

arm = next((o for o in bpy.data.objects if o.type == 'ARMATURE'), None)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
assert arm and meshes, 'expected an armature and a mesh'
print('BONES %d   CLIPS %s' % (len(arm.data.bones), [a.name for a in bpy.data.actions]))

for m in meshes:
    m.data.calc_loop_triangles()
n0 = sum(len(m.data.loop_triangles) for m in meshes)

for m in meshes:
    m.data.calc_loop_triangles()
    n = len(m.data.loop_triangles)
    if n <= TARGET: continue
    bpy.context.view_layer.objects.active = m
    d = m.modifiers.new('dec', 'DECIMATE')
    d.decimate_type = 'COLLAPSE'
    d.ratio = TARGET / float(n)
    d.use_collapse_triangulate = True
    # keep it ABOVE the armature modifier so skinning still applies after
    while m.modifiers.find('dec') > 0:
        bpy.ops.object.modifier_move_up(modifier='dec')
    bpy.ops.object.modifier_apply(modifier='dec')

n1 = 0
weighted = total = 0
for m in meshes:
    m.data.calc_loop_triangles(); n1 += len(m.data.loop_triangles)
    total += len(m.data.vertices)
    weighted += sum(1 for v in m.data.vertices if len(v.groups) > 0)
print('TRIS %d -> %d' % (n0, n1))
print('WEIGHTS kept on %d / %d verts' % (weighted, total))

# glTF stores at most four joints per vertex; the rest are dropped silently and
# that is what tears a mesh at the shoulders
for m in meshes:
    if not m.vertex_groups: continue      # eyes/props carry no weights
    bpy.ops.object.select_all(action='DESELECT')
    m.select_set(True)
    bpy.context.view_layer.objects.active = m
    bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)

# Deliberately NOT rescaled here. Scaling a mesh that is parented to an
# armature compounds through matrix_world in ways that are easy to get wrong
# (a first attempt turned a 2.30 m model into a 33 m one). The game already
# measures a rig and fits it at load - see skinMake - so leave the export at
# its authored size and let the runtime place it.
zs = [(m.matrix_world @ v.co).z for m in meshes for v in m.data.vertices]
print('HEIGHT %.2f m (fitted at runtime, not here)' % (max(zs) - min(zs)))

for im in bpy.data.images:
    if im.size[0] <= 0: continue
    w, h = im.size
    if max(w, h) <= TEXCAP: continue
    if w >= h: nw, nh = TEXCAP, max(1, int(h * TEXCAP / w))
    else:      nw, nh = max(1, int(w * TEXCAP / h)), TEXCAP
    try: im.scale(nw, nh)
    except Exception: pass

bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_apply=False,
    export_animations=True, export_skins=True, export_morph=False,
    export_image_format='JPEG', export_jpeg_quality=88,
    export_draco_mesh_compression_enable=False)
print('WROTE %s  %.2f MB' % (OUT, os.path.getsize(OUT) / 1e6))
