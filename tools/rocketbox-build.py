import bpy, sys, os, math
from mathutils import Matrix, Vector
from bpy_extras.anim_utils import action_get_channelbag_for_slot

S = '/private/tmp/claude-501/-Users-sam-Desktop-testtt/f33b73f6-0ced-49b8-9271-c4bc64f71fc2/scratchpad/rocketbox/'
OUT = '/Users/sam/Desktop/testtt/godot/assets/enemies/'
AVATARS = [
    ('enemy_01', 'Male_Adult_04', 'm', 'm006'),
    ('enemy_02', 'Male_Adult_12', 'm', 'm007'),
    ('enemy_03', 'Male_Adult_18', 'm', 'm023'),
    ('enemy_04', 'Male_Adult_17', 'm', 'm022'),
    ('enemy_05', 'Female_Party_02', 'f', 'f022'),
    ('enemy_06', 'Business_Female_01', 'f', 'f014'),
]
CLIPS = [('idle', 'idle_neutral_01', False), ('walk', 'walk_neutral', True), ('run', 'run_neutral', True)]

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
only = set(argv)


def fcurves_of(obj):
    ad = obj.animation_data
    return action_get_channelbag_for_slot(ad.action, ad.action_slot).fcurves


def leg_len(arm):
    b = arm.data.bones
    h = lambda n: b[n].head_local
    return ((h('Bip01 L Thigh') - h('Bip01 L Calf')).length + (h('Bip01 L Calf') - h('Bip01 L Foot')).length) * arm.matrix_world.to_scale()[0]


def img(path, noncolor=False):
    im = bpy.data.images.load(path)
    if noncolor:
        im.colorspace_settings.name = 'Non-Color'
    return im


def build_material(mat, code, part):
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(bsdf.outputs[0], out.inputs['Surface'])
    bsdf.inputs['Roughness'].default_value = 0.8
    bsdf.inputs['Metallic'].default_value = 0.0
    if part == 'opacity':
        t = nt.nodes.new('ShaderNodeTexImage'); t.image = img(S + f'tex/{code}_opacity_color.png')
        nt.links.new(t.outputs['Color'], bsdf.inputs['Base Color'])
        rnd = nt.nodes.new('ShaderNodeMath'); rnd.operation = 'ROUND'
        nt.links.new(t.outputs['Alpha'], rnd.inputs[0])
        nt.links.new(rnd.outputs[0], bsdf.inputs['Alpha'])
        mat.surface_render_method = 'DITHERED'
        mat.use_backface_culling = False
    else:
        t = nt.nodes.new('ShaderNodeTexImage'); t.image = img(S + f'tex/{code}_{part}_color.jpg')
        nt.links.new(t.outputs['Color'], bsdf.inputs['Base Color'])
        n = nt.nodes.new('ShaderNodeTexImage'); n.image = img(S + f'tex/{code}_{part}_normal.jpg', True)
        nm = nt.nodes.new('ShaderNodeNormalMap')
        nt.links.new(n.outputs['Color'], nm.inputs['Color'])
        nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
        mat.use_backface_culling = True


def build(out_name, avatar, g, code):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = 30
    bpy.ops.import_scene.fbx(filepath=S + f'src/{avatar}/{avatar}.fbx')
    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    for o in list(bpy.data.objects):
        if o.type not in ('ARMATURE', 'MESH'):
            bpy.data.objects.remove(o)
    for o in [arm] + meshes:
        o.animation_data_clear()
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    print('AVATAR', avatar, 'arm loc', tuple(arm.location), 'rot', tuple(arm.rotation_euler), 'scale', tuple(arm.scale))

    old_mw = arm.matrix_world.copy()
    loc, rot, _ = old_mw.decompose()
    root_m = Matrix.Translation(loc) @ rot.to_matrix().to_4x4()

    # unparent meshes, apply all transforms so everything is in world metres
    for m in meshes:
        mw = m.matrix_world.copy(); m.parent = None; m.matrix_world = mw
    bpy.ops.object.select_all(action='DESELECT')
    for o in [arm] + meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # add root bone at the old Bip01 node transform
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.data.edit_bones.new('Bip01')
    eb.head = (0, 0, 0); eb.tail = (0, 0.1, 0)
    eb.matrix = root_m
    eb.length = 0.1
    for b in arm.data.edit_bones:
        if b.parent is None and b.name != 'Bip01':
            b.use_connect = False
            b.parent = eb
    bpy.ops.object.mode_set(mode='OBJECT')
    arm.name = 'Armature'; arm.data.name = 'Armature'

    for m in meshes:
        m.parent = arm
        m.matrix_parent_inverse = Matrix.Identity(4)
        for mod in m.modifiers:
            if mod.type == 'ARMATURE':
                mod.object = arm
        m.name = out_name + '_mesh'
        tris = sum(len(p.vertices) - 2 for p in m.data.polygons)
        print('TRIS', out_name, tris)
        m.data.shape_keys and m.shape_key_clear()
        for slot in m.material_slots:
            mat = slot.material
            part = 'opacity' if 'opacity' in mat.name else ('head' if 'head' in mat.name else 'body')
            build_material(mat, code, part)

    # bind any unweighted vertices to the nearest deforming bone (else glTF adds a static neutral_bone)
    bnames = set(b.name for b in arm.data.bones)
    for m in meshes:
        valid = {vg.index for vg in m.vertex_groups if vg.name in bnames}
        for v in m.data.vertices:
            if sum(g.weight for g in v.groups if g.group in valid) <= 0:
                cands = [b for b in arm.data.bones if b.name != 'Bip01' and b.name in m.vertex_groups]
                nb = min(cands, key=lambda b: (b.head_local - v.co).length)
                if nb.parent and nb.parent.name == 'Bip01 Head':
                    nb = nb.parent
                m.vertex_groups[nb.name].add([v.index], 1.0, 'REPLACE')
                print('REBIND vertex', v.index, '->', nb.name)
    A_leg = leg_len(arm)
    arm_bones = set(b.name for b in arm.data.bones)

    for clip, fname, inplace in CLIPS:
        before = set(bpy.data.objects)
        pre_actions = set(bpy.data.actions)
        bpy.ops.import_scene.fbx(filepath=S + f'anim/{g}_{fname}.fbx')
        new = [o for o in bpy.data.objects if o not in before]
        src = next(o for o in new if o.type == 'ARMATURE')
        ratio = A_leg / leg_len(src)
        fr = [int(round(x)) for x in src.animation_data.action.frame_range]
        for fc in fcurves_of(src):
            if fc.data_path == 'location':
                kps = fc.keyframe_points
                if fc.array_index in (0, 1) and inplace:
                    v0 = kps[0].co[1]; v1 = kps[-1].co[1]; t0 = kps[0].co[0]; t1 = kps[-1].co[0]
                    for k in kps:
                        f = (k.co[0] - t0) / (t1 - t0)
                        d = v0 + (v1 - v0) * f
                        k.co[1] -= d; k.handle_left[1] -= d; k.handle_right[1] -= d
                elif fc.array_index == 2:
                    for k in kps:
                        k.co[1] *= ratio; k.handle_left[1] *= ratio; k.handle_right[1] *= ratio
                fc.update()
        print('CLIP', clip, 'frames', fr, 'leg ratio', round(ratio, 4))

        bpy.ops.object.select_all(action='DESELECT')
        bpy.context.view_layer.objects.active = arm
        arm.select_set(True)
        bpy.ops.object.mode_set(mode='POSE')
        for pb in arm.pose.bones:
            for c in list(pb.constraints): pb.constraints.remove(c)
            if pb.name == 'Bip01':
                c = pb.constraints.new('COPY_LOCATION'); c.target = src
                c = pb.constraints.new('COPY_ROTATION'); c.target = src
            elif pb.name in src.pose.bones:
                c = pb.constraints.new('COPY_ROTATION'); c.target = src; c.subtarget = pb.name
                c.target_space = 'WORLD'; c.owner_space = 'WORLD'
        sc.frame_start, sc.frame_end = fr
        if arm.animation_data:
            arm.animation_data.action = None
        bpy.ops.nla.bake(frame_start=fr[0], frame_end=fr[1], only_selected=False, visual_keying=True,
                         clear_constraints=True, use_current_action=False, bake_types={'POSE'})
        bpy.ops.object.mode_set(mode='OBJECT')
        act = arm.animation_data.action
        act.name = clip
        act.use_fake_user = True
        act.use_frame_range = True
        act.frame_start, act.frame_end = fr
        act.use_cyclic = True
        arm.animation_data.action = None
        for o in new:
            bpy.data.objects.remove(o)
        for a in list(bpy.data.actions):
            if a in pre_actions or a.name == clip:
                continue
            bpy.data.actions.remove(a)
    # tidy: remove orphan armature data
    for a in list(bpy.data.armatures):
        if a.users == 0:
            bpy.data.armatures.remove(a)
    print('ACTIONS', [(a.name, tuple(a.frame_range)) for a in bpy.data.actions])

    # rest pose foot height check (idle frame 1)
    arm.animation_data.action = bpy.data.actions['idle']
    arm.animation_data.action_slot = bpy.data.actions['idle'].slots[0]
    sc.frame_set(1)
    zs = [(arm.matrix_world @ arm.pose.bones[n].head).z for n in ('Bip01 L Toe0', 'Bip01 R Toe0', 'Bip01 L Foot', 'Bip01 R Foot', 'Bip01 Head')]
    print('IDLE f1 toeL/toeR/footL/footR/head z', [round(z, 3) for z in zs])
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.rotation_euler = (0, 0, 0); pb.scale = (1, 1, 1)

    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT + out_name + '.glb', export_format='GLB',
        export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True,
        export_anim_slide_to_zero=True, export_frame_range=False, export_def_bones=False,
        export_image_format='AUTO', export_image_quality=88, export_yup=True, export_skins=True,
        export_morph=False, export_apply=False, export_optimize_animation_size=True,
        export_reset_pose_bones=True)
    bpy.ops.wm.save_as_mainfile(filepath=S + 'blend/' + out_name + '.blend')


os.makedirs(S + 'blend', exist_ok=True)
for a in AVATARS:
    if only and a[0] not in only:
        continue
    build(*a)
print('DONE')
