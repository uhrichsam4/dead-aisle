import bpy, os, mathutils

SRC='/Users/sam/Downloads/Workspace (1).glb'
DONOR='/Users/sam/Desktop/testtt/assets/hostile.glb'
OUT='/Users/sam/Desktop/testtt/assets/skin_suit.glb'
TARGET_TRIS=18000

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
# Clean the transferred weights:
#  - smooth removes isolated spikes where a vertex grabbed a distant bone
#  - glTF stores at most 4 joints per vertex; anything beyond that is dropped
#    silently at export, which tears the mesh exactly where it matters
bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
bpy.ops.object.vertex_group_smooth(group_select_mode='ALL', factor=.6, repeat=8, expand=0)
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
mx_inf=max((len(v.groups) for v in m.data.vertices), default=0)
print('CLEAN max influences/vert %d'%mx_inf)
weighted=sum(1 for v in m.data.vertices if len(v.groups)>0)
print('TRANSFER groups=%d  weighted verts %d / %d'%(len(m.vertex_groups), weighted, len(m.data.vertices)))

# ---- bind: object parent + armature modifier, no auto weights ----
if not USE_HEAT:
    m.parent=arm
    m.matrix_parent_inverse=arm.matrix_world.inverted()
    am=m.modifiers.new('Armature','ARMATURE'); am.object=arm
print('BIND via', 'BONE HEAT' if USE_HEAT else 'WEIGHT TRANSFER')
# drop the donor mesh now that its weights have been copied
for o in donor: bpy.data.objects.remove(o, do_unlink=True)

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
