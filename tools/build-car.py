"""Turn the CGTrader Sonata OBJ into a game-ready GLB for DEAD AISLE.

The source is 255 loose groups with generic names, only ONE wheel, authored
Z-up but declaring Y-up, and an MTL whose texture paths point at the original
author's D:\\ drive. This does all of that:

  - reorients (-90 X) so the car stands up, front at +Z to match the existing
    CAR_FIT.ry = PI that the game already applies
  - scales to real size from the known 4.855 m Sonata length
  - clones and mirrors the single wheel into all four corners, named
    wheel_FL/FR/BL/BR - the names the game already binds to
  - splits out trunk_lid and the four doors with their ORIGINS ON THEIR HINGES,
    so opening one is a single rotation
  - joins the remainder into car_body
  - applies a black PBR set keyed off the MTL's material names
  - decimates to a game budget and exports GLB

env: CAR_TRIS (default 90000)
"""
import bpy, math, mathutils, os, sys

SRC   = '/tmp/sonata/Hyundai+Sonata+2016+-+Obj/Hyundai Sonata 2016 - Obj.obj'
OUT   = os.path.join(os.path.dirname(__file__), '..', 'assets', 'car2.glb')
TRIS  = int(os.environ.get('CAR_TRIS', '90000'))
SONATA_LEN = 4.855          # 2016 Sonata, metres

BOOT   = '74'
# Exported glTF has front at +Z and up at +Y; the game applies CAR_FIT.ry=PI,
# which makes model +X the car's LEFT. The OBJ's +x parts are therefore the
# left-hand doors.
DOORS  = {'27':'door_FL', '161':'door_FR', '104':'door_RL', '162':'door_RR'}
WHEEL  = ['259','261','257']          # tyre + rim + valve, front-right only

for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.wm.obj_import(filepath=SRC, use_split_groups=True, use_split_objects=True)
objs=[o for o in bpy.data.objects if o.type=='MESH']
print('imported %d parts' % len(objs))

# --- orient + scale ---------------------------------------------------------
# authored Z-up but the importer assumes Y-up; -90 about X stands it up and
# leaves the front at +Z, which is what CAR_FIT.ry=PI in the game expects
# Blender's up is Z and its exporter converts Z-up -> glTF Y-up on the way out.
# So the car has to STAND UP ALONG BLENDER +Z, not +Y. -90 about X does that:
# after it, x=width, y=length (+y = rear), z=up. On export that becomes
# gltf y=up and gltf z=-length, i.e. front at +Z - which is what the game's
# existing CAR_FIT.ry=PI expects.
R = mathutils.Matrix.Rotation(math.radians(-90), 4, 'X')
for o in objs: o.matrix_world = R @ o.matrix_world
bpy.context.view_layer.update()

def bounds(items):
    lo=[1e30]*3; hi=[-1e30]*3
    for o in items:
        for c in o.bound_box:
            w=o.matrix_world @ mathutils.Vector(c)
            for i in range(3): lo[i]=min(lo[i],w[i]); hi[i]=max(hi[i],w[i])
    return lo,hi
lo,hi = bounds(objs)
scale = SONATA_LEN/(hi[1]-lo[1])
print('scale %.5f  (was %.2f units long)' % (scale, hi[1]-lo[1]))
S = mathutils.Matrix.Scale(scale,4)
for o in objs: o.matrix_world = S @ o.matrix_world
bpy.context.view_layer.update()
lo,hi = bounds(objs)
# sit the wheels on y=0 and centre it on x / z
T = mathutils.Matrix.Translation(mathutils.Vector((
    -(lo[0]+hi[0])/2, -(lo[1]+hi[1])/2, -lo[2])))
for o in objs: o.matrix_world = T @ o.matrix_world
bpy.context.view_layer.update()
lo,hi = bounds(objs)
print('final bbox  x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f'
      % (lo[0],hi[0],lo[1],hi[1],lo[2],hi[2]))

def grab(sfx):
    for o in list(bpy.data.objects):
        if o.type=='MESH' and (o.name.endswith('_'+sfx) or ('_Sko_'+sfx) in o.name):
            return o
    return None

# --- black PBR set, keyed off the MTL names --------------------------------
LOOK={
 'carpaint'  : ((0.0115,0.0120,0.0130),0.80,0.13),
 'chrome'    : ((0.30,0.31,0.33),1.00,0.16),
 'chromedoor1':((0.26,0.27,0.29),1.00,0.20),
 'chromedoor2':((0.26,0.27,0.29),1.00,0.20),
 'mirror'    : ((0.40,0.41,0.43),1.00,0.10),
 'mattemetal': ((0.075,0.077,0.082),0.90,0.46),
 'clearglass': ((0.30,0.33,0.36),0.0,0.06),
 'windowglass':((0.045,0.055,0.065),0.0,0.10),
 'redglass'  : ((0.42,0.015,0.02),0.0,0.14),
 'orangeglass':((0.55,0.16,0.01),0.0,0.16),
 'plastic'   : ((0.030,0.030,0.032),0.0,0.62),
 'black'     : ((0.020,0.020,0.022),0.0,0.55),
 'black_intro':((0.026,0.026,0.028),0.0,0.50),
 'white'     : ((0.30,0.30,0.31),0.0,0.45),
 'gray'      : ((0.14,0.14,0.15),0.0,0.55),
 'red'       : ((0.35,0.02,0.02),0.0,0.40),
}
seen=set()
for o in bpy.data.objects:
    if o.type!='MESH': continue
    for m in o.data.materials:
        if not m or m in seen or not m.use_nodes: continue
        seen.add(m)
        b=m.node_tree.nodes.get('Principled BSDF')
        if not b: continue
        key=m.name.split('.')[0]
        spec=LOOK.get(key)
        if spec is None:
            low=key.lower()
            if low.startswith('interior'): spec=((0.030,0.029,0.028),0.0,0.68)
            elif low.startswith('wire_'):  spec=((0.09,0.09,0.10),0.0,0.60)
            else:                          spec=((0.07,0.07,0.075),0.0,0.60)
        c,met,rough=spec
        if not b.inputs['Base Color'].is_linked:
            b.inputs['Base Color'].default_value=(c[0],c[1],c[2],1)
        b.inputs['Metallic'].default_value=met
        b.inputs['Roughness'].default_value=rough
print('materials tuned: %d' % len(seen))

def join(items, name):
    items=[i for i in items if i]
    if not items: return None
    bpy.ops.object.select_all(action='DESELECT')
    for i in items: i.select_set(True)
    bpy.context.view_layer.objects.active = items[0]
    if len(items)>1: bpy.ops.object.join()
    ob=bpy.context.view_layer.objects.active
    ob.name=name
    return ob

def set_origin(ob, world_point):
    bpy.context.scene.cursor.location = world_point
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True); bpy.context.view_layer.objects.active=ob
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

# --- wheels: one exists, mirror it into four -------------------------------
wparts=[grab(s) for s in WHEEL]
wheel=join(wparts, 'wheel_src')
wl,wh = bounds([wheel])
wc = mathutils.Vector(((wl[0]+wh[0])/2,(wl[1]+wh[1])/2,(wl[2]+wh[2])/2))
print('wheel centre %.3f %.3f %.3f  dia %.3f' % (wc.x,wc.y,wc.z, wh[2]-wl[2]))
WB = 2.805                                  # Sonata wheelbase, metres
# in Blender space now: y is length with +y = rear, z is up. The source wheel
# is the front one; +x becomes the car's LEFT once the game applies ry=PI.
fy = -abs(wc.y); ry = fy + WB
targets = {'wheel_FL': ( abs(wc.x), fy, wc.z),
           'wheel_FR': (-abs(wc.x), fy, wc.z),
           'wheel_BL': ( abs(wc.x), ry, wc.z),
           'wheel_BR': (-abs(wc.x), ry, wc.z)}
# decimate the wheel ONCE, before cloning - otherwise four copies each carry
# the full tyre tread and the wheels alone outweigh the whole car
wt = sum(len(p.vertices)-2 for p in wheel.data.polygons)
if wt > 4200:
    m=wheel.modifiers.new('dw','DECIMATE'); m.decimate_type='COLLAPSE'
    m.ratio=4200.0/wt
    bpy.context.view_layer.objects.active=wheel
    bpy.ops.object.modifier_apply(modifier=m.name)
    print('wheel decimated %d -> %d tris' % (wt, sum(len(p.vertices)-2 for p in wheel.data.polygons)))
made=[]
for nm,(tx,ty,tz) in targets.items():
    d=wheel.copy(); d.data=wheel.data.copy(); bpy.context.scene.collection.objects.link(d)
    mirror = (tx<0)
    M = mathutils.Matrix.Translation(mathutils.Vector((tx,ty,tz))) @ \
        (mathutils.Matrix.Diagonal((-1,1,1,1)) if mirror else mathutils.Matrix.Identity(4)) @ \
        mathutils.Matrix.Translation(-wc)
    d.matrix_world = M @ d.matrix_world
    d.name=nm
    if mirror:
        bpy.ops.object.select_all(action='DESELECT'); d.select_set(True)
        bpy.context.view_layer.objects.active=d
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        d.data.flip_normals()
    set_origin(d, mathutils.Vector((tx,ty,tz)))
    made.append(d)
    print('  %s at %.3f %.3f %.3f%s' % (nm,tx,ty,tz,' (mirrored)' if mirror else ''))
bpy.data.objects.remove(wheel, do_unlink=True)

# --- boot lid + doors, origins on their hinges -----------------------------
movers=[]
boot=grab(BOOT)
if boot:
    boot.name='trunk_lid'
    bl,bh = bounds([boot])
    set_origin(boot, mathutils.Vector(((bl[0]+bh[0])/2, bl[1], bh[2]))) # front-top edge
    movers.append(boot)
    print('trunk_lid hinge y=%.3f z=%.3f' % (bl[1], bh[2]))
for sfx,nm in DOORS.items():
    d=grab(sfx)
    if not d: continue
    d.name=nm
    dl,dh = bounds([d])
    # a door hinges on a vertical axis at its FORWARD edge (front is +Z)
    set_origin(d, mathutils.Vector((dh[0] if dl[0]>0 else dl[0], dl[1], (dl[2]+dh[2])/2)))
    movers.append(d)
    print('%s hinge x=%.3f y=%.3f' % (nm, dh[0] if dl[0]>0 else dl[0], dl[1]))

# --- everything else becomes car_body --------------------------------------
keep={o.name for o in made+movers}
rest=[o for o in bpy.data.objects if o.type=='MESH' and o.name not in keep]
body=join(rest, 'car_body')
tris=lambda o: sum(len(p.vertices)-2 for p in o.data.polygons)
total=sum(tris(o) for o in bpy.data.objects if o.type=='MESH')
print('pre-decimate tris: %d' % total)
PANEL={'trunk_lid':4500,'door_FL':3000,'door_FR':3000,'door_RL':2400,'door_RR':2400}
for o in movers:
    t=tris(o); cap=PANEL.get(o.name)
    if cap and t>cap:
        m=o.modifiers.new('dp','DECIMATE'); m.decimate_type='COLLAPSE'; m.ratio=cap/float(t)
        bpy.context.view_layer.objects.active=o
        bpy.ops.object.modifier_apply(modifier=m.name)
        print('%s decimated %d -> %d' % (o.name, t, tris(o)))
bt=tris(body) if body else 0
budget=TRIS - sum(tris(o) for o in made) - sum(tris(o) for o in movers)
if body and bt>budget>0:
    m=body.modifiers.new('dec','DECIMATE'); m.decimate_type='COLLAPSE'
    m.ratio=max(.05, budget/float(bt))
    bpy.context.view_layer.objects.active=body
    bpy.ops.object.modifier_apply(modifier=m.name)
    print('body decimated %d -> %d tris' % (bt, tris(body)))
    total=sum(tris(o) for o in bpy.data.objects if o.type=='MESH')
print('final tris: %d' % total)
for o in bpy.data.objects:
    if o.type=='MESH': print('  %-12s %6d tris' % (o.name, tris(o)))

bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_apply=True,
    export_animations=False, export_skins=False, export_morph=False,
    export_image_format='JPEG', export_jpeg_quality=90,
    export_draco_mesh_compression_enable=False)
print('WROTE %s  %.2f MB' % (OUT, os.path.getsize(OUT)/1e6))
