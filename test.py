import json
import os
import socket
from pprint import pprint

s = socket.socket(socket.AF_UNIX)
s.connect(os.environ["XDG_RUNTIME_DIR"] + "/miti.sock")
s.sendall(b"today -j\n")
temp = s.makefile().read()
output = json.loads(temp)
pprint(output)
