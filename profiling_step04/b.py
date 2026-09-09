import json
for i in range(300000):
  x={'a':i,'b':[1,2,3,4]}
  json.dumps(x)
