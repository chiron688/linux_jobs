# linux_jobs

个人自用linux脚本就当作备份了

tiktok 解锁检测：
```shell
wget -O tiktok.sh "https://github.com/chiron688/linux_jobs/blob/main/tiktok.sh" && chmod +x tcpx.sh && ./tcpx.sh
```

bbr算法推荐：
预先准备:
**centos：**

```shell
yum install ca-certificates wget -y && update-ca-trust force-enable
```

**debian/ubuntu：**

```shell
apt-get install ca-certificates wget -y && update-ca-certificates
```

**不卸载内核版本**

```shell

wget -O tcpx.sh "https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh" && chmod +x tcpx.sh && ./tcpx.sh
```

**卸载内核版本**

```shell
wget -O tcp.sh "https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcp.sh" && chmod +x tcp.sh && ./tcp.sh
```

**双持bbr+锐速**
bbr 添加

```shell
echo "net.core.default_qdisc=fq" >> /etc/sysctl.d/99-sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-sysctl.conf
sysctl -p
```

编辑锐速文件

```shell
nano /appex/etc/config
```

检测代码有BUG，如果锐速正常 运行查看

```shell
bash /appex/bin/lotServer.sh status | grep "LotServer"
```

检查bbr 内核默认bbr算法不会有输出

```shell
lsmod | grep bbr
```

检查centos安装内核

```shell
grubby --info=ALL|awk -F= '$1=="kernel" {print i++ " : " $2}'
```

查看当前支持TCP算法

```shell
cat /proc/sys/net/ipv4/tcp_allowed_congestion_control
```

查看当前运行的算法

```shell
cat /proc/sys/net/ipv4/tcp_congestion_control
```

查看当前队列算法

```shell
sysctl net.core.default_qdisc
```

命令：

```shell
uname -a
```

作用： 查看系统内核版本号及系统名称

命令：

```shell
 cat /proc/version
```

作用： 查看目录"/proc"下version的信息，也可以得到当前系统的内核版本号及系统名称

编译bbr+fq算法

```shell
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
lsmod | grep bbr
```
