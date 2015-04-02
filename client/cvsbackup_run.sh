#!/bin/sh

[ `/root/bin/wdogc.pl a` != 'accept' ] && exit
[ -f /var/run/cvsbackup.pid ] && exit

export CVSROOT=':ext:cvsbackup@cvsbackup.example.ru/www/cvs'
export CVS_RSH='/root/bin/cvsbackup_ssh.sh'
export HOME='/root'

rm -rfd /var/tmp/cvstmp*

/root/bin/cvsbackup.pl config=/root/bin/.cvsbackup.cf && \
/root/bin/wdogc.pl s
