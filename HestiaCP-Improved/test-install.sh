
#dropbox backup
read -r -p "Do you want to automated backup to dropbox daily? (needs app key, app secret, access code. to get this information try running 'andreafabrizi/Dropbox-Uploader' from other machine ) [y/N] " vDropboxUploader
if [ $vDropboxUploader == "y" ] || [ $vDropboxUploader == "Y" ]; then
  read -r -p "Please input your dropbox Generated app key: " vDropboxUploaderAppKey
fi
if [ $vDropboxUploader == "y" ] || [ $vDropboxUploader == "Y" ]; then
  read -r -p "Please input your dropbox Generated app secret: " vDropboxUploaderAppSecret
fi
if [ $vDropboxUploader == "y" ] || [ $vDropboxUploader == "Y" ]; then
  read -r -p "Please input your dropbox Generated access token: " vDropboxUploaderAccessToken
fi


if [ $vDropboxUploader == "y" ] || [ $vDropboxUploader == "Y" ]; then
  ##Automate backup to dropbox (START)
  
  greentext "installing dropbox backup..."

  #get the dropbox uploader api
  cd /  #cd to main dir
  mkdir dropbox
  cd dropbox
  curl "https://raw.githubusercontent.com/andreafabrizi/Dropbox-Uploader/master/dropbox_uploader.sh" -o dropbox_uploader.sh
  chmod 755 dropbox_uploader.sh
  echo "$vDropboxUploaderAppKey
  $vDropboxUploaderAppSecret
  $vDropboxUploaderAccessToken
  y" | ./dropbox_uploader.sh

  #download the cron file (vestacp)
  #curl -o dropbox-auto-backup-cron-hestia.sh https://gist.githubusercontent.com/erikdemarco/959e3afc29122634631e59d3e3640333/raw/f58557e0ab474eedd480e145e499de584eed6293/dropbox_auto_backup_cron.sh

  #download the cron file (hestiacp)
  curl -o dropbox-auto-backup-cron-hestia.sh https://raw.githubusercontent.com/erikdemarco/gists/main/HestiaCP-Improved/dropbox-auto-backup-cron-hestia.sh

  #move the cron file for accessiblity & chmod it
  mv dropbox-auto-backup-cron-hestia.sh /bin/
  chmod 755 /bin/dropbox-auto-backup-cron-hestia.sh 



  ##Automate backup to dropbox (END)
fi
