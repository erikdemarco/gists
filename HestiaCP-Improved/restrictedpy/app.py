"""
TEST:
curl -X POST -H "Content-Type: application/json" -d @- http://127.0.0.1:5001 << EOF
{"code": "print(f\"Arguments: {args['name']}\")", "args": {"name": "Alice"}}
EOF

php json generator:
$code = <<<EOD
import yfinance as yf
msft = yf.Ticker('MSFT')
msft.info
EOD;
$data = [];
$data['code'] = $code;
$data['args'] = ['name' => 'Alice'];
$encoded = json_encode($data);
print( $encoded );

"""

import json
import os
import signal
from flask import Flask, request, jsonify
import io
import contextlib

app = Flask(__name__)


def execute_code(code_snippet, args={}):

    def get_restricted_globals():
        restricted_functions = ['exec', 'eval']
        restricted_modules = ['os', 'subprocess']
        restricted_globals = {
            '__builtins__': {k: getattr(globals()['__builtins__'], k) for k in dir(globals()['__builtins__']) if k not in restricted_functions},
            '__name__': '__main__',
        }
        def restricted_import(name, globals=None, locals=None, fromlist=(), level=0):
            if name in restricted_modules:
                raise ImportError(f"Importing '{name}' is not allowed")
            return globals()['__builtins__']['__import__'](name, globals, locals, fromlist, level)
        restricted_globals['__builtins__']['__import__'] = restricted_import

    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        try:
            exec(code_snippet, get_restricted_globals(), {'args': args})
        except Exception as e:
            buffer.write(str(e))
    return buffer.getvalue().strip()




@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'GET':
        return "Ok"
    elif request.method == 'POST':
        try:
            data = request.get_json()
            code = data.get('code', "")
            args = data.get('args', {})
            result = execute_code(code, args)
        except json.JSONDecodeError:
            result = "Error: Invalid JSON"
        except Exception as e:
            result = str(e)

        # construct response
        response = {
            "result": str(result)
        }

        return jsonify(response)

@app.route('/shutdown', methods=['GET'])
def shutdown():
    print("Shutting down server...")
    os.kill(os.getpid(), signal.SIGTERM)
    return "Server is shutting down..."

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=False, use_debugger=False, use_reloader=False) #docker
    #app.run(host="127.0.0.1", port=5001, debug=False, use_debugger=False, use_reloader=False) #standalone
