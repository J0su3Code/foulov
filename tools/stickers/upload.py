import os, sys, boto3, concurrent.futures as cf
from botocore.config import Config
env = dict(l.split('=',1) for l in open(os.path.expanduser('~/.foulov-r2.env')).read().split('\n') if '=' in l)
s3 = boto3.client('s3', endpoint_url=env['R2_ENDPOINT'], aws_access_key_id=env['R2_KEY'], aws_secret_access_key=env['R2_SECRET'], region_name='auto', config=Config(signature_version='s3v4', max_pool_connections=16))
root = sys.argv[1]; B = 'foulove-stickers'
have = set()
for page in s3.get_paginator('list_objects_v2').paginate(Bucket=B, Prefix='v1/'):
    have |= {o['Key'] for o in page.get('Contents', [])}
files = []
for d, _, fs in os.walk(os.path.join(root, 'v1')):
    for f in fs:
        k = os.path.relpath(os.path.join(d, f), root)
        if k.endswith('index.json'): continue
        if k not in have: files.append(k)
def up(k):
    s3.upload_file(os.path.join(root, k), B, k, ExtraArgs={'ContentType': 'image/webp', 'CacheControl': 'public, max-age=31536000, immutable'})
with cf.ThreadPoolExecutor(16) as ex:
    list(ex.map(up, files))
# L'index en dernier : il n'annonce que des fichiers déjà en place.
s3.upload_file(os.path.join(root, 'v1', 'index.json'), B, 'v1/index.json', ExtraArgs={'ContentType': 'application/json', 'CacheControl': 'no-cache'})
n = sum(1 for p in s3.get_paginator('list_objects_v2').paginate(Bucket=B, Prefix='v1/') for _ in p.get('Contents', []))
print('déposés :', len(files), '; total dans le seau :', n)
