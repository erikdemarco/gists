import json
import subprocess
import shlex
import os
import signal
from flask import Flask, request, jsonify

app = Flask(__name__)

def run_script(filepath, args=None):
    if not os.path.exists(filepath):
        return f"Error: The file '{filepath}' does not exist."
    # command = ['su', 'restrictedpy', '-c', 'python3', filepath]
    command = ['sudo', '-u', 'restrictedpy', 'python3', filepath]
    if args:
        # Ensure each argument is properly quoted using shlex.quote()
        command.extend(shlex.quote(arg) for arg in args)
    result = subprocess.run(command, capture_output=True, text=True, shell=False)
    if result.returncode != 0:
        return result.stderr
    else:
        return result.stdout

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'GET':
        return "Ok"
    elif request.method == 'POST':
        try:
            data = request.get_json()
            filepath = data.get('filepath', "")
            args = data.get('args', [])
            result = run_script(filepath, args)
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
    app.run(host="127.0.0.1", port=5001, debug=True)
