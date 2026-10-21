# DEAD AISLE

A single-file browser FPS built on three.js r160. Drive a Brabus S-Class into
town, park at TOPS, and get four survivors out of the store alive — shot
through a bodycam filter.

## Layout

    dead-aisle.html   the whole game: markup, CSS and every system
    assets/           models, textures and audio the page fetches at runtime
    deploy/README.txt hosting notes that ship inside dist/
    build.sh          assembles dist/ (index.html + assets)
    screenshots/      promo captures

`dist/` is generated, not tracked. Run `./build.sh` to rebuild it.

## Running it

Open `dead-aisle.html` directly, or serve the folder:

    python3 -m http.server 8765

three.js is pulled from unpkg, so the browser needs network access on first
load. Everything else is local.

## Deploying

`./deploy.sh` builds and publishes to GitHub Pages (the `gh-pages` branch),
live at https://uhrichsam4.github.io/dead-aisle/

For any other static host, `./build.sh` then upload `dist/`. See
`deploy/README.txt` for EdgeOne Pages specifics.

## Multiplayer

Peer-to-peer over WebRTC. The host simulates the world and broadcasts
snapshots; clients send their transform and their hit events. Connection
offers go through PeerJS's public broker — after that, traffic is direct
between players. No server of ours is involved, which is why it runs on
static hosting.

## Controls

    WASD      move / drive          R      reload
    Mouse     aim                   SHIFT  sprint
    LMB       fire                  F      pick up / throw
    RMB       aim down sights       E      car radio (during the drive)
    1/2/3/Q   weapons               M      mute      N  music only
