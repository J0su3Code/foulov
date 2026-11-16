"""Télécharge les éléments CC0 de Poly Haven utilisés par intro_garden.py (sol, herbe, fougères, éclairages HDRI).

Ils ne sont pas stockés dans git : ce script les récupère à l'identique.
Usage : python3 fetch_assets.py
"""
import json, os, urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'assets')
MODELS = ['brown_mud_leaves_01', 'grass_medium_01', 'fern_02']
HDRIS = ['epping_forest_01', 'dikhololo_night']
UA = {'User-Agent': 'foulov-asset-fetch'}


def get_json(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA)) as r:
        return json.load(r)


def jobs():
    for a in MODELS:
        d = get_json(f'https://api.polyhaven.com/files/{a}')['blend']['2k']['blend']
        yield d['url'], os.path.join(ROOT, a, os.path.basename(d['url']))
        for rel, inc in d.get('include', {}).items():
            yield inc['url'], os.path.join(ROOT, a, rel)
    for a in HDRIS:
        u = get_json(f'https://api.polyhaven.com/files/{a}')['hdri']['2k']['hdr']['url']
        yield u, os.path.join(ROOT, 'hdri', os.path.basename(u))


def fetch(job):
    url, path = job
    if os.path.exists(path):
        return path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA)) as r, open(path, 'wb') as f:
        f.write(r.read())
    return path


if __name__ == '__main__':
    with ThreadPoolExecutor(8) as ex:
        done = list(ex.map(fetch, list(jobs())))
    print(len(done), 'fichiers dans', ROOT)
