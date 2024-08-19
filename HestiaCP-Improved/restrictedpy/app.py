"""
TEST:
curl -X POST -H "Content-Type: application/json" -d @- http://127.0.0.1:5001 << EOF
{"code": "print(f\"Arguments: {args['name']}\")", "args": {"name": "Alice"}}
EOF

"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import multiprocessing
import sys
import io

def execute_code_with_timeout(code="", args={}, timeout=30):

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

    def target_func(code, args, output_queue):
        try:

            # Redirect stdout to capture print statements
            output = io.StringIO()
            sys.stdout = output

            # Execute the code in a restricted global namespace, sys is required in exec
            exec(code, get_restricted_globals(), {'args': args})

            # Send the captured output to the queue
            output_queue.put(output.getvalue())
        except Exception as e:
            output_queue.put(f"Error: {e}")
        finally:
            sys.stdout = sys.__stdout__  # Restore stdout

    # Create a Queue to capture output
    output_queue = multiprocessing.Queue()

    # Create a new process to run the target function
    process = multiprocessing.Process(target=target_func, args=(code, args, output_queue))

    # Start the process
    process.start()

    # Wait for the process to finish, with a timeout
    process.join(timeout)

    # Terminate the process if it's still running
    if process.is_alive():
        process.terminate()
        process.join()
        return "" #Timeout reached

    # Get the output from the Queue
    if not output_queue.empty():
        result = output_queue.get().strip()  # Strip trailing newlines
    else:
        result = ""

    return result



class SimpleHTTPRequestHandler(BaseHTTPRequestHandler):

    def do_POST(self):
        # Get the content length to read the data
        content_length = int(self.headers['Content-Length'])
        # Read the posted data
        post_data = self.rfile.read(content_length)
        
        # Parse the JSON data
        try:
            json_data = json.loads(post_data)
            code = json_data.get('code', "")
            args = json_data.get('args', {})
            result = execute_code_with_timeout(code, args)

            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(result.encode('utf-8'))

        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b'Invalid JSON data.')

    #turn off logging
    def log_message(self, format, *args):
        return

httpd = HTTPServer(('0.0.0.0', 5001), SimpleHTTPRequestHandler) #docker
#httpd = HTTPServer(('127.0.0.1', 5001), SimpleHTTPRequestHandler) #standalone
httpd.serve_forever()
