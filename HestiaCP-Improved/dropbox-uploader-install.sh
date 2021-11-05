cd /  #cd to main dir
mkdir dropbox
cd dropbox
curl "https://raw.githubusercontent.com/andreafabrizi/Dropbox-Uploader/master/dropbox_uploader.sh" -o dropbox_uploader.sh
chmod 755 dropbox_uploader.sh
./dropbox_uploader.sh
