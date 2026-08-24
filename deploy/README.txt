DEAD AISLE — deployable build
=============================

This folder is self-contained. Upload the WHOLE folder; do not rename anything.

  index.html              the game (entry point)
  assets/kill-voice.mp3   voice line on every kill
  assets/vo-deploy.mp3    "Remember lads, subscribe to PewDiePie."  (on park)
  assets/vo-win.mp3       "We made it out. GG chat."                (on win)
  assets/radio-song.m4a   car radio, toggled with E
  assets/hostile-1..7.mp3 hostile shouts - one is assigned to each attacker
                          at spawn, played only within 20 m of the player
                          with a squared distance falloff
  assets/hostile-v1..6.mp3 hostile REACTION lines - played when one takes a
                          round, or the moment it first spots you. Same 20 m
                          cutoff and squared falloff, plus a 0.7 s cooldown
                          across all hostiles so they never talk over
                          each other.
  assets/sfx-gunshot.mp3  every rifle shot (pitch varied +/-5%)
  assets/sfx-player-hit.mp3   you take a hit
  assets/sfx-breath.mp3   layered over the synthesised breathing when you are
                          sprinting or under ~55 HP
  assets/sfx-step-in.mp3  footstep bed, hard floor - loops while you move
                          inside the store, rate 0.72 walking / 1.0 sprinting
  assets/sfx-step-out.mp3 footstep bed, asphalt - same, used in the lot and
                          on the street
  assets/sfx-enemy-scream.mp3 a hostile taking a round (45% of hits; the other
                          55% get one of the hostile-v lines)
  assets/sfx-body-drop.mp3    the body landing, once per kill, distance-scaled

Every recorded one-shot falls back to the built-in synthesised sound if its
file is missing, so a partial upload degrades rather than going silent.

Total ~7.7 MB.


AUDIO CONTROLS
--------------
  M   mute / unmute everything
  N   mute / unmute the park track only (independent of M)
  E   car radio, during the drive


DEPLOY TO EDGEONE PAGES
-----------------------
CLI (edgeone 1.6.21 is already installed globally). Note the "pages"
subcommand is a deprecated alias now — use "makers":

    edgeone login
    cd /Users/sam/Desktop/testtt
    edgeone makers deploy dist

Or in the EdgeOne console: create a project of the "Direct upload" type and
drop this dist folder in. There is no build step — it is plain static files.
An existing project must be of the direct-upload type for CLI deploys.

Build output directory : .        (this folder is already the output)
Build command          : (leave empty)
Entry point            : index.html


SERVER REQUIREMENTS
-------------------
None beyond static file serving. No build, no Node, no environment variables,
no API keys. Make sure the host serves these MIME types (EdgeOne does by
default):

    .html  text/html
    .mp3   audio/mpeg
    .m4a   audio/mp4

The page pulls three.js r160 from unpkg.com over HTTPS, so the host must allow
outbound CDN requests from the browser (any normal static host is fine).


NO SECRETS IN THIS BUILD
------------------------
The ElevenLabs API key that used to be embedded in the page has been removed.
All spoken lines are pre-rendered into assets/*.mp3, so nothing calls the API
at runtime and there is nothing to leak when this folder is public.

If the old key was ever pushed anywhere public, rotate it at
elevenlabs.io > Profile > API Keys.


REGENERATING THE VOICE LINES
----------------------------
The lines were rendered with ElevenLabs voice "Charlie" (Australian male,
id IKne3meq5aSn9XLyUdCD) using model eleven_turbo_v2_5. To change a line,
re-render it and overwrite the matching mp3 — no code changes needed.

Note: free ElevenLabs plans cannot use Voice Library voices via the API
(HTTP 402). Premade voices such as Charlie work fine.


PLAYING LOCALLY
---------------
Open index.html directly in Chrome. Everything works from file:// too —
the character model is embedded in the page as base64, and the audio files
load as siblings.
