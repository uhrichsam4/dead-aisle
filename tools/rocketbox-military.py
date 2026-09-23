# Military_Male_03 -> godot/assets/skin_military.glb: the enemy pipeline
# (build.py) plus a helmet GoPro lifted off operator.glb, Foot_L/Foot_R
# markers, a hand-keyed "reach" (a bend into the boot) for arrival.gd and the
# Rocketbox crouch_in / crouch / crouch_out and idle_look mocap
import bpy, sys, math
from mathutils import Matrix, Vector
sys.argv = [sys.argv[0], '--', '__none__']
S = '/private/tmp/claude-501/-Users-sam-Desktop-testtt/f33b73f6-0ced-49b8-9271-c4bc64f71fc2/scratchpad/rocketbox/'
g = {'__name__': 'rb'}
exec(open(S + 'build.py').read(), g)
g['OUT'] = '/Users/sam/Desktop/testtt/godot/assets/'
_orig = g['build_material']

def mil_material(mat, code, part):
    part = mat.name.split('_')[-1].split('.')[0]      # sm004_helmet -> helmet
    mat.use_nodes = True
    nt = mat.node_tree; nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(bsdf.outputs[0], out.inputs['Surface'])
    bsdf.inputs['Roughness'].default_value = 0.55 if part in ('helmet', 'pistol') else 0.85
    bsdf.inputs['Metallic'].default_value = 0.3 if part == 'pistol' else 0.0
    t = nt.nodes.new('ShaderNodeTexImage'); t.image = g['img'](S + f'tex/{code}_{part}_color.jpg')
    nt.links.new(t.outputs['Color'], bsdf.inputs['Base Color'])
    n = nt.nodes.new('ShaderNodeTexImage'); n.image = g['img'](S + f'tex/{code}_{part}_normal.jpg', True)
    nm = nt.nodes.new('ShaderNodeNormalMap')
    nt.links.new(n.outputs['Color'], nm.inputs['Color'])
    nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    mat.use_backface_culling = True
g['build_material'] = mil_material
g['COMBAT'] = []                                # the soldier gets no CMU clips
g['CLIPS'] = [
    ('idle', 'idle_neutral_01', False, True),
    ('idle_2', 'idle_neutral_02', False, True),
    ('idle_3', 'idle_neutral_03', False, True),
    ('idle_look', 'idle_look_around_01', False, True),
    ('idle_look_2', 'idle_look_around_02', False, True),
    ('idle_look_3', 'idle_look_around_03', False, True),
    ('walk', 'walk_neutral', True, True),
    ('walk_2', 'walk_neutral_01', True, True),
    ('walk_3', 'walk_neutral_02', True, True),
    ('run', 'run_neutral', True, True),
    ('run_2', 'run_neutral_01', True, True),
    ('run_3', 'run_slow_02', True, True),       # m_run_neutral_02 duplicates m_run_neutral
    ('crouch_in', 'crouch_in', True, False),     # the hips' 19 cm step back is spread over the clip
    ('crouch', 'crouch_idle', False, True),
    ('crouch_2', ('mirror', 'crouch'), False, True),
    ('crouch_3', 'f_crouch_idle', False, True),  # the only other crouch take
    ('crouch_out', 'crouch_out', True, False),
]

g['build']('skin_military', 'Military_Male_03', 'm', 'sm004')
g['write_speeds']('skin_military', g['SPEEDS']['skin_military'])

sc = bpy.context.scene
arm = bpy.data.objects['Armature']
body = next(o for o in bpy.data.objects if o.type == 'MESH')

def bone_world(name):
    return arm.matrix_world @ arm.data.bones[name].matrix_local

# --- feet markers, as operator.glb has them (arrival.gd plants the feet)
for side, bn in (('L', 'Bip01 L Foot'), ('R', 'Bip01 R Foot')):
    e = bpy.data.objects.new('Foot_' + side, None)
    sc.collection.objects.link(e)
    e.parent = arm; e.parent_type = 'BONE'; e.parent_bone = bn
    e.matrix_world = Matrix.Translation(bone_world(bn).translation)

# --- the helmet: its verts give the crown and the brow
helmet_i = next(i for i, m in enumerate(body.data.materials) if 'helmet' in m.name)
hv = [body.matrix_world @ body.data.vertices[v].co for p in body.data.polygons if p.material_index == helmet_i for v in p.vertices]
top = max(v.z for v in hv)
cx = sum(v.x for v in hv) / len(hv)
front = min(v.y for v in hv)            # faces -Y
print('HELMET top', round(top, 3), 'front', round(front, 3), 'cx', round(cx, 3))

# --- the GoPro, lifted off the operator with its mount
before = set(bpy.data.objects)
acts_before = set(bpy.data.actions)
bpy.ops.import_scene.gltf(filepath='/Users/sam/Desktop/testtt/godot/assets/operator.glb')
imported = [o for o in bpy.data.objects if o not in before]
for a in list(bpy.data.actions):
    if a not in acts_before:
        bpy.data.actions.remove(a)
cam = next(o for o in imported if o.name.startswith('action_camera'))
keep = [cam] + list(cam.children_recursive)
# the operator's head top, to carry the camera's seat over
op_meshes = [o for o in imported if o.type == 'MESH' and o not in keep]
dg = bpy.context.evaluated_depsgraph_get()
op_top = -1e9; op_front = 1e9
for o in op_meshes:
    ev = o.evaluated_get(dg)
    for v in ev.data.vertices:
        w = ev.matrix_world @ v.co
        if w.z > 1.5:
            op_top = max(op_top, w.z); op_front = min(op_front, w.y)
cw = cam.matrix_world.copy()
print('OP top', round(op_top, 3), 'front', round(op_front, 3), 'cam at', tuple(round(x, 3) for x in cw.translation))
mats = {o: o.matrix_world.copy() for o in keep}
for o in keep:
    o.parent = None
for o in keep:
    o.matrix_world = mats[o]
for o in imported:
    if o not in keep:
        bpy.data.objects.remove(o, do_unlink=True)
for o in keep:
    for c in list(o.users_collection):
        c.objects.unlink(o)
    sc.collection.objects.link(o)
# seat: same height below the crown and same set-back from the brow as on the operator
off = Vector((0, cw.translation.y - op_front, cw.translation.z - op_top))
seat = Vector((cx, front + off.y, top + off.z))
delta = Matrix.Translation(seat - cw.translation)
for o in keep:
    o.matrix_world = delta @ mats[o]
# re-parent the pieces under the camera root, then the root to the head bone
bpy.context.view_layer.update()
for o in keep[1:]:
    w = o.matrix_world.copy(); o.parent = cam; o.matrix_world = w
w = cam.matrix_world.copy()
cam.parent = arm; cam.parent_type = 'BONE'; cam.parent_bone = 'Bip01 Head'
cam.matrix_world = w
cam.name = 'action_camera'
print('CAM seat', tuple(round(x, 3) for x in seat), 'pieces', len(keep))

# --- "reach": the idle's first frame, bent at the waist and knees, arms out to the boot
idle = bpy.data.actions['idle']
arm.animation_data.action = idle
arm.animation_data.action_slot = idle.slots[0]
sc.frame_set(1)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
order = [pb for pb in arm.pose.bones]            # parents come first
snap = {pb.name: pb.matrix.copy() for pb in order}
arm.animation_data.action = None
for pb in order:
    pb.matrix = snap[pb.name]
    bpy.context.view_layer.update()

def bend(name, deg, axis='X'):
    pb = arm.pose.bones[name]
    M = pb.matrix.copy(); h = M.translation.copy()
    pb.matrix = Matrix.Translation(h) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-h) @ M
    bpy.context.view_layer.update()

root = arm.pose.bones['Bip01 Pelvis'] if 'Bip01 Pelvis' in arm.pose.bones else arm.pose.bones['Bip01']
for n, d in (('Bip01 L Thigh', -28), ('Bip01 R Thigh', -24), ('Bip01 L Calf', 46), ('Bip01 R Calf', 42),
             ('Bip01 L Foot', -18), ('Bip01 R Foot', -18),
             ('Bip01 Spine', 18), ('Bip01 Spine1', 14), ('Bip01 Spine2', 8), ('Bip01 Head', -14),
             ('Bip01 L UpperArm', -55), ('Bip01 R UpperArm', -55), ('Bip01 L Forearm', -20), ('Bip01 R Forearm', -20)):
    if n in arm.pose.bones:
        bend(n, d)
# drop the hips so the soles stay down after the knee bend
bpy.context.view_layer.update()
toe_z = min((arm.matrix_world @ arm.pose.bones[n].head).z for n in ('Bip01 L Toe0', 'Bip01 R Toe0'))
pb = arm.pose.bones['Bip01']
pb.matrix = Matrix.Translation((0, 0, 0.005 - toe_z)) @ pb.matrix
bpy.context.view_layer.update()
act = bpy.data.actions.new('reach')
arm.animation_data.action = act
for f in (1, 30):
    for pb in arm.pose.bones:
        pb.keyframe_insert('location', frame=f)
        pb.keyframe_insert('rotation_quaternion', frame=f)
act.use_fake_user = True
act.use_frame_range = True; act.frame_start, act.frame_end = 1, 30
act.use_cyclic = True
arm.animation_data.action = None
bpy.ops.object.mode_set(mode='OBJECT')
for pb in arm.pose.bones:
    pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.scale = (1, 1, 1)
print('ACTIONS', [(a.name, tuple(a.frame_range)) for a in bpy.data.actions])

bpy.ops.export_scene.gltf(
    filepath=g['OUT'] + 'skin_military.glb', export_format='GLB',
    export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True,
    export_anim_slide_to_zero=True, export_frame_range=False, export_def_bones=False,
    export_image_format='AUTO', export_image_quality=88, export_yup=True, export_skins=True,
    export_morph=False, export_apply=False, export_optimize_animation_size=True,
    export_reset_pose_bones=True)
bpy.ops.wm.save_as_mainfile(filepath=S + 'blend/skin_military.blend')
print('MIL DONE')
