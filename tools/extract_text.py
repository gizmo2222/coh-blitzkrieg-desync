"""Extract the human-readable files from the Blitzkrieg data archives into ./extracted/<archive>/.
Also dumps one RGD so its chunk layout can be inspected.
Run from the repo root:  python -I tools/extract_text.py ["<game folder>"]
The game folder is the argument, else $env:COH_GAME, else the default Steam library.
"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from sga import SGA

GAME = (sys.argv[1] if len(sys.argv) > 1 else os.environ.get("COH_GAME")
        or r"C:\Program Files (x86)\Steam\steamapps\common\Company of Heroes Relaunch")
G = os.path.join(GAME, "Blitzkrieg", "Archives")
if not os.path.isdir(G):
    sys.exit(f"No Blitzkrieg archives at {G}. Pass the game folder: python -I tools/extract_text.py \"D:\\SteamLibrary\\steamapps\\common\\Company of Heroes Relaunch\"")
TEXT = ('.lua', '.scar', '.ai', '.txt', '.ini', '.xml', '.bak', '.ucs', '.cfg', '.nis', '.squadai', '.gd', '.copy')
OUT = 'extracted'

def extract(archive, pred):
    a = SGA(f"{G}/{archive}.sga"); n = 0
    for p, doff, clen, ulen, st in a.entries():
        if pred(p):
            dst = os.path.join(OUT, archive, p)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, 'wb') as f:
                f.write(a.read(doff, clen, ulen, st))
            n += 1
    print(archive, 'extracted', n)

extract('BKData', lambda p: p.lower().endswith(TEXT))
extract('BKDataPatch', lambda p: p.lower().endswith(TEXT))
extract('BKAttrib', lambda p: not p.lower().endswith('.rgd'))
extract('BKAttribPatch', lambda p: not p.lower().endswith('.rgd'))
extract('BKAttribPatch', lambda p: p == 'attrib/abilities/allied_apcbc_shell.rgd')

# inspect the sample RGD
p = os.path.join(OUT, 'BKAttribPatch', 'attrib/abilities/allied_apcbc_shell.rgd')
b = open(p, 'rb').read()
print('rgd size', len(b))
print('head', b[:48])
# walk Relic Chunky chunks
off = 36 if b.startswith(b'Relic Chunky') else 0
import struct
def walk(off, end, depth=0):
    while off + 24 <= end:
        kind, id_, ver, size, nlen = struct.unpack_from('<4s4sIII', b, off)
        name = b[off+20:off+20+nlen]
        print('  '*depth + f'{kind.decode()} {id_.decode()} v{ver} size={size} name={name[:40]!r}')
        body = off + 20 + nlen
        if kind == b'FOLD':
            walk(body, body + size, depth+1)
        off = body + size
walk(off, len(b))
# show the printable strings in the DATA chunk to see whether key names are embedded
import re
strs = re.findall(rb'[ -~]{4,}', b)
print('strings:', [s.decode() for s in strs[:60]])
