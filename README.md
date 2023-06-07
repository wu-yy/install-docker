1.查看是否存在docker用户组
cat /etc/group |grep docker

如果没有就添加一个
groupadd docker
2.添加用户到docker分组
addgroup xingxing docker

3.查看用户的分组
groups xingxing

4.用户如果还是没有权限，可以尝试重新登陆是否解决


QA：
sudo chmod 666 /var/run/docker.sock
