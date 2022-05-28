#!/bin/bash
systemctl stop firewalld.service
systemctl disable firewalld.service
yum -y install curl
yum -y install wget 
yum -y install fuse
yum -y install screen
yum -y install tar
bash <(wget -qO- https://git.io/gclone.sh)
wget https://raw.githubusercontent.com/chiron688/linux_jobs/master/rclone.config
mv rclone.config /root/.config/rclone/
cd /mnt
mkdir dianyingag dianyinghn dianyingot dianyinguz dongman guochanju jilupian oumeiju rihanju zhuigeng
gclone mount dianyingag:/ /mnt/dianyingag --config /root/.config/rclone/rclone.conf --vfs-cache-mode writes --use-mmap --daemon-timeout=10m --vfs-read-chunk-size 10M --vfs-read-chunk-size-limit 512M --cache-dir /home/rclone/vfs_cache --allow-other --drive-chunk-size 128M --log-level INFO --log-file /var/log/rclone.log --timeout 1h --umask 002 --daemon
gclone mount dianyinghn:/ /mnt/dianyinghn --config /root/.config/rclone/rclone.conf --vfs-cache-mode writes --use-mmap --daemon-timeout=10m --vfs-read-chunk-size 10M --vfs-read-chunk-size-limit 512M --cache-dir /home/rclone/vfs_cache --allow-other --drive-chunk-size 128M --log-level INFO --log-file /var/log/rclone.log --timeout 1h --umask 002 --daemon
gclone mount dianyingot:/ /mnt/dianyingot --config /root/.config/rclone/rclone.conf --vfs-cache-mode writes --use-mmap --daemon-timeout=10m --vfs-read-chunk-size 10M --vfs-read-chunk-size-limit 512M --cache-dir /home/rclone/vfs_cache --allow-other --drive-chunk-size 128M --log-level INFO --log-file /var/log/rclone.log --timeout 1h --umask 002 --daemon
gclone mount dianyinguz:/ /mnt/dianyinguz --config /root/.config/rclone/rclone.conf --vfs-cache-mode writes --use-mmap --daemon-timeout=10m --vfs-read-chunk-size 10M --vfs-read-chunk-size-limit 512M --cache-dir /home/rclone/vfs_cache --allow-other --drive-chunk-size 128M --log-level INFO --log-file /var/log/rclone.log --timeout 1h --umask 002 --daemon
gclone mount dongman:/ /mnt/dongman --config /root/.config/rclone/rclone.conf --vfs-cache-mode writes --use-mmap --daemon-timeout=10m --vfs-read-chunk-size 10M --vfs-read-chunk-size-limit 512M --cache-dir /home/rclone/vfs_cache --allow-other --drive-chunk-size 128M --log-level INFO --log-file /var/log/rclone.log --timeout 1h --umask 002 --daemon
gclone mount guochan:/ /mnt/guochanju --config /root/.config/rclone/rclone.conf --vfs-cache-mode writes --use-mmap --daemon-timeout=10m --vfs-read-chunk-size 10M --vfs-read-chunk-size-limit 512M --cache-dir /home/rclone/vfs_cache --allow-other --drive-chunk-size 128M --log-level INFO --log-file /var/log/rclone.log --timeout 1h --umask 002 --daemon
gclone mount jilupian:/ /mnt/jilupian --config /root/.config/rclone/rclone.conf --vfs-cache-mode writes --use-mmap --daemon-timeout=10m --vfs-read-chunk-size 10M --vfs-read-chunk-size-limit 512M --cache-dir /home/rclone/vfs_cache --allow-other --drive-chunk-size 128M --log-level INFO --log-file /var/log/rclone.log --timeout 1h --umask 002 --daemon
gclone mount oumei:/ /mnt/oumeiju --config /root/.config/rclone/rclone.conf --vfs-cache-mode writes --use-mmap --daemon-timeout=10m --vfs-read-chunk-size 10M --vfs-read-chunk-size-limit 512M --cache-dir /home/rclone/vfs_cache --allow-other --drive-chunk-size 128M --log-level INFO --log-file /var/log/rclone.log --timeout 1h --umask 002 --daemon
gclone mount rihan:/ /mnt/rihanju --config /root/.config/rclone/rclone.conf --vfs-cache-mode writes --use-mmap --daemon-timeout=10m --vfs-read-chunk-size 10M --vfs-read-chunk-size-limit 512M --cache-dir /home/rclone/vfs_cache --allow-other --drive-chunk-size 128M --log-level INFO --log-file /var/log/rclone.log --timeout 1h --umask 002 --daemon
gclone mount zhuigeng:/ /mnt/zhuigeng --config /root/.config/rclone/rclone.conf --vfs-cache-mode writes --use-mmap --daemon-timeout=10m --vfs-read-chunk-size 10M --vfs-read-chunk-size-limit 512M --cache-dir /home/rclone/vfs_cache --allow-other --drive-chunk-size 128M --log-level INFO --log-file /var/log/rclone.log --timeout 1h --umask 002 --daemon
cd /root 
wget https://downloads.plex.tv/plex-media-server-new/1.26.2.5797-5bd057d2b/redhat/plexmediaserver-1.26.2.5797-5bd057d2b.x86_64.rpm
rpm -ivh plexmediaserver-1.26.2.5797-5bd057d2b.x86_64.rpm
cd /var/lib
rm -rf plexmediaserver
screen glcone copy gerenpan:/backen/plex.tar.gz /var/lib -P
screen tar –xzf plex.tar.gz
mv /var/lib/var/lib/plexmediaserver /var/lib

