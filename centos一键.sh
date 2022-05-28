#!/bin/bash 
systemctl stop firewalld.service
systemctl disable firewalld.service
yum -y install curl
yum -y install wget 
yum -y install fuse
yum -y install screen
bash <(wget -qO- https://git.io/gclone.sh)
wget 
wget https://downloads.plex.tv/plex-media-server-new/1.26.2.5797-5bd057d2b/redhat/plexmediaserver-1.26.2.5797-5bd057d2b.x86_64.rpm
