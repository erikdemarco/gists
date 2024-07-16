import web
import json
import subprocess
import os

urls = (
    '/', 'index',
    '/shutdown', 'shutdown'
)

app = web.application(urls, globals())


def run_script(filepath, args=None):
    if not os.path.exists(filepath):
        return f"Error: The file '{filepath}' does not exist."
    #command = ['su', 'restrictedpy', '-c', 'python3', filepath]
    command = ['sudo', '-u', 'restrictedpy', 'python3', filepath]
    if args:
        # Ensure each argument is properly quoted using shlex.quote()
        command.extend(shlex.quote(arg) for arg in args)
    result = subprocess.run(command, capture_output=True, text=True, shell=False)
    if result.returncode != 0:
        return result.stderr
    else:
        return result.stdout

class index:
    def GET(self):
        return ""

    def POST(self):

        try:
            data = json.loads(web.data())
            filepath = data.get('filepath', "")
            args = data.get('args', [])
            result = run_script(filepath, args)
        except json.JSONDecodeError:
            result = "Error: Invalid JSON"
        except Exception as e:
            result = str(e)

        #construct response
        response = {
            "result": str(result)
        }

        return json.dumps(response)

class shutdown:
    def GET(self):
        print("Shutting down server...")
        app.stop()

if __name__ == "__main__":
    server = web.httpserver.runsimple(app.wsgifunc(), ("127.0.0.1", 5001))
    #app.run() #to run via custom socket use: /usr/bin/python3 /usr/local/bin/webpy.py 127.0.0.1:5001
