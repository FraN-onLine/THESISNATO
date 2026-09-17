import zipfile, os, shutil

dest = r"C:/Autolab/_godot"
os.makedirs(dest, exist_ok=True)
zpath = r"C:/Users/acer/Downloads/Godot_v4.7-stable_win64.exe.zip"
with zipfile.ZipFile(zpath) as z:
    for info in z.infolist():
        print(info.filename, info.file_size)
        z.extract(info, dest)
print("EXTRACTED ->", dest)
for root, dirs, files in os.walk(dest):
    for f in files:
        print(" ", os.path.join(root, f), os.path.getsize(os.path.join(root, f)))