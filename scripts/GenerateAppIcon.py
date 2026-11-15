"""Generate an original opaque app icon using only Python's standard library."""
from pathlib import Path
import json, math, struct, zlib
N = 1024
BG = (6, 12, 20)
pixels = bytearray(bytes(BG) * (N * N))
def span(y, x0, x1, color):
    if 0 <= y < N:
        x0, x1 = max(0, int(x0)), min(N, int(x1))
        if x1 > x0:
            start = (y * N + x0) * 3
            pixels[start:start + (x1-x0)*3] = bytes(color) * (x1-x0)
def polygon(points, color):
    for y in range(max(0, int(min(p[1] for p in points))), min(N, int(max(p[1] for p in points))+1)):
        hits = []
        for a,b in zip(points, points[1:]+points[:1]):
            if (a[1] <= y < b[1]) or (b[1] <= y < a[1]):
                hits.append(a[0] + (y-a[1])*(b[0]-a[0])/(b[1]-a[1]))
        hits.sort()
        for a,b in zip(hits[0::2],hits[1::2]): span(y, math.ceil(a), math.ceil(b), color)
def circle(cx, cy, radius, color):
    for y in range(max(0,cy-radius), min(N,cy+radius+1)):
        dx = math.sqrt(max(0, radius*radius-(y-cy)**2))
        span(y, math.ceil(cx-dx), math.floor(cx+dx)+1, color)
for p in range(128,897,128):
    for y in range(80,945): span(y,p,p+3,(18,46,56))
    for y in range(p,p+3): span(y,80,945,(18,46,56))
polygon([(512,108),(916,512),(512,916),(108,512)],(51,224,209))
polygon([(512,140),(884,512),(512,884),(140,512)],BG)
points=[(295,345),(402,665),(512,475),(622,665),(729,345)]
for a,b in zip(points,points[1:]):
    dx,dy=b[0]-a[0],b[1]-a[1]; length=math.hypot(dx,dy)
    nx,ny=-dy/length*32,dx/length*32
    polygon([(a[0]+nx,a[1]+ny),(b[0]+nx,b[1]+ny),(b[0]-nx,b[1]-ny),(a[0]-nx,a[1]-ny)],(244,250,252))
for x,y in points: circle(x,y,32,(244,250,252))
circle(512,790,34,(255,171,56))
def chunk(kind,data):
    return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
raw=b''.join(b'\0'+pixels[y*N*3:(y+1)*N*3] for y in range(N))
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',N,N,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b'')
root=Path(__file__).resolve().parents[1]/'App'/'Assets.xcassets'
directory=root/'AppIcon.appiconset';directory.mkdir(parents=True,exist_ok=True)
(directory/'AppIcon.png').write_bytes(png)
(root/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}),encoding='utf-8')
(directory/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}}),encoding='utf-8')
print(f'Original RGB icon generated: {len(png)} bytes; 1024x1024; no alpha.')
