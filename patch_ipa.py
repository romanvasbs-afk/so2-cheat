import lief, sys, os, zipfile, shutil, tempfile

def fail(m):
    print("ERROR:", m); sys.exit(1)

src, dylib, bundle, dst = sys.argv[1:5]
for p in (src, dylib, bundle):
    if not os.path.exists(p): fail("missing " + p)

tmp = tempfile.mkdtemp()
with zipfile.ZipFile(src) as z:
    z.extractall(tmp)
    infos = z.infolist()

app = os.path.join(tmp, "Payload", "Standoff2.app")
if not os.path.isdir(app): fail("no Payload/Standoff2.app - wrong IPA")

fw = os.path.join(app, "Frameworks")
os.makedirs(fw, exist_ok=True)
shutil.copy(dylib, os.path.join(fw, os.path.basename(dylib)))
shutil.copytree(bundle, os.path.join(fw, "chams.bundle"), dirs_exist_ok=True)

exe_name = "Standoff2"
import plistlib
with open(os.path.join(app, "Info.plist"), "rb") as f:
    exe_name = plistlib.load(f).get("CFBundleExecutable", exe_name)
exe = os.path.join(app, exe_name)

targets = [exe, os.path.join(app, "Frameworks", "UnityFramework.framework", "UnityFramework")]
link = "@executable_path/Frameworks/" + os.path.basename(dylib)

done = False
for t in targets:
    if not os.path.exists(t): continue
    try:
        b = lief.MachO.parse(t).at(0)
        if b.has_encryption_info:
            fail(t + " is still encrypted - get a decrypted IPA")
        if any(c.name == link for c in b.libraries):
            print("already injected:", t); done = True; break
        b.add_library(link)
        b.remove_signature()
        b.write(t)
        print("injected into", os.path.basename(t))
        done = True
        break
    except Exception as e:
        print("retry next target:", t, "->", e)

if not done: fail("injection failed on every target (no header space?)")

# rezip, keep Payload/ as root, store symlinks
out = zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED, compresslevel=1)
for root, dirs, files in os.walk(tmp):
    for f in files:
        full = os.path.join(root, f)
        arc = os.path.relpath(full, tmp)
        st = os.lstat(full)
        if os.path.islink(full):
            zi = zipfile.ZipInfo(arc)
            zi.external_attr = (st.st_mode & 0xFFFF) << 16
            out.writestr(zi, os.readlink(full))
        else:
            out.write(full, arc)
out.close()
shutil.rmtree(tmp)
print("wrote", dst, os.path.getsize(dst) // 1048576, "MB")
