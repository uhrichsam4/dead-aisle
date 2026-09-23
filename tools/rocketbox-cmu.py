# CMU Graphics Lab mocap (BVH, 120 fps) -> Rocketbox Biped, with rest-pose compensation.
# Used from build.py (exec'd into its globals): needs bpy, Matrix, Vector, math, S, leg_len.
# CMU licence: free for any use incl. commercial products; the raw data may not be resold.
import bpy, math
from mathutils import Matrix, Vector, Quaternion
from bpy_extras.anim_utils import action_get_channelbag_for_slot

CMU_DIR = '/private/tmp/claude-501/-Users-sam-Desktop-testtt/f33b73f6-0ced-49b8-9271-c4bc64f71fc2/scratchpad/cmu/'
# target bone: (CMU bone, CMU bone whose head the src direction points at, target bone whose head the tgt direction points at)
CMU_MAP = {
    'Bip01 Pelvis': ('Hips', None, None),
    'Bip01 Spine': ('LowerBack', 'Spine', 'Bip01 Spine1'),
    'Bip01 Spine1': ('Spine', 'Spine1', 'Bip01 Spine2'),
    'Bip01 Spine2': ('Spine1', 'Neck', 'Bip01 Neck'),
    'Bip01 Neck': ('Neck', 'Head', 'Bip01 Head'),
    'Bip01 Head': ('Head', None, None),
}
for s, c in (('L', 'Left'), ('R', 'Right')):
    CMU_MAP.update({
        f'Bip01 {s} Clavicle': (f'{c}Shoulder', f'{c}Arm', f'Bip01 {s} UpperArm'),
        f'Bip01 {s} UpperArm': (f'{c}Arm', f'{c}ForeArm', f'Bip01 {s} Forearm'),
        f'Bip01 {s} Forearm': (f'{c}ForeArm', f'{c}Hand', f'Bip01 {s} Hand'),
        f'Bip01 {s} Hand': (f'{c}Hand', f'{c}FingerBase', f'Bip01 {s} Finger2'),
        f'Bip01 {s} Thigh': (f'{c}UpLeg', f'{c}Leg', f'Bip01 {s} Calf'),
        f'Bip01 {s} Calf': (f'{c}Leg', f'{c}Foot', f'Bip01 {s} Foot'),
        f'Bip01 {s} Foot': (f'{c}Foot', f'{c}ToeBase', f'Bip01 {s} Toe0'),
        f'Bip01 {s} Toe0': (f'{c}ToeBase', None, None),
    })


def _yaw_between(a, b):
    """rotation about Z taking the XY direction of a onto that of b"""
    return Matrix.Rotation(math.atan2(b.y, b.x) - math.atan2(a.y, a.x), 3, 'Z')


def import_bvh(path):
    before = set(bpy.data.objects)
    bpy.ops.import_anim.bvh(filepath=path, global_scale=1.0, frame_start=0, use_fps_scale=False,
                            update_scene_fps=False, update_scene_duration=False, rotate_mode='NATIVE')
    src = next(o for o in bpy.data.objects if o not in before and o.type == 'ARMATURE')
    return src


def retarget_bvh(arm, take, t0, t1, name, rest_basis, times=None, yaw=0.0, yaw_list=None):
    """Bake CMU take `take` onto `arm` as action `name`, one key per entry of `times` (seconds into
    the take; default t0..t1 at 30 fps), frames 1..N. The first sample faces -Y with the hips over
    the origin, then turned by `yaw` (+ yaw_list[k] per sample). rest_basis: {bone: Matrix} pose
    for the bones the take does not drive (fingers, face)."""
    sc = bpy.context.scene
    src = import_bvh(CMU_DIR + take + '.bvh')
    sb = src.data.bones; tb = arm.data.bones
    SW = src.matrix_world
    s_rest = {b.name: (SW @ b.matrix_local) for b in sb}
    t_rest = {b.name: (arm.matrix_world @ b.matrix_local) for b in tb}
    # global yaw between the two rest poses, from the hip line (left -> right)
    ls = s_rest['RightUpLeg'].translation - s_rest['LeftUpLeg'].translation
    lt = t_rest['Bip01 R Thigh'].translation - t_rest['Bip01 L Thigh'].translation
    G = _yaw_between(ls, lt)
    K = {}
    for tn, (sn, sc_, tc) in CMU_MAP.items():
        Rmin = Matrix.Identity(3)
        if sc_ and tc and tc in tb:
            ds = G @ (s_rest[sc_].translation - s_rest[sn].translation)
            dt = t_rest[tc].translation - t_rest[tn].translation
            Rmin = ds.rotation_difference(dt).to_matrix()
        # target_world(t) = src_world(t) @ K
        K[tn] = s_rest[sn].to_3x3().inverted() @ G.inverted() @ Rmin.inverted() @ t_rest[tn].to_3x3()
    # leg-length scale (units and proportions)
    def chain(r, a, b, c):
        return (r[a].translation - r[b].translation).length + (r[b].translation - r[c].translation).length
    scale = chain(t_rest, 'Bip01 L Thigh', 'Bip01 L Calf', 'Bip01 L Foot') / chain(s_rest, 'LeftUpLeg', 'LeftLeg', 'LeftFoot')
    if times is None:
        times = [t0 + k / 30.0 for k in range(int(round((t1 - t0) * 30)) + 1)]
    samples = []
    for tt in times:
        f = tt * 120.0
        sc.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
        W = {pb.name: SW @ pb.matrix for pb in src.pose.bones}
        samples.append(W)
    # heading: make the first frame face -Y (target forward), hips over the origin
    W0 = samples[0]
    l0 = W0['RightUpLeg'].translation - W0['LeftUpLeg'].translation
    H0 = Matrix.Rotation(yaw, 3, 'Z') @ _yaw_between(l0, lt)
    p0 = W0['Hips'].translation.copy()
    M = Matrix.Diagonal((-1, 1, 1, 1))
    order = [pb for pb in arm.pose.bones]
    act = bpy.data.actions.new(name); act.use_fake_user = True
    arm.animation_data_create(); arm.animation_data.action = act
    rootpos = []
    prevq = {}
    root_rest = tb['Bip01'].matrix_local
    for k, W in enumerate(samples):
        fn = 1 + k
        H = ((Matrix.Rotation(yaw_list[k], 3, 'Z') @ H0) if yaw_list else H0).to_4x4()
        pos = W['Hips'].translation - Vector((p0.x, p0.y, 0))
        pos = (H @ pos.to_4d()).to_3d() * scale
        rootpos.append(pos)
        P = {}
        for pb in order:
            b = pb.bone
            par = b.parent
            local_rest = (par.matrix_local.inverted() @ b.matrix_local) if par else b.matrix_local
            if not par:                     # Bip01: translation only, rest orientation
                P[b.name] = Matrix.Translation(pos) @ Matrix(root_rest.to_3x3()).to_4x4()
            else:
                unposed = P[par.name] @ local_rest
                if b.name in CMU_MAP:
                    R = H.to_3x3() @ W[CMU_MAP[b.name][0]].to_3x3() @ K[b.name]
                    P[b.name] = Matrix.Translation(unposed.translation) @ R.to_4x4()
                else:
                    P[b.name] = unposed @ rest_basis.get(b.name, Matrix.Identity(4))
            basis = (local_rest.inverted() @ P[par.name].inverted() @ P[b.name]) if par else (b.matrix_local.inverted() @ P[b.name])
            q = basis.to_quaternion().normalized()
            if b.name in prevq and prevq[b.name].dot(q) < 0:
                q.negate()
            prevq[b.name] = q
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = q
            pb.keyframe_insert('rotation_quaternion', frame=fn)
            if not par:
                pb.location = basis.to_translation()
                pb.keyframe_insert('location', frame=fn)
    n = len(samples)
    # clean up the source
    sa = src.animation_data.action if src.animation_data else None
    bpy.data.objects.remove(src)
    if sa: bpy.data.actions.remove(sa)
    arm.animation_data.action = None
    act.use_frame_range = True
    act.frame_start, act.frame_end = 1, n
    print('CMU', take, (round(times[0], 3), round(times[-1], 3)), '->', name, 'frames', n, 'scale', round(scale, 4))
    return act, rootpos, scale


# ---------------------------------------------------------------- post-processing
def _root_fcs(act):
    fcs = action_get_channelbag_for_slot(act, act.slots[0]).fcurves
    return {fc.array_index: fc for fc in fcs if fc.data_path == 'pose.bones["Bip01"].location'}


def _bone_world(arm, fn, names):
    bpy.context.scene.frame_set(fn)
    return {n: arm.matrix_world @ arm.pose.bones[n].head for n in names}


def root_world_to_basis(arm):
    """basis location of Bip01 = R_rest^-1 @ (world - rest head): returns (Rinv, head)"""
    b = arm.data.bones['Bip01']
    return b.matrix_local.to_3x3().inverted(), b.matrix_local.translation.copy()


def shift_root(arm, act, fn_offset):
    """add a world-space offset fn_offset(frame) -> Vector to Bip01 for every key"""
    Rinv, _ = root_world_to_basis(arm)
    fcs = _root_fcs(act)
    n = len(fcs[0].keyframe_points)
    for i in range(n):
        f = fcs[0].keyframe_points[i].co[0]
        d = Rinv @ fn_offset(f)
        for ax in range(3):
            k = fcs[ax].keyframe_points[i]
            k.co[1] += d[ax]; k.handle_left[1] += d[ax]; k.handle_right[1] += d[ax]
    for fc in fcs.values():
        fc.update()


def root_world_positions(arm, act):
    arm.animation_data.action = act; arm.animation_data.action_slot = act.slots[0]
    f0, f1 = [int(round(x)) for x in act.frame_range]
    out = {}
    for fn in range(f0, f1 + 1):
        bpy.context.scene.frame_set(fn)
        out[fn] = (arm.matrix_world @ arm.pose.bones['Bip01'].matrix).translation.copy()
    arm.animation_data.action = None
    return out


def make_inplace(arm, act, fa, fb):
    """remove the straight-line XY drift between frames fa and fb (applied along the whole clip)"""
    P = root_world_positions(arm, act)
    d = P[fb] - P[fa]; d.z = 0
    shift_root(arm, act, lambda f: -(Vector((P[fa].x, P[fa].y, 0)) + d * ((f - fa) / (fb - fa))))
    return d.length


def mesh_min_z(arm, meshes, act, step=1):
    arm.animation_data.action = act; arm.animation_data.action_slot = act.slots[0]
    f0, f1 = [int(round(x)) for x in act.frame_range]
    out = {}
    for fn in range(f0, f1 + 1, step):
        bpy.context.scene.frame_set(fn)
        dg = bpy.context.evaluated_depsgraph_get()
        z = 1e9
        for m in meshes:
            ev = m.evaluated_get(dg)
            me = ev.to_mesh()
            mw = ev.matrix_world
            z = min(z, min((mw @ v.co).z for v in me.vertices))
            ev.to_mesh_clear()
        out[fn] = z
    arm.animation_data.action = None
    return out


def ground(arm, meshes, act, mode):
    """put the lowest vertex on z=0: 'const' (median over the clip) or 'ends' (start and end
    matched separately, blended across the clip)"""
    Z = mesh_min_z(arm, meshes, act, 2)
    fs = sorted(Z)
    if mode == 'const':
        zs = sorted(Z.values()); off0 = off1 = -zs[len(zs) // 2]
    else:
        a = sorted(Z[f] for f in fs[:4]); b = sorted(Z[f] for f in fs[-4:])
        off0, off1 = -a[len(a) // 2], -b[len(b) // 2]
    fa, fb = fs[0], fs[-1]
    def off(f):
        w = min(1, max(0, (f - fa) / max(1, fb - fa))); w = w * w * (3 - 2 * w)
        return Vector((0, 0, off0 + (off1 - off0) * w))
    shift_root(arm, act, off)
    print('GROUND', act.name, mode, 'offset start/end', round(off0, 3), round(off1, 3), 'raw min', round(min(Z.values()), 3), 'max', round(max(Z.values()), 3))
    return off0, off1


def pelvis_local_pose(arm, fn, names=('Bip01 L Hand', 'Bip01 R Hand', 'Bip01 L Foot', 'Bip01 R Foot', 'Bip01 Head', 'Bip01 L Calf', 'Bip01 R Calf')):
    bpy.context.scene.frame_set(fn)
    mw = arm.matrix_world
    pel = mw @ arm.pose.bones['Bip01 Pelvis'].head
    r = (mw @ arm.pose.bones['Bip01 R Thigh'].head) - (mw @ arm.pose.bones['Bip01 L Thigh'].head)
    yaw = math.atan2(r.y, r.x)
    Rz = Matrix.Rotation(-yaw, 3, 'Z')
    pts = []
    for n in names:
        v = (mw @ arm.pose.bones[n].head) - Vector((pel.x, pel.y, 0))
        pts.append(Rz @ v)
    return pts, yaw, Vector((pel.x, pel.y))


def find_cycle(arm, act, lo, hi, smin, smax, travel=0.0):
    """frames s (in lo..hi) and e (s+smin..s+smax) whose pelvis-relative poses match best"""
    arm.animation_data.action = act; arm.animation_data.action_slot = act.slots[0]
    f1 = int(round(act.frame_range[1]))
    feat = {fn: pelvis_local_pose(arm, fn) for fn in range(lo, min(f1, hi + smax) + 1)}
    arm.animation_data.action = None
    best = None
    for s in range(lo, hi + 1):
        for e in range(s + smin, s + smax + 1):
            if e not in feat or (feat[e][2] - feat[s][2]).length < travel:
                continue
            err = max((a - b).length for a, b in zip(feat[s][0], feat[e][0]))
            if best is None or err < best[0]:
                dy = feat[e][1] - feat[s][1]
                dy = (dy + math.pi) % (2 * math.pi) - math.pi
                best = (err, s, e, dy)
    return best


def seam_blend(act, s, e, B):
    """make frame e equal frame s by cross-fading the last B frames into the B frames before s,
    then keep only s..e (as trim_loop, but at a known cycle)"""
    fcs = action_get_channelbag_for_slot(act, act.slots[0]).fcurves
    L = e - s
    f0 = int(round(act.frame_range[0]))
    vals = {fc: {int(round(k.co[0])): k.co[1] for k in fc.keyframe_points} for fc in fcs}
    quats = {}
    for fc in fcs:
        if fc.data_path.endswith('rotation_quaternion'):
            quats.setdefault(fc.data_path, [None] * 4)[fc.array_index] = fc
    flip = {}
    for dp, q in quats.items():
        for tt in range(e - B, e + 1):
            flip[(dp, tt)] = -1.0 if sum(vals[c][tt] * vals[c][tt - L] for c in q) < 0 else 1.0
    for fc in fcs:
        new = []
        for tt in range(s, e + 1):
            v = vals[fc][tt]
            if tt >= e - B and B > 0:
                w = (tt - (e - B)) / B; w = w * w * (3 - 2 * w)
                v = (1 - w) * v + w * vals[fc][tt - L] * flip.get((fc.data_path, tt), 1.0)
            new.append(v)
        kp = fc.keyframe_points; kp.clear(); kp.add(len(new))
        for i, v in enumerate(new):
            kp[i].co = (1 + i, v); kp[i].interpolation = 'LINEAR'
        fc.update()
    for dp, q in quats.items():
        for i in range(L + 1):
            nrm = math.sqrt(sum(c.keyframe_points[i].co[1] ** 2 for c in q)) or 1.0
            for c in q:
                c.keyframe_points[i].co[1] /= nrm
        for c in q:
            c.update()
    act.frame_start, act.frame_end = 1, L + 1


def hand_reach(arm, act):
    """frame and hand of the strike: the hand furthest ahead of the pelvis, along -Y"""
    arm.animation_data.action = act; arm.animation_data.action_slot = act.slots[0]
    f0, f1 = [int(round(x)) for x in act.frame_range]
    reach = []
    for fn in range(f0, f1 + 1):
        w = _bone_world(arm, fn, ('Bip01 Pelvis', 'Bip01 L Hand', 'Bip01 R Hand'))
        for h in ('Bip01 L Hand', 'Bip01 R Hand'):
            v = w[h] - w['Bip01 Pelvis']; v.z = 0
            reach.append((v.length, fn, h, v.copy()))
    arm.animation_data.action = None
    best = max(reach, key=lambda r: r[0])
    # contact: the first frame the striking hand is (nearly) at full reach, not where it is held
    hit = next(r for r in reach if r[2] == best[2] and r[0] >= 0.93 * best[0])
    return (best[0], hit[1], best[2], best[3])


def cmu_clip(arm, meshes, name, spec, rest_basis):
    """build one CMU action from a spec dict; returns extras {'speed':..} / {'hit':..}"""
    kind = spec['kind']
    take = spec['take']; t0, t1 = spec['t']
    rate = spec.get('rate', 1.0)
    extras = {}
    if kind == 'loop':                                     # crawl: find a cycle, in place, seamless
        pre = retarget_bvh(arm, take, t0, t1, name + '_scan', rest_basis)[0]
        B = 15
        err, s, e, dyaw = find_cycle(arm, pre, 1 + B, 1 + B + 45, spec['cycle'][0], spec['cycle'][1], spec.get('travel', 0.25))
        bpy.data.actions.remove(pre)
        ts, te = t0 + (s - 1) / 30.0, t0 + (e - 1) / 30.0
        times = [ts + (k - B) / 30.0 for k in range(0, e - s + B + 1)]
        yl = [-dyaw * (k - B) / (e - s) for k in range(len(times))]
        act = retarget_bvh(arm, take, 0, 0, name, rest_basis, times=times, yaw_list=yl)[0]
        P = root_world_positions(arm, act)
        dist = (P[1 + B + (e - s)] - P[1 + B]); dist.z = 0
        extras['speed'] = round(dist.length / ((e - s) / 30.0), 2)
        make_inplace(arm, act, 1 + B, 1 + B + (e - s))
        seam_blend(act, 1 + B, 1 + B + (e - s), B)
        ground(arm, meshes, act, 'const')
        print('CYCLE', name, take, 'secs', round(ts, 2), round(te, 2), 'err', round(err, 3), 'yaw drift', round(math.degrees(dyaw), 1), 'speed', extras['speed'])
    elif kind == 'pingpong':                               # writhe: there and back, closes by construction
        n = int(round((t1 - t0) * 30 / rate))
        fw = [t0 + (t1 - t0) * (0.5 - 0.5 * math.cos(math.pi * k / n)) for k in range(n + 1)]   # eased ends
        times = fw + fw[-2::-1]
        act = retarget_bvh(arm, take, 0, 0, name, rest_basis, times=times)[0]
        ground(arm, meshes, act, 'const')
    else:                                                   # one-shots
        n = int(round((t1 - t0) * 30 / rate))
        times = [t0 + (t1 - t0) * k / n for k in range(n + 1)]
        if spec.get('reverse'):
            times = times[::-1]
        act, rp, sc_ = retarget_bvh(arm, take, 0, 0, name, rest_basis, times=times)
        if kind == 'attack':                                # turn so the strike goes along -Y (forward)
            _, fn, hand, v = hand_reach(arm, act)
            yaw = math.atan2(-1, 0) - math.atan2(v.y, v.x)
            bpy.data.actions.remove(act)
            act = retarget_bvh(arm, take, 0, 0, name, rest_basis, times=times, yaw=yaw)[0]
            _, fn, hand, v = hand_reach(arm, act)
            extras['hit'] = round((fn - 1) / 30.0, 2)
            P = root_world_positions(arm, act)
            step = (P[max(P)] - P[1]); step.z = 0
            print('ATTACK', name, take, 'hit', extras['hit'], hand, 'step', round(step.length, 2))
        ground(arm, meshes, act, 'ends')
    act.use_fake_user = True
    act.use_frame_range = True
    act.frame_start, act.frame_end = [int(round(x)) for x in (act.frame_range[0], act.frame_range[1])]
    act.use_cyclic = kind in ('loop', 'pingpong')
    return act, extras


COMBAT = [
    ('attack', dict(kind='attack', take='76_01', t=(5.6, 6.9))),        # lunge + grab/swing
    ('attack_2', dict(kind='attack', take='13_17', t=(1.35, 2.45))),    # step-in straight right
    ('attack_3', dict(kind='attack', take='111_19', t=(0.45, 1.65))),   # step + punch
    ('death', dict(kind='once', take='140_01', t=(0.6, 6.6), reverse=True, rate=1.8)),   # sinks forward onto the face
    ('death_2', dict(kind='once', take='90_18', t=(0.4, 2.6))),         # feet taken away, onto the back
    ('death_3', dict(kind='once', take='113_08', t=(1.0, 4.8), rate=1.4)),              # knees, sit, over onto the back
    ('fall_prone', dict(kind='once', take='111_03', t=(0.8, 2.9))),     # standing -> down on the belly
    ('crawl', dict(kind='loop', take='133_01', t=(4.4, 8.0), cycle=(25, 70))),
    ('crawl_2', dict(kind='loop', take='133_02', t=(3.4, 8.0), cycle=(25, 70))),
    ('crawl_3', dict(kind='loop', take='111_03', t=(3.0, 9.5), cycle=(30, 100), travel=0.3)),   # slow, dragging
    ('writhe', dict(kind='pingpong', take='140_03', t=(0.4, 2.2), rate=0.8)),
    ('writhe_2', dict(kind='pingpong', take='111_21', t=(5.5, 8.5), rate=0.8)),
    ('writhe_3', dict(kind='pingpong', take='140_04', t=(0.5, 2.5), rate=0.8)),
]
