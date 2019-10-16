import json
import sys

if __name__ == '__main__':
	data = sys.stdin.read()
	f = json.loads(data)
	app = f["outputs"]["app_external_ip"]["value"]
	db = f["outputs"]["db_external_ip"]["value"]
	out = {'app': {'hosts': [str(app)]}, 
		'db': {'hosts': [str(db)]}}
	sys.stdout.write(json.dumps(out))
