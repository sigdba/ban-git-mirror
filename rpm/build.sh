#!/bin/bash

# yum install -y wget rpm-build rpmdevtools redhat-rpm-config gcc git libffi-devel openssl-devel readline-devel zlib-devel bzip2

RUBY_NAME="ruby-2.3.3"
RUBY_SRC_FILE="${RUBY_NAME}.tar.bz2"
RUBY_SRC_URL="https://cache.ruby-lang.org/pub/ruby/2.3/${RUBY_SRC_FILE}"
RUBY_SRC_SHA1="a8db9ce7f9110320f33b8325200e3ecfbd2b534b"

INST_BASE=/opt/xe_mirror
RUBY_HOME=${INST_BASE}/ruby
RUBY_BIN=${RUBY_HOME}/bin

rpmdev-setuptree
echo '%_topdir %(echo $HOME)/rpmbuild' > ~/.rpmmacros

# copy spec into SPECS

cd ~/rpmbuild/SPECS
spectool -g xe_mirror.spec
rpmbuild -v -bb xe_mirror.spec

wget ${RUBY_SRC_URL}

tar xjf ${RUBY_SRC_FILE}
cd $RUBY_NAME

./configure --prefix=${RUBY_HOME}    \
			--disable-install-doc    \
			--disable-install-rdoc

make
make install

${RUBY_BIN}/gem install net-ssh:2.9.2 git:1.2.9 gitlab:4.5.0
