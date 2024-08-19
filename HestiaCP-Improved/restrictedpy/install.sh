mkdir /tempdocker && cd /tempdocker
curl -O https://raw.githubusercontent.com/erikdemarco/gists/main/HestiaCP-Improved/restrictedpy/Dockerfile
sudo docker build --tag flask-app .
docker run -d --memory=256m --cpus="1" --restart always --name flask-app -p 127.0.0.1:5001:5001 flask-app
cd / && rm -r /tempdocker
