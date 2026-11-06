"""Install only the Godot 4.5.1 web export template (no threads, release) without downloading
the whole 1.35 GB .tpz: reads the zip directory and the two entries with HTTP byte ranges.

Usage: python3 tools/fetch_web_template.py
Then:  godot --headless --path . --export-release "Web" /tmp/webbuild/index.html
"""
import os, struct, zlib, requests

URL = "https://github.com/godotengine/godot/releases/download/4.5.1-stable/Godot_v4.5.1-stable_export_templates.tpz"
WANT = ("templates/version.txt", "templates/web_nothreads_release.zip")
DEST = os.path.expanduser("~/.local/share/godot/export_templates/4.5.1.stable")

def main():
    s = requests.Session()
    head = s.head(URL, allow_redirects=True)
    real, size = head.url, int(head.headers["Content-Length"])
    def get(a, b):
        r = s.get(real, headers={"Range": "bytes=%d-%d" % (a, b)})
        r.raise_for_status()
        return r.content
    tail = get(size - 65536, size - 1)
    i = tail.rfind(b"PK\x05\x06")
    cd_size, cd_off = struct.unpack("<2L", tail[i + 12:i + 20])
    cd = get(cd_off, cd_off + cd_size - 1)
    os.makedirs(DEST, exist_ok=True)
    p = 0
    while p < len(cd):
        (meth,) = struct.unpack("<H", cd[p + 10:p + 12])
        csz, = struct.unpack("<L", cd[p + 20:p + 24])
        fl, el, cl = struct.unpack("<3H", cd[p + 28:p + 34])
        (off,) = struct.unpack("<L", cd[p + 42:p + 46])
        name = cd[p + 46:p + 46 + fl].decode()
        p += 46 + fl + el + cl
        if name not in WANT:
            continue
        h = get(off, off + 29)
        lfl, lel = struct.unpack("<2H", h[26:30])
        data = get(off + 30 + lfl + lel, off + 30 + lfl + lel + csz - 1)
        raw = zlib.decompress(data, -15) if meth == 8 else data
        with open(os.path.join(DEST, os.path.basename(name)), "wb") as f:
            f.write(raw)
        print("installed", name, len(raw))

if __name__ == "__main__":
    main()
