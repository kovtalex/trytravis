#!/usr/bin/env python

import json
import sys

if __name__ == '__main__':
  out_str = ""
  try:
    data = sys.stdin.read()
    f = json.loads(data)
    app = f["outputs"]["app_external_ip"]["value"]
    db = f["outputs"]["db_external_ip"]["value"]
    out = {'app': {'hosts': [str(app)]},'db': {'hosts': [str(db)]}}
    out_str = json.dumps(out)
  except:
    pass
  
  sys.stdout.write(out_str)
