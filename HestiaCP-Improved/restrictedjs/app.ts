async function exec_with_timeout(code = "", args = {}, timeout = 30000){

  const workerCode = `
      'use strict';
      setTimeout(() => {
          self.close();
      }, ${timeout});
      const exec_code = ${exec_code.toString()};
      const result = await exec_code(${JSON.stringify(code)}, ${JSON.stringify(args)});
      self.postMessage(result);
      self.close();
  `;

  const blobUrl = `data:application/javascript;base64,${btoa(workerCode)}`;
  const worker = new Worker(blobUrl, {type: "module"});

  return new Promise((resolve, reject) => {
      worker.onmessage = (event) => {
        resolve(event.data);
      };
      worker.onerror = (error) => {
        reject(error);
      };
      worker.onmessageerror = (error) => {
        reject(error);
      }
    });

}


async function exec_code(code = "", args = {}) {

  const buffer = [];
  const originalConsoleLog = console.log;
  console.log = (...args) => {
    buffer.push(...args);
  };

  try {
    // Wrap the code in an async function to allow the use of await
    const wrappedCode = `(async () => {
      const args = ${JSON.stringify(args)};
      ${code}
    })();`;

    // Evaluate the wrapped code
    await eval(wrappedCode);
  } catch (e) {
      buffer.push(e.toString());
  } finally {
      console.log = originalConsoleLog;
  }

  return buffer.join('\n').trim();
}




const handler = async (request: Request): Promise<Response> => {
  if (request.method === "POST") {
    try {
      const body = await request.json();
      const code = body.code ?? "";
      const args = body.args ?? {};
      const result = await exec_with_timeout(code, args, 30000);

      return new Response(result), {
        status: 200,
        headers: { "Content-Type": "text/plain" },
      });

    } catch (error) {
      return new Response("Invalid JSON", { status: 400 });
    }
  } else {
    return new Response("Method Not Allowed", { status: 405 });
  }
};

Deno.serve({ port: 5002, hostname: "0.0.0.0" }, handler);
