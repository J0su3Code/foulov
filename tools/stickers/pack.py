"""Pack FouLove : dédoublonne, allège (sans perte visible), nomme par empreinte, miniatures et index. En parallèle."""
import os, sys, json, hashlib, io
from multiprocessing import Pool
from PIL import Image, ImageSequence
SRC, OUT = sys.argv[1], sys.argv[2]

def work(path):
    raw = open(path, 'rb').read()
    try:
        im = Image.open(io.BytesIO(raw)); n = getattr(im, 'n_frames', 1)
    except Exception:
        return None
    full = raw
    try:
        if n > 1:
            # Animé : gardé tel quel s'il est déjà léger, sinon réduit à 384 px.
            if len(raw) > 300 * 1024:
                frames, durs = [], []
                for fr in ImageSequence.Iterator(im):
                    frames.append(fr.convert('RGBA').resize((384, 384), Image.LANCZOS))
                    durs.append(fr.info.get('duration', 80))
                b = io.BytesIO()
                frames[0].save(b, 'WEBP', save_all=True, append_images=frames[1:], duration=durs, loop=0, quality=60, method=4)
                if len(b.getvalue()) < len(raw): full = b.getvalue()
        elif len(raw) > 60 * 1024 or max(im.size) > 512:
            fr = im.convert('RGBA'); fr.thumbnail((512, 512), Image.LANCZOS)
            b = io.BytesIO(); fr.save(b, 'WEBP', quality=80, method=4)
            if len(b.getvalue()) < len(raw): full = b.getvalue()
        im2 = Image.open(io.BytesIO(full)); im2.seek(0); w, h = im2.size
        t = im2.convert('RGBA'); t.thumbnail((160, 160), Image.LANCZOS)
        tb = io.BytesIO(); t.save(tb, 'WEBP', quality=70, method=4)
    except Exception:
        return None
    sid = hashlib.sha256(full).hexdigest()
    open(os.path.join(OUT, 'v1', sid + '.webp'), 'wb').write(full)
    open(os.path.join(OUT, 'v1', 't', sid + '.webp'), 'wb').write(tb.getvalue())
    return {'id': sid, 'w': w, 'h': h, 'a': 1 if n > 1 else 0, 's': len(full), 't': len(tb.getvalue())}

if __name__ == '__main__':
    os.makedirs(os.path.join(OUT, 'v1', 't'), exist_ok=True)
    seen, paths = set(), []
    # Ordre : d'abord les stickers WhatsApp (les plus utilisés), puis Business, du plus récent au plus ancien.
    for d in ['whatsapp', 'business']:
        fs = [f for f in os.listdir(os.path.join(SRC, d)) if f.endswith('.webp')]
        fs.sort(key=lambda f: os.path.getmtime(os.path.join(SRC, d, f)), reverse=True)
        for f in fs:
            p = os.path.join(SRC, d, f); h = hashlib.sha256(open(p, 'rb').read()).hexdigest()
            if h not in seen: seen.add(h); paths.append(p)
    with Pool(os.cpu_count()) as pool:
        res = [r for r in pool.map(work, paths, chunksize=8) if r]
    out, ids = [], set()
    for r in res:
        if r['id'] in ids: continue
        ids.add(r['id']); out.append({k: r[k] for k in ('id', 'w', 'h', 'a', 's')})
    json.dump({'version': 1, 'stickers': out}, open(os.path.join(OUT, 'v1', 'index.json'), 'w'), separators=(',', ':'))
    print(len(out), 'stickers ; complets', round(sum(r['s'] for r in res)/1e6, 1), 'Mo ; miniatures', round(sum(r['t'] for r in res)/1e6, 1), 'Mo ; animés', sum(r['a'] for r in out))
