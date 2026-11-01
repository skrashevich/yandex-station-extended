"""Build the Station 1 Spotify bridge and one-file AliceBridge installer."""
from pathlib import Path
import base64, gzip, hashlib, io, json, os, subprocess, tarfile, zipfile

ROOT=Path(__file__).resolve().parent
WORK=Path(os.environ.get('STATION_SPOTIFY_BUILD_DIR',str(ROOT/'tools')))
DIST=ROOT/'dist';DIST.mkdir(exist_ok=True);WORK.mkdir(parents=True,exist_ok=True)
JAVA=Path(os.environ['JAVA_HOME'])/'bin'
SDK=Path(os.environ['ANDROID_SDK_ROOT'])
BT=sorted((SDK/'build-tools').glob('*'),key=lambda p:tuple(int(x) for x in p.name.split('.') if x.isdigit()))[-1]
ANDROID=sorted((SDK/'platforms').glob('android-*/android.jar'),key=lambda p:int(p.parent.name.split('-')[1]))[-1]
R8=Path(os.environ.get('STATION_R8_JAR',str(BT/'lib/d8.jar')))
EXE='.exe' if os.name=='nt' else ''

def run(*args,env=None):subprocess.run([str(a) for a in args],env=env,check=True)
def zip_bytes(items):
    out=io.BytesIO()
    with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED) as z:
        for name,data in sorted(items.items()):
            entry=zipfile.ZipInfo(name,(2000,1,1,0,0,0));entry.compress_type=zipfile.ZIP_DEFLATED;z.writestr(entry,data)
    return out.getvalue()
def classes_jar(folder,target,skip=()):
    target.write_bytes(zip_bytes({p.relative_to(folder).as_posix():p.read_bytes() for p in folder.rglob('*.class') if p.stem not in skip}))
def compile_java(folder,sources):
    folder.mkdir(exist_ok=True)
    run(JAVA/('javac'+EXE),'--release','7','-Xlint:-options','-encoding','UTF-8','-cp',ANDROID,'-d',folder,*sources)
def dex(source,target):
    run(JAVA/('java'+EXE),'-cp',R8,'com.android.tools.r8.D8','--release','--min-api','23','--no-desugaring','--lib',ANDROID,'--output',target,source)

cli=WORK/'cli-classes'
compile_java(cli,[ROOT/'src/SpotifyControl.java',ROOT/'src/SpotifyVoice.java',ROOT/'src/CommandParser.java',ROOT/'Check.java'])
run(JAVA/('java'+EXE),'-cp',str(cli)+os.pathsep+str(ANDROID),'Check')
classes_jar(cli,WORK/'cli-classes.jar',skip=('Check',))
dex(WORK/'cli-classes.jar',WORK/'control-raw.jar')
with zipfile.ZipFile(WORK/'control-raw.jar') as z:
    control=zip_bytes({n:z.read(n) for n in z.namelist()})
(DIST/'control.jar').write_bytes(control)

files={'control.jar':control,
       'boot.sh':(ROOT/'boot.sh').read_bytes(),'control.sh':(ROOT/'control.sh').read_bytes()}
files['files.sha256']=''.join(hashlib.sha256(data).hexdigest()+'  '+name+'\n' for name,data in sorted(files.items())).encode()
out=io.BytesIO()
with tarfile.open(fileobj=out,mode='w',format=tarfile.USTAR_FORMAT) as archive:
    for name,data in sorted(files.items()):
        item=tarfile.TarInfo(name);item.size=len(data);item.mode=0o644;item.mtime=0;archive.addfile(item,io.BytesIO(data))
payload=gzip.compress(out.getvalue(),mtime=0)
pins=json.loads((ROOT/'spotify-release.json').read_text(encoding='utf8'))
encoded=base64.b64encode(payload).decode()
script=(ROOT/'install.template.sh').read_text(encoding='utf8')
script=script.replace('__PAYLOAD_SHA__',hashlib.sha256(payload).hexdigest()).replace('__XAPK_SHA__',pins['sha256'])
script=script.replace('__APK_HASHES__','\n'.join(h+'  '+name for name,h in pins['apks'].items()))
script=script.replace('__PAYLOAD__','\n'.join(encoded[i:i+76] for i in range(0,len(encoded),76)))
assert '__PAYLOAD' not in script
with zipfile.ZipFile(io.BytesIO(control)) as z:
    bytecode=z.read('classes.dex')
    assert b'SwitchVpn' not in bytecode and b'GeoUid' not in bytecode
(ROOT/'install.sh').write_bytes(script.encode('utf8'))
print('One-file installer:',ROOT/'install.sh','SHA256',hashlib.sha256(script.encode('utf8')).hexdigest())
installer=script.encode('utf8')
windows=(ROOT/'install.template.ps1').read_text(encoding='utf8')
windows=windows.replace('__INSTALLER_SHA256__',hashlib.sha256(installer).hexdigest()).replace('__INSTALLER_BASE64__',base64.b64encode(installer).decode())
assert '__INSTALLER_' not in windows
(ROOT/'install.ps1').write_text(windows,encoding='utf-8-sig',newline='\n')
print('Windows installer:',ROOT/'install.ps1')
