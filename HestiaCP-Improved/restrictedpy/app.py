"""
TEST:
curl -X POST -H "Content-Type: application/json" -d @- http://127.0.0.1:5001 << EOF
{"code": "print(f\"Arguments: {args['name']}\")", "args": {"name": "Alice"}}
EOF

"""

import json
import os
import signal
from flask import Flask, request, jsonify
import io
import contextlib
import multiprocessing
import builtins

app = Flask(__name__)


def execute_code_with_timeout(code, args={}, timeout=30):
    result_queue = multiprocessing.Queue()
    def target():
        result = execute_code(code, args)
        result_queue.put(result)
    process = multiprocessing.Process(target=target)
    process.start()
    process.join(timeout)
    if process.is_alive():
        process.terminate()
        process.join()  # Ensure process termination
        raise TimeoutError(f"Code execution exceeded the {timeout}-second time limit.")
    if not result_queue.empty():
        return result_queue.get()
    else:
        return "No result returned."


def execute_code(code_snippet, args={}):

    def get_restricted_globals():
        restricted_functions = ['exec', 'eval']
        restricted_modules = ['os', 'subprocess']
        restricted_globals = {}
        for name in dir(__builtins__):
            if name not in restricted_functions and not name.startswith('__'):
                restricted_globals[name] = getattr(__builtins__, name)
        def restricted_import(name, globals=None, locals=None, fromlist=(), level=0):
            if name in restricted_modules:
                raise ImportError(f"Importing '{name}' is not allowed")
            return __import__(name, globals, locals, fromlist, level)
        restricted_globals['__builtins__'] = {
            name: getattr(__builtins__, name) for name in dir(__builtins__)
            if name not in restricted_functions
        }
        restricted_globals['__builtins__']['__import__'] = restricted_import
        return restricted_globals

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
            result = execute_code_with_timeout(code, args)
        except json.JSONDecodeError:
            result = "Error: Invalid JSON"
        except Exception as e:
            result = str(e)

        # construct response
        #response = { "result": str(result) }; response = jsonify(response)
        response = str(result)
        
        return response


@app.route('/shutdown', methods=['GET'])
def shutdown():
    print("Shutting down server...")
    os.kill(os.getpid(), signal.SIGTERM)
    return "Server is shutting down..."

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=False, use_debugger=False, use_reloader=False) #docker
    #app.run(host="127.0.0.1", port=5001, debug=False, use_debugger=False, use_reloader=False) #standalone
