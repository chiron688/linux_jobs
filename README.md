# linux_jobs
个人自用linux脚本

想到加点什么就加什么

一般都是关于plex 的

还有一些自动运行的脚本类型的

就当作备份了
bbr算法推荐：bash <(curl -Lso- https://git.io/kernel.sh)

编译bbr+fq算法
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf

echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf

sysctl -p

lsmod | grep bbr

使用方法

wget https://raw.githubusercontent.com/chiron688/linux_jobs/master/download.sh && chmod +x download.sh && ./download.sh
