import sys
import os
import glob
import shutil

if len(sys.argv) != 3:
    print(f"Usage: python {sys.argv[0]} <source_pattern> <destination>")
    print(f'Example: python {sys.argv[0]} "C:\\Users\\tarun\\Desktop\\*abc*.txt" "D:\\Archive"')
    sys.exit(1)

source = sys.argv[1]
dest = sys.argv[2]

os.makedirs(dest, exist_ok=True)

files = glob.glob(source)
files = [f for f in files if os.path.isfile(f)]

if not files:
    print(f"No files found matching: {source}")
    sys.exit(0)

print(f"Found {len(files)} file(s). Moving to {dest} ...")
for f in files:
    shutil.move(f, dest)
    print(f"  {os.path.basename(f)}")

print("Done.")