#!/bin/sh

/usr/bin/wget --no-check-certificate -O /root/bin/cvsbckp_install.pl https://mnt.example.ru/pub/cvsbackup/cvsbckp_install.pl 2>/dev/null 

touch /var/run/cvsbackup.trap
touch /boot/loader.conf
[ -d /root/.ssh ] || ( mkdir /root/.ssh && chmod 700 /root/.ssh )


sleep 5

/usr/bin/perl /root/bin/cvsbckp_install.pl
rm -vf /root/bin/cvsbckp_install.pl
rm $0

echo "done"
