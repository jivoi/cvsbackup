#!/bin/sh
PATH="/bin:/usr/bin:/usr/local/bin:"
ssh -o "StrictHostKeyChecking no" -i /root/.ssh/cvsbackup_dsa $*
