mkdir /tempdocker && cd /tempdocker
curl -O https://raw.githubusercontent.com/erikdemarco/gists/main/HestiaCP-Improved/restrictedpy/Dockerfile
sudo docker build --tag app-restrictedpy .
docker run -d --memory=256m --cpus="1" --restart always --name app-restrictedpy -p 127.0.0.1:5001:5001 app-restrictedpy
cd / && rm -r /tempdocker
