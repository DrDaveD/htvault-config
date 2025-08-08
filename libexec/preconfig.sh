#!/bin/bash
# Create vault.hcl from template, and do any other cluster-wide configuration
#   that needs to be done as root.
#
# This source file is Copyright (c) 2021, FERMI NATIONAL
#   ACCELERATOR LABORATORY.  All rights reserved.

LIBEXEC=/usr/libexec/htvault-config
VARLIB=/var/lib/htvault-config
cd $VARLIB

CLUSTERFILES="`grep -H ^cluster: /etc/htvault-config/config.d/*.yaml|cut -d: -f1`"
if $LIBEXEC/parseconfig.py $CLUSTERFILES >preconfig.json.new; then
    if [ -f preconfig.json ]; then
        mv preconfig.json preconfig.json.old
    fi
    mv preconfig.json.new preconfig.json
    if $LIBEXEC/jsontobash.py <preconfig.json >preconfig.bash.new; then
        if [ -f preconfig.bash ]; then
            mv preconfig.bash preconfig.bash.old
        fi
        mv preconfig.bash.new preconfig.bash
    else
        echo "Failure converting preconfig.json to preconfig.bash" >&2
        exit 1
    fi
else
    echo "Failure converting $CLUSTERFILES to preconfig.json" >&2
    exit 1
fi
. ./preconfig.bash

if [ -n "$_cluster_master" ]; then
    TMPLTYPE=raft
else
    TMPLTYPE=single
fi
MYNAME="${_cluster_myname:-`uname -n`}"

if [ -f vault.hcl ]; then
    mv vault.hcl vault.hcl.old
fi
cat $LIBEXEC/vault.common.template $LIBEXEC/vault.$TMPLTYPE.template \
    | sed -e "s,<myfqdn>,$MYNAME," \
        -e "s,<clusterfqdn>,$_cluster_master," \
        -e "s,<peer1fqdn>,$_cluster_peer1," \
        -e "s,<peer2fqdn>,$_cluster_peer2," \
        >vault.hcl

if [ -n "$_cluster_auditlog" ]; then
    # if it doesn't exist, make the directory of the auditlog
    AUDITDIR="${_cluster_auditlog%/*}"
    if [ ! -d $AUDITDIR ]; then
        mkdir -p $AUDITDIR
        chmod 750 $AUDITDIR
    fi
    # Handle the transition from older packages when the service was run
    # under the vault user instead of the openbao user.  Be careful to
    # handle the case where the auditlog was in a shared directory.
    find $AUDITDIR -maxdepth 0 -user vault | xargs -r chown openbao
    find ${_cluster_auditlog}* ! -user openbao | xargs -r chown openbao:openbao
fi
