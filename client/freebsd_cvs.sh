#!/bin/sh

fetch -q -o /root/bin/cvsbckp_install.pl https://mnt.example.ru/pub/cvsbackup/cvsbckp_install.pl 2>/dev/null
touch /var/run/cvsbackup.trap
[ -d /root/.ssh ] || ( mkdir /root/.ssh && chmod 700 /root/.ssh )

/usr/bin/perl /root/bin/cvsbckp_install.pl

rm -vf /root/bin/cvsbckp_install.pl
rm $0

echo "done"
