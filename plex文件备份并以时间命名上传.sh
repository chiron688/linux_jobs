#!/bin/bash 
#打开文件夹
cd /var/lib
#压缩plexmediaserver，就是plex的数据存储文件夹
zip -r plexmediaserver.zip plexmediaserver
#上传到谷歌云盘，前提是必须用gclone挂载好
#gclone mount gerenpan:/ /media/backen --allow-other --attr-timeout 30m --vfs-cache-mode full --vfs-cache-max-age 6h --vfs-cache-max-size 3G --vfs-read-chunk-size-limit 3G --buffer-size 100M --daemon
#gclone mount：是gclone挂载命令
#gerenpan:/ ：上面已经提到，提前配置好google Drive，并将名称命名为gerenpan，gerenpan:/则是google Drive上的路径
#//home/backen:为本地文件夹路径（建议为空目录）
#--allow-other：指的是允许非当前Rclone用户外的用户进行访问
#--attr-timeout 5m：文件属性缓存，（大小，修改时间等）的时间。如果小鸡配置比较低，建议适当提高这个值，避免过多的和内核交互，占用资源。
#-vfs-cache-mode full：开启VFS文件缓存，这样可减少Rclone与API交互，同时可提高文件读写效率
#--vfs-cache-max-age 6h：VFS文件缓存时间，这里设置的6小时，如果文件很少更改，建议设置更长的时间
#--vfs-cache-max-size 3G：VFS文件缓存上限大小，建议不超过当前空余磁盘的50%
#vfs-read-chunk-size-limit 3G：分块读取大小，这里设置的是3G，可提高文件读的效率，比如1G的文件，大致分为10个块进行读取，但与此同时API请求次数也会增多
#--buffer-size 100M：内存缓存，如果您内存比较小，可降低此值，如果内存比较大，可适当提高
#--daemon：指后台方式运行
#上传命令，上传到指定文件夹并以上传时间进行保存
gclone move /var/lib/plexmediaserver.zip /media/backen/backen/$(date +%Y-%m-%d)plex数据备份 --transfers 32 -P
cd /home
#压缩文件夹
zip -r guazaiwenjian.zip /home/
gclone move /var/lib/plexmediaserver.zip /media/backen/backen/$(date +%Y-%m-%d)挂载文件备份 --transfers 32 -P
