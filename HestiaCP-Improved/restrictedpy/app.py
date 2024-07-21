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
    """
    Executes a Python code snippet with the provided arguments and returns the output as a string.
    
    Args:
        code_snippet (str): The Python code to be executed.
        args (dict, optional): A dictionary of arguments to be used in the code snippet. Defaults to {}.
        
    Returns:
        str: The output of the executed code.
    """
    # Create a buffer to capture the output
    buffer = io.StringIO()
    
    # Redirect stdout to the buffer
    with contextlib.redirect_stdout(buffer):
        try:
            # Execute the code snippet with the provided arguments
            exec(code_snippet, globals(), {'args': args})
        except Exception as e:
            # If an exception occurs, print the error message to the buffer
            buffer.write(str(e))
    
    # Get the output from the buffer and return it as a string
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
