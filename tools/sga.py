"""Minimal reader for Relic SGA v4 archives (Company of Heroes 1).
Usage:
  python sga.py list  <archive.sga> [filter]
  python sga.py cat   <archive.sga> <path-inside-archive>
  python sga.py x     <archive.sga> <outdir> [filter]
"""
import struct, sys, zlib, os

def read_cstr(buf, off):
    end = buf.index(b'\0', off)
    return buf[off:end].decode('latin-1')

class SGA:
    def __init__(self, path):
        self.path = path
        with open(path, 'rb') as f:
            self.hdr = f.read(184)
            magic, ver, prod = struct.unpack_from('<8sHH', self.hdr, 0)
            assert magic == b'_ARCHIVE', magic
            self.version = ver
            self.hdr_size, self.data_off = struct.unpack_from('<II', self.hdr, 172)
            # v4 has one more uint32 (platform) after data_off; data header starts at 184
            self.base = 184 if ver >= 4 else 180
            f.seek(self.base)
            dh = f.read(self.hdr_size)
        self.dh = dh
        (toc_off, toc_cnt, dir_off, dir_cnt, file_off, file_cnt, str_off, str_cnt) = \
            struct.unpack_from('<IHIHIHIH', dh, 0)
        self.tocs = []
        for i in range(toc_cnt):
            o = toc_off + i*138
            alias, name, d0, d1, f0, f1, dstart = struct.unpack_from('<64s64sHHHHH', dh, o)
            self.tocs.append((alias.split(b'\0')[0].decode(), name.split(b'\0')[0].decode(), d0, d1, f0, f1, dstart))
        self.dirs = []
        for i in range(dir_cnt):
            o = dir_off + i*12
            n, sd0, sd1, sf0, sf1 = struct.unpack_from('<IHHHH', dh, o)
            self.dirs.append((read_cstr(dh, str_off + n), sd0, sd1, sf0, sf1))
        self.files = []
        self.fe_size = 22 if ver >= 4 else 20
        for i in range(file_cnt):
            o = file_off + i*self.fe_size
            if ver >= 4:
                n, doff, clen, ulen, mtime, stype = struct.unpack_from('<IIIIIH', dh, o)
            else:
                n, flags, doff, clen, ulen = struct.unpack_from('<IIIII', dh, o); stype = flags >> 8; mtime = 0
            self.files.append((read_cstr(dh, str_off + n), doff, clen, ulen, stype))
        # map file index -> directory path
        self.file_dir = {}
        for dname, sd0, sd1, sf0, sf1 in self.dirs:
            for fi in range(sf0, sf1):
                self.file_dir[fi] = dname
    def entries(self):
        for i, (name, doff, clen, ulen, stype) in enumerate(self.files):
            d = self.file_dir.get(i, '')
            yield (d + '/' + name if d else name).replace(chr(92), '/'), doff, clen, ulen, stype
    def read(self, doff, clen, ulen, stype):
        with open(self.path, 'rb') as f:
            f.seek(self.data_off + doff)
            raw = f.read(clen)
        if stype == 0 or (clen == ulen and not raw.startswith(b'x')):
            return raw
        return zlib.decompress(raw)

if __name__ == '__main__':
    cmd, path = sys.argv[1], sys.argv[2]
    a = SGA(path)
    if cmd == 'list':
        flt = sys.argv[3].lower() if len(sys.argv) > 3 else ''
        print(f'# version {a.version}, tocs {a.tocs[:1]}, dirs {len(a.dirs)}, files {len(a.files)}')
        for p, doff, clen, ulen, st in a.entries():
            if flt in p.lower():
                print(f'{ulen:>10} {st} {p}')
    elif cmd == 'cat':
        want = sys.argv[3].lower().replace(chr(92), '/')
        for p, doff, clen, ulen, st in a.entries():
            if p.lower() == want:
                sys.stdout.buffer.write(a.read(doff, clen, ulen, st)); break
        else:
            sys.exit('not found')
    elif cmd == 'x':
        out = sys.argv[3]; flt = sys.argv[4].lower() if len(sys.argv) > 4 else ''
        n = 0
        for p, doff, clen, ulen, st in a.entries():
            if flt in p.lower():
                dst = os.path.join(out, p)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                with open(dst, 'wb') as f: f.write(a.read(doff, clen, ulen, st))
                n += 1
        print(f'extracted {n} files to {out}')
