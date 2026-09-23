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
# (action name, source, in-place: strip the root's XY travel, loop)
# source: a Rocketbox clip name (prefixed m_/f_ by gender), a {'m': .., 'f': ..} pair,
# or ('mirror', <an action built earlier in the list>) for a true L/R mirror of it
CLIPS = [
    ('idle', 'idle_neutral_01', False, True),
    ('idle_2', 'idle_neutral_02', False, True),
    ('idle_3', 'idle_neutral_03', False, True),
    ('idle_angry', 'idle_angry_01', False, True),
    ('idle_angry_2', 'idle_angry_02', False, True),
    ('idle_angry_3', ('mirror', 'idle_angry'), False, True),
    ('idle_look', 'idle_look_around_01', False, True),
    ('idle_look_2', 'idle_look_around_02', False, True),
    ('idle_look_3', 'idle_look_around_03', False, True),
    ('idle_nervous', 'idle_nervous_01', False, True),
    ('idle_nervous_2', 'idle_nervous_02', False, True),
    ('idle_nervous_3', 'idle_nervous_03', False, True),
    ('walk', 'walk_neutral', True, True),
    ('walk_2', 'walk_neutral_01', True, True),
    ('walk_3', 'walk_neutral_02', True, True),
    ('walk_shamble', 'walk_drunk', True, True),
    ('walk_shamble_2', ('mirror', 'walk_shamble'), True, True),
    ('walk_shamble_3', ['heavy', 'walk_slow_02'], True, True),   # funny_01 reads as a plain walk
    ('walk_injured', 'walk_bruised', True, True),
    ('walk_injured_2', 'walk_injured', True, True),          # male has no take: the female's
    ('walk_injured_3', ('mirror', 'walk_injured'), True, True),
    ('walk_stroll', 'walk_stroll_01', True, True),
    ('walk_stroll_2', 'walk_stroll_02', True, True),
    ('walk_stroll_3', 'walk_slow_01', True, True),
    ('run', 'run_neutral', True, True),
    ('run_2', 'run_neutral_01', True, True),
    ('run_3', {'m': 'run_slow_02', 'f': 'run_neutral_02'}, True, True),   # m_run_neutral_02 duplicates m_run_neutral
    ('run_fast', 'run_fast_01', True, True),
    ('run_fast_2', {'m': 'run_fast_02', 'f': 'run_extremefemale'}, True, True),
    ('run_fast_3', ('mirror', 'run_fast'), True, True),
    ('run_injured', 'run_injured', True, True),
    ('run_injured_2', ('mirror', 'run_injured'), True, True),
    ('run_injured_3', 'run_slow_01', True, True),
]
# idles longer than this are cut to a loop of at most TRIM_MAX frames, cross-faded over TRIM_FADE
TRIM_MAX, TRIM_MIN, TRIM_FADE = 300, 180, 30
SPEEDS_JSON = '/Users/sam/Desktop/testtt/godot/assets/enemies/clip_speeds.json'
EVENTS_JSON = '/Users/sam/Desktop/testtt/godot/assets/enemies/clip_events.json'
SPEEDS = {}
EVENTS = {}
# CMU mocap combat / death / ground clips (cmu.py): attack*, death*, fall_prone, crawl*, writhe*
exec(open(S + 'cmu.py').read())

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
only = set(argv)


def fcurves_of(obj):
    ad = obj.animation_data
    return action_get_channelbag_for_slot(ad.action, ad.action_slot).fcurves


def leg_len(arm):
    b = arm.data.bones
    h = lambda n: b[n].head_local
    return ((h('Bip01 L Thigh') - h('Bip01 L Calf')).length + (h('Bip01 L Calf') - h('Bip01 L Foot')).length) * arm.matrix_world.to_scale()[0]


LOOP_BONES = ('Bip01 L Foot', 'Bip01 R Foot', 'Bip01 L Hand', 'Bip01 R Hand', 'Bip01 Head',
              'Bip01 L Calf', 'Bip01 R Calf', 'Bip01 L Forearm', 'Bip01 R Forearm')


def trim_loop(arm, act, fr):
    """Cut a long baked clip to [s, e] (s = 1 + fade) where the pose best matches frame s,
    and cross-fade the last `fade` frames into the frames just before s, so e == s exactly."""
    sc = bpy.context.scene
    B = TRIM_FADE
    arm.animation_data.action = act
    arm.animation_data.action_slot = act.slots[0]
    poses = {}
    for fn in range(fr[0] + B, min(fr[1], fr[0] + B + 90 + TRIM_MAX) + 1):
        sc.frame_set(fn)
        poses[fn] = [arm.matrix_world @ arm.pose.bones[b].head for b in LOOP_BONES]
    best = None
    for s in range(fr[0] + B, fr[0] + B + 91, 3):         # start and end both free: the closest pair
        for e in range(s + TRIM_MIN, min(fr[1], s + TRIM_MAX) + 1):
            if s not in poses or e not in poses:
                continue
            err = max((a - b).length for a, b in zip(poses[s], poses[e]))
            if best is None or err < best[0]:
                best = (err, s, e)
    err, s, e = best
    L = e - s
    fcs = action_get_channelbag_for_slot(act, act.slots[0]).fcurves
    vals = {fc: [fc.evaluate(f) for f in range(fr[0], fr[1] + 1)] for fc in fcs}
    at = lambda fc, f: vals[fc][f - fr[0]]
    # quaternion sign per bone and frame, so the blend never takes the long way round
    quats = {}
    for fc in fcs:
        if fc.data_path.endswith('rotation_quaternion'):
            quats.setdefault(fc.data_path, [None] * 4)[fc.array_index] = fc
    flip = {}
    for dp, q in quats.items():
        for t in range(e - B, e + 1):
            d = sum(at(c, t) * at(c, t - L) for c in q)
            flip[(dp, t)] = -1.0 if d < 0 else 1.0
    for fc in fcs:
        new = []
        for t in range(s, e + 1):
            v = at(fc, t)
            if t >= e - B:
                w = (t - (e - B)) / B
                w = w * w * (3 - 2 * w)
                v2 = at(fc, t - L) * flip.get((fc.data_path, t), 1.0)
                v = (1 - w) * v + w * v2
            new.append(v)
        kp = fc.keyframe_points
        kp.clear()
        kp.add(len(new))
        for i, v in enumerate(new):
            kp[i].co = (s + i, v)
            kp[i].interpolation = 'LINEAR'
        fc.update()
    # re-normalise quaternions
    for dp, q in quats.items():
        for i in range(e - s + 1):
            n = math.sqrt(sum(c.keyframe_points[i].co[1] ** 2 for c in q)) or 1.0
            for c in q:
                c.keyframe_points[i].co[1] /= n
        for c in q:
            c.update()
    arm.animation_data.action = None
    print('TRIM', act.name, 'from', fr, 'to', (s, e), 'seam err before fade', round(err, 3))
    return [s, e]


def mirror_action(arm, src, name):
    """A true left/right mirror of `src`: every bone takes its partner's armature-space pose
    reflected through the body's YZ plane, re-expressed in its own rest frame."""
    sc = bpy.context.scene
    M = Matrix.Diagonal((-1, 1, 1, 1))
    bones = arm.data.bones
    def partner(n):
        return n.replace(' L ', ' R ') if ' L ' in n else (n.replace(' R ', ' L ') if ' R ' in n else n)
    F = {}
    for b in bones:
        p = bones.get(partner(b.name))
        if p is None:
            continue
        f = (M @ p.matrix_local).inverted() @ b.matrix_local
        if max(abs(f[i][j] - (round(f[i][j]) if i == j else 0)) for i in range(3) for j in range(3)) < 0.05:
            F[b.name] = f                    # symmetric pair (face rig bones are not: they keep their pose)
    order = [pb for pb in arm.pose.bones]    # parents first
    f0, f1 = [int(round(x)) for x in src.frame_range]
    arm.animation_data.action = src
    arm.animation_data.action_slot = src.slots[0]
    frames = []
    for fn in range(f0, f1 + 1):
        sc.frame_set(fn)
        frames.append(({pb.name: pb.matrix.copy() for pb in order}, {pb.name: pb.matrix_basis.copy() for pb in order}))
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    prevq = {}
    for k, (P, basis0) in enumerate(frames):
        fn = f0 + k
        Pm = {}
        for pb in order:
            b = pb.bone
            if b.name in F:
                Pm[b.name] = M @ P[partner(b.name)] @ F[b.name]
            elif b.parent:
                Pm[b.name] = Pm[b.parent.name] @ (b.parent.matrix_local.inverted() @ b.matrix_local) @ basis0[b.name]
            else:
                Pm[b.name] = P[b.name]
            if b.parent:
                basis = (b.parent.matrix_local.inverted() @ b.matrix_local).inverted() @ Pm[b.parent.name].inverted() @ Pm[b.name]
            else:
                basis = b.matrix_local.inverted() @ Pm[b.name]
            q = basis.to_quaternion()
            if b.name in prevq and prevq[b.name].dot(q) < 0:
                q.negate()
            prevq[b.name] = q
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = q
            pb.keyframe_insert('rotation_quaternion', frame=fn)
            if not b.parent:
                pb.location = basis.to_translation()
                pb.keyframe_insert('location', frame=fn)
    arm.animation_data.action = None
    for pb in order:
        pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0)
    act.use_frame_range = True
    act.frame_start, act.frame_end = f0, f1
    act.use_cyclic = src.use_cyclic
    print('MIRROR', src.name, '->', name, (f0, f1), 'unmirrored bones', len(bones) - len(F))
    return act


def make_heavy(arm, act, stretch=1.3):
    """Turn a slow walk into a dragging shamble: stoop the spine, drop the head, play it slower."""
    sc = bpy.context.scene
    # (not 'Bip01 Spine': the Biped thighs hang off it, so leaning it would lift the feet)
    lean = {'Bip01 Spine1': 12, 'Bip01 Spine2': 9, 'Bip01 Neck': 6, 'Bip01 Head': 10,
            'Bip01 L UpperArm': -6, 'Bip01 R UpperArm': -6}
    f0, f1 = [int(round(x)) for x in act.frame_range]
    arm.animation_data.action = act
    arm.animation_data.action_slot = act.slots[0]
    fcs = action_get_channelbag_for_slot(act, act.slots[0]).fcurves
    newq = {}
    for fn in range(f0, f1 + 1):
        sc.frame_set(fn)
        for n, deg in lean.items():
            pb = arm.pose.bones.get(n)
            if pb is None:
                continue
            R = Matrix.Rotation(math.radians(deg), 3, 'X')
            P = pb.matrix.to_3x3()
            d = (P.inverted() @ R @ P).to_quaternion()
            newq.setdefault(n, []).append(pb.rotation_quaternion @ d)
    for n, qs in newq.items():
        dp = f'pose.bones["{n}"].rotation_quaternion'
        for fc in fcs:
            if fc.data_path == dp:
                for i, k in enumerate(fc.keyframe_points):
                    k.co[1] = qs[i][fc.array_index]; k.interpolation = 'LINEAR'
                fc.update()
    # slow it down: stretch every key in time about f0, to a whole number of frames so the loop closes
    stretch = round((f1 - f0) * stretch) / (f1 - f0)
    for fc in fcs:
        for k in fc.keyframe_points:
            for attr in ('co', 'handle_left', 'handle_right'):
                v = getattr(k, attr); v[0] = f0 + (v[0] - f0) * stretch
            k.interpolation = 'LINEAR'
        fc.update()
    arm.animation_data.action = None
    f1s = int(round(f0 + (f1 - f0) * stretch))
    print('HEAVY', act.name, (f0, f1), '->', (f0, f1s), 'stretch', round(stretch, 4))
    return [f0, f1s], stretch


def write_speeds(key, d, path=SPEEDS_JSON):
    import json
    try:
        allsp = json.load(open(path))
    except Exception:
        allsp = {}
    allsp[key] = d
    with open(path, 'w') as f:
        json.dump(dict(sorted(allsp.items())), f, indent=1)
        f.write('\n')


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

    speeds = {}
    for clip, fname, inplace, loop in CLIPS:
        if isinstance(fname, tuple):
            mirror_action(arm, bpy.data.actions[fname[1]], clip)
            if fname[1] in speeds:
                speeds[clip] = speeds[fname[1]]
            continue
        heavy = isinstance(fname, list)          # ['heavy', clip]
        if heavy:
            fname = fname[1]
        if isinstance(fname, dict):
            fname = fname[g]
        before = set(bpy.data.objects)
        pre_actions = set(bpy.data.actions)
        path = S + (f'anim/{fname}.fbx' if fname[:2] in ('m_', 'f_') else f'anim/{g}_{fname}.fbx')   # explicit m_/f_ = that take
        if not os.path.exists(path):          # this gender lacks the clip: borrow the other's
            path = S + f'anim/{"f" if g == "m" else "m"}_{fname}.fbx'
            print('FALLBACK', clip, path)
        bpy.ops.import_scene.fbx(filepath=path)
        new = [o for o in bpy.data.objects if o not in before]
        src = next(o for o in new if o.type == 'ARMATURE')
        ratio = A_leg / leg_len(src)
        fr = [int(round(x)) for x in src.animation_data.action.frame_range]
        if clip.startswith(('walk', 'run')):
            sc.frame_set(fr[0]); r0 = src.matrix_world.translation.copy()
            sc.frame_set(fr[1]); r1 = src.matrix_world.translation.copy()
            speeds[clip] = round((r1 - r0).xy.length / ((fr[1] - fr[0]) / 30.0) * ratio, 2)
            print('SPEED', clip, speeds[clip], 'm/s')
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
        arm.animation_data.action = None
        if loop and fr[1] - fr[0] > TRIM_MAX + TRIM_FADE:
            fr = trim_loop(arm, act, fr)
        if heavy:
            fr, k = make_heavy(arm, act)
            if clip in speeds:
                speeds[clip] = round(speeds[clip] / k, 2)
        act.use_frame_range = True
        act.frame_start, act.frame_end = fr
        act.use_cyclic = loop
        for o in new:
            bpy.data.objects.remove(o)
        for a in list(bpy.data.actions):
            if a in pre_actions or a.name == clip:
                continue
            bpy.data.actions.remove(a)
    # --- CMU clips, posed from the idle's first frame for the bones CMU does not drive (fingers, face)
    events = {}
    if COMBAT:
        idle = bpy.data.actions['idle']
        arm.animation_data.action = idle; arm.animation_data.action_slot = idle.slots[0]
        sc.frame_set(int(idle.frame_range[0]))
        rest_basis = {pb.name: pb.matrix_basis.copy() for pb in arm.pose.bones}
        arm.animation_data.action = None
        for clip, spec in COMBAT:
            if isinstance(spec, tuple):
                mirror_action(arm, bpy.data.actions[spec[1]], clip)
                if spec[1] in speeds: speeds[clip] = speeds[spec[1]]
                if spec[1] in events: events[clip] = dict(events[spec[1]])
                continue
            act, ex = cmu_clip(arm, meshes, clip, spec, rest_basis)
            if 'speed' in ex: speeds[clip] = ex['speed']
            if 'hit' in ex: events[clip] = {'hit': ex['hit']}
    EVENTS[out_name] = events
    SPEEDS[out_name] = speeds
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
    write_speeds(a[0], SPEEDS[a[0]])
    write_speeds(a[0], EVENTS[a[0]], EVENTS_JSON)
print('DONE')
