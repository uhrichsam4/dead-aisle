#!/usr/bin/env python3
"""Generate DEAD AISLE's player audio with the ElevenLabs API.

Runs LOCALLY only. The key is read from ~/.config/deadaisle/eleven.env and never
enters the repo or the shipped build - dead-aisle.html keeps ELEVEN_KEY='' and
plays these files as static assets.

Resumable: anything already on disk is skipped, so a rate-limit or a crash costs
nothing. Every clip is post-processed to mono, silence-trimmed and peak
normalised, which is what makes a set of variants sit together instead of
jumping in level.

  python3 tools/gen-audio.py            # generate everything missing
  python3 tools/gen-audio.py --dry      # list what WOULD be generated
  python3 tools/gen-audio.py --only step,breath
"""
import json, os, subprocess, sys, time, urllib.request, urllib.error

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sfx')
ENV = os.path.expanduser('~/.config/deadaisle/eleven.env')
SFX_URL = 'https://api.elevenlabs.io/v1/sound-generation'
TTS_VOICE = 'IKne3meq5aSn9XLyUdCD'          # Charlie, AU male - the game's voice
TTS_URL = f'https://api.elevenlabs.io/v1/text-to-speech/{TTS_VOICE}?output_format=mp3_44100_128'

def key():
    if not os.path.exists(ENV):
        sys.exit(f'no key file at {ENV}')
    for line in open(ENV):
        if line.startswith('ELEVEN_KEY_1='):
            return line.split('=', 1)[1].strip()
    sys.exit('ELEVEN_KEY_1 not found')

# (family, name, prompt, seconds, count, influence)
# Prompts are deliberately specific: close-mic and dry, because the game adds
# its own space. A prompt that mentions a room bakes reverb in and the sound
# then fights the world it is played in.
SFX = [
 # ---- breathing: the spine of the calm/stressed system ----
 ('breath','calm',      'quiet calm nasal exhale, single breath, close mic, dry, no music', 2.0, 3, .55),
 ('breath','medium',    'moderate winded breathing through mouth, single breath cycle, close mic, dry', 2.0, 3, .55),
 ('breath','heavy',     'heavy exhausted panting, one breath in and out, close mic, dry, no music', 2.2, 4, .6),
 ('breath','spent',     'ragged desperate gasping for air, exhausted, close mic, dry', 2.4, 3, .6),
 ('breath','hold',      'sharp inhale then holding breath, close mic, dry', 1.6, 2, .6),
 # ---- footsteps ----
 ('step','tile',        'single boot footstep on hard ceramic tile floor, close mic, dry, no reverb', 0.9, 6, .7),
 ('step','concrete',    'single boot footstep on rough concrete, close mic, dry, no reverb', 0.9, 6, .7),
 ('step','gravel',      'single boot footstep crunching on loose gravel, close mic, dry', 1.0, 4, .7),
 ('step','grass',       'single boot footstep on grass and soil, soft, close mic, dry', 1.0, 4, .7),
 ('step','wet',         'single boot footstep in shallow water on tile, wet splash, close mic, dry', 1.0, 4, .7),
 ('sprint','tile',      'fast running boot footstep on tile, heavy impact, close mic, dry', 0.7, 4, .7),
 ('sprint','concrete',  'fast running boot footstep on concrete, heavy impact, close mic, dry', 0.7, 4, .7),
 # ---- weapon handling ----
 ('gun','shot',         'single assault rifle gunshot, dry close mic, punchy, no reverb tail', 1.4, 6, .65),
 ('gun','dry',          'rifle trigger click on empty chamber, dry metallic, close mic', 0.8, 2, .7),
 ('gun','magout',       'rifle magazine released and pulled out of magwell, metal on polymer, close mic, dry', 1.2, 3, .65),
 ('gun','magin',        'rifle magazine inserted and seated with a firm click, close mic, dry', 1.2, 3, .65),
 ('gun','charge',       'rifle charging handle pulled back and released, metallic clack, close mic, dry', 1.2, 3, .65),
 ('gun','fumble',       'fumbled magazine, hand slips, magazine knocks against rifle then seats, close mic, dry', 1.8, 2, .6),
 ('gun','draw',         'rifle lifted and shouldered, sling and fabric movement, close mic, dry', 1.4, 3, .6),
 ('gun','holster',      'rifle lowered onto sling, fabric and light metal settle, close mic, dry', 1.4, 2, .6),
 ('gun','adsin',        'quick fabric and gear shift as rifle is raised to aim, close mic, dry', 0.8, 2, .6),
 ('gun','adsout',       'quick fabric shift as rifle is lowered from aim, close mic, dry', 0.8, 2, .6),
 # ---- gear / the GoPro ----
 ('gear','gopro_on',    'small action camera powering on, single soft electronic beep and click, close mic, dry', 1.6, 2, .7),
 ('gear','gopro_beep',  'single short electronic confirmation beep from a small camera, close mic, dry', 0.7, 2, .75),
 ('gear','strap',       'nylon head strap tightened, velcro and buckle, close mic, dry', 1.4, 2, .65),
 ('gear','rustle',      'tactical vest and webbing shifting on a body, fabric and light buckles, close mic, dry', 1.4, 3, .6),
 # ---- car ----
 ('car','start',        'sedan engine cranking and starting, from inside the car, no music', 3.0, 2, .6),
 ('car','rev',          'sedan petrol engine revving up and settling, from inside the car', 2.6, 2, .6),
 ('car','dooropen',     'car door handle pulled and door opening, close mic, dry', 1.6, 2, .65),
 ('car','doorclose',    'car door closing with a solid thud and latch, close mic, dry', 1.4, 2, .7),
 ('car','trunkopen',    'car boot latch popping and lid lifting on struts, close mic, dry', 2.0, 2, .65),
 ('car','trunkclose',   'car boot lid pushed down and latching shut, close mic, dry', 1.4, 2, .7),
 ('car','handbrake',    'handbrake lever ratcheting up, mechanical clicks, close mic, dry', 1.2, 1, .7),
 ('car','seatbelt',     'seatbelt drawn out and clicked into the buckle, close mic, dry', 1.8, 1, .65),
 # ---- bullet impacts on materials (the player's rounds landing) ----
 ('hit','metal',        'bullet impact on sheet metal, sharp metallic ping and rattle, close mic, dry', 1.0, 3, .7),
 ('hit','wood',         'bullet impact splintering wood, close mic, dry', 1.0, 3, .7),
 ('hit','concrete',     'bullet impact on concrete, sharp crack and grit spray, close mic, dry', 1.0, 3, .7),
 ('hit','glass',        'bullet shattering a pane of glass, close mic, dry', 1.4, 3, .7),
 # ---- the player taking damage / effort ----
 ('pain','hit',         'adult man short pained grunt from a body blow, close mic, dry, no music', 1.2, 4, .6),
 ('pain','effort',      'adult man short effort grunt, exertion, close mic, dry, no music', 1.0, 3, .6),
]

# Short player callouts. Charged per character, so these are cheap next to SFX.
VO = [
 # Charlie is an Australian male voice; the lines are written Australian too, so
 # the delivery and the idiom agree instead of an AU accent reading US phrasing.
 ('vo','camera_live',  "Camera's rollin'. Goin' in."),
 ('vo','reloading',    "Reloadin'!"),
 ('vo','last_mag',     "Last mag, mate."),
 ('vo','clear',        "Yeah, clear."),
 ('vo','moving',       "Movin' up."),
 ('vo','contact',      "Contact, front!"),
 ('vo','hit',          "Ah, I'm hit!"),
 ('vo','low_hp',       "Yeah nah, I'm not good. I'm not good."),
 ('vo','survivor',     "Got one. Stay behind us, mate."),
 ('vo','all_survivors',"That's the lot of 'em. Let's go."),
 ('vo','out_front',    "Ride's out front. Go on, move!"),
 ('vo','need_ammo',    "I'm dry! Chuck us a mag!"),
 ('vo','behind_you',   "Behind ya!"),
 ('vo','nice_shot',    "Beauty."),
 ('vo','regroup',      "On me, on me."),
 ('vo','trunk',        "Gear's in the boot."),
 ('vo','driving',      "Couple minutes out, yeah?"),
 ('vo','parked',       "Righto. We're here."),
]

def post(raw, dst):
    """mono, trimmed, peak-normalised - what makes variants sit together"""
    r = subprocess.run(['ffmpeg','-v','error','-y','-i',raw,
        '-af','silenceremove=start_periods=1:start_silence=0.02:start_threshold=-50dB,'
              'areverse,silenceremove=start_periods=1:start_silence=0.05:start_threshold=-50dB,areverse,'
              'loudnorm=I=-18:TP=-1.5:LRA=11',
        '-ac','1','-b:a','96k', dst], capture_output=True, text=True)
    if r.returncode != 0:
        subprocess.run(['ffmpeg','-v','error','-y','-i',raw,'-ac','1','-b:a','96k',dst], check=False)

def post_vo(raw, dst):
    subprocess.run(['ffmpeg','-v','error','-y','-i',raw,
        '-af','loudnorm=I=-16:TP=-1.5:LRA=11','-ac','1','-b:a','96k', dst], check=False)

def req(url, payload, K):
    body = json.dumps(payload).encode()
    r = urllib.request.Request(url, data=body, headers={
        'xi-api-key': K, 'content-type': 'application/json'})
    with urllib.request.urlopen(r, timeout=180) as resp:
        return resp.read()

def main():
    args = sys.argv[1:]
    dry = '--dry' in args
    only = None
    if '--only' in args:
        only = set(args[args.index('--only')+1].split(','))
    os.makedirs(OUT, exist_ok=True)
    K = key()
    jobs = []
    for fam, name, prompt, secs, n, infl in SFX:
        if only and fam not in only: continue
        for i in range(1, n+1):
            jobs.append(('sfx', f'{fam}_{name}_{i}', prompt, secs, infl))
    for fam, name, text in VO:
        if only and fam not in only: continue
        jobs.append(('tts', f'{fam}_{name}', text, 0, 0))
    todo = [j for j in jobs if not os.path.exists(os.path.join(OUT, j[1]+'.mp3'))]
    print(f'{len(jobs)} clips defined, {len(jobs)-len(todo)} already on disk, {len(todo)} to generate')
    if dry:
        for j in todo: print('  would generate', j[1])
        return
    ok = fail = 0
    for k, (kind, fid, text, secs, infl) in enumerate(todo, 1):
        dst = os.path.join(OUT, fid + '.mp3')
        raw = dst + '.raw'
        try:
            if kind == 'sfx':
                data = req(SFX_URL, {'text': text, 'duration_seconds': secs,
                                     'prompt_influence': infl}, K)
            else:
                data = req(TTS_URL, {'text': text, 'model_id': 'eleven_turbo_v2_5',
                                     'voice_settings': {'stability': .45, 'similarity_boost': .75}}, K)
            open(raw, 'wb').write(data)
            (post_vo if kind == 'tts' else post)(raw, dst)
            os.remove(raw)
            sz = os.path.getsize(dst)
            ok += 1
            print(f'  [{k}/{len(todo)}] {fid:28s} {sz/1024:6.1f} KB')
        except urllib.error.HTTPError as e:
            body = e.read()[:200].decode('utf8', 'replace')
            fail += 1
            print(f'  [{k}/{len(todo)}] {fid:28s} HTTP {e.code}: {body}')
            if e.code in (401, 402, 403):
                print('  !! auth/quota problem - stopping'); break
            if e.code == 429:
                print('  rate limited, backing off 20s'); time.sleep(20)
        except Exception as e:
            fail += 1
            print(f'  [{k}/{len(todo)}] {fid:28s} ERROR {e}')
        time.sleep(0.35)
    print(f'done: {ok} generated, {fail} failed')

if __name__ == '__main__':
    main()
