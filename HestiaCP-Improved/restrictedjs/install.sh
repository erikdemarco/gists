mkdir /tempdocker && cd /tempdocker
curl -O https://raw.githubusercontent.com/erikdemarco/gists/main/HestiaCP-Improved/restrictedjs/Dockerfile
sudo docker build --tag app-restrictedjs .
docker run -d --memory=256m --restart always --name app-restrictedjs -p 127.0.0.1:5002:5002 app-restrictedjs
cd / && rm -r /tempdocker
