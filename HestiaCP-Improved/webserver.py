
"""
TEST:
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"filepath":"/home/mystery/Desktop/tmp/python/hello-world.py","args":[]}' \
  http://127.0.0.1:5001

NOTE:
-) if this gets hacked we should consider using real python webserver like flask, web.py, gunicorn? will it have permission based like php to run its code?
https://help.pythonanywhere.com/pages/

web.py **
https://stackoverflow.com/q/10457346


Known issue: 
-) [Errno 98] Address already in use, best solution is to continue retrying until you can gain a connection again
https://stackoverflow.com/a/6380198
"""

import http.server
import socketserver
import json
import subprocess
import os
import threading
import socket

IP = "127.0.0.1"
#PORT = 8080
PORT = 5001

class SimpleHTTPRequestHandler(http.server.BaseHTTPRequestHandler):

    def run_script(self, filepath, args=None):
        if not os.path.exists(filepath):
            return f"Error: The file '{filepath}' does not exist."
        #command = ['/usr/bin/python3', filepath]
        command = ['sudo', '-u', 'restrictedpy', '/usr/bin/python3', filepath] #by now we should already run this script in non-root, but we keep enforcing it just to make sure
        if args:
            # Ensure each argument is properly quoted using shlex.quote()
            command.extend(shlex.quote(arg) for arg in args)
        result = subprocess.run(command, capture_output=True, text=True, shell=False)
        if result.returncode != 0:
            return result.stderr
        else:
            return result.stdout

    def do_GET(self):
        if self.path == '/shutdown':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'Server shutting down...')
            
            def shutdown_server(server):
                server.shutdown()
                server.server_close()  # This will close the socket

            # Shut down the server
            #threading.Thread(target=self.server.shutdown).start()
            #threading.Thread(target=shutdown_server, args=(self.server,)).start()
            threading.Thread(target=shutdown_server, args=(self.server,), daemon=True).start()
        else:
            self.send_response(200) #we must always return 200, so monit will know its up, we cant use 404 because monit will treat it as fail
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'Hello')

    def do_POST(self):
        # Get the length of the data
        content_length = int(self.headers['Content-Length'])
        # Read the data
        post_data = self.rfile.read(content_length)
        
        # Parse the JSON data
        result = "Error: Unknown"
        try:
            parsed_data = json.loads(post_data.decode('utf-8'))
            filepath = parsed_data.get('filepath', "")  # default value = ""
            args = parsed_data.get('args', None)
            result = self.run_script(filepath, args)
        except json.JSONDecodeError:
            result = "Error: Invalid JSON"

        #construct response
        response = {
            "result": str(result)
        }

        # Send response status code
        self.send_response(200)
        # Send headers
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        # Send the JSON response
        self.wfile.write(json.dumps(response).encode('utf-8'))


"""
with socketserver.TCPServer((IP, PORT), SimpleHTTPRequestHandler, bind_and_activate=False) as httpd:

    #to fix: [Errno 98] Address already in use" in this script, doesnt work. https://gist.github.com/andreif/10dff6a3dedb0206f35f92f626894134
    httpd.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    httpd.server_bind()
    httpd.server_activate()

    print(f"Serving on port {PORT}")
    server_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    server_thread.start()
    server_thread.join()
    #httpd.serve_forever()
"""

with socketserver.ThreadingTCPServer((IP, PORT), SimpleHTTPRequestHandler, bind_and_activate=False) as httpd:

    #to fix: [Errno 98] Address already in use" in this script, doesnt work. https://gist.github.com/andreif/10dff6a3dedb0206f35f92f626894134
    httpd.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    httpd.server_bind()
    httpd.server_activate()

    print(f"Serving on port {PORT}")
    httpd.serve_forever()
