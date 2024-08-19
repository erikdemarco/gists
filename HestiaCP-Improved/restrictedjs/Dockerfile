FROM denoland/deno:alpine

# The port that your application listens to.
EXPOSE 5002

#deno default
WORKDIR /app
USER deno

ADD --chmod=755 https://raw.githubusercontent.com/erikdemarco/gists/main/HestiaCP-Improved/restrictedjs/app.ts .

# These steps will be re-run upon each file change in your working directory:
COPY . .

# Compile the main app so that it doesn't need to be compiled each startup/entry.
RUN deno cache app.ts

CMD ["run", "--allow-net", "app.ts"]
