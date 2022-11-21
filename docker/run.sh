#!/bin/bash

#
# die <message>
# Print an error message and exit with error status
#
die () {
    echo "ERROR: $*"
    exit 1
}

#
# require <var>
# Throw an error if the specified VAR isn't set
#
require () {
    [ -z "${!1}" ] && die "Missing required environment variable: ${1}"
}

require SSH_PRIVATE_KEY
require GITLAB_API_URL
require GITLAB_API_TOKEN
require GITLAB_SSH_HOST

mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keyscan -H banner-src.ellucian.com >>~/.ssh/known_hosts
ssh-keyscan -H $GITLAB_SSH_HOST >>~/.ssh/known_hosts
chmod 600 ~/.ssh/known_hosts

echo "$SSH_PRIVATE_KEY" >~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa

cat >/mirror/mirror.conf <<EOF
mirror:
    root: /mirror-data
    ssh_key: ~/.ssh/id_rsa
gitlab:
    url: $GITLAB_API_URL
    token: $GITLAB_API_TOKEN
skip:
  - banner/apps/banner_student_success_api
  - banner/plugins/banner_finaid_validation
EOF

ruby /mirror/ellucian_git_mirror.rb /mirror/mirror.conf
