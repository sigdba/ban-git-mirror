%define __requires_exclude /usr/bin/ruby

%define buildcode  %{getenv:BUILD_CODE}

Name:     xe_mirror
Version:  %buildcode
Release:  1%{?dist}
Requires: libffi,openssl,readline,zlib,git
Summary:  XE Mirror Script
URL:      http://sigcorp.com
License:  Direct

Source0: https://cache.ruby-lang.org/pub/ruby/2.3/ruby-2.3.3.tar.bz2

%description
Ellucian mirror script with embedded Ruby

%prep
%autosetup -n ruby-2.3.3

%build
rm -rf "$RPM_BUILD_ROOT"
./configure --prefix=/opt/xe_mirror/ruby   \
			--disable-install-doc          \
			--disable-install-rdoc
%make_build

%install
%make_install
ln -sf ${RPM_BUILD_ROOT}/opt/xe_mirror /opt/xe_mirror
${RPM_BUILD_ROOT}/opt/xe_mirror/ruby/bin/gem install net-ssh:2.9.2 git:1.2.9 gitlab:4.5.0
%{buildroot}/opt/xe_mirror/ruby/bin/gem install net-ssh:2.9.2 git:1.2.9 gitlab:4.5.0
rm -f /opt/xe_mirror %{buildroot}/opt/xe_mirror/xe_mirror
cp ${CODEBUILD_SRC_DIR}/ellucian_git_mirror.rb ${RPM_BUILD_ROOT}/opt/xe_mirror
cp ${CODEBUILD_SRC_DIR}/mirror_conf.example.yml ${RPM_BUILD_ROOT}/opt/xe_mirror/mirror_conf.yml
mkdir -p ${RPM_BUILD_ROOT}/lib/systemd/system
cp ${CODEBUILD_SRC_DIR}/rpm/xe_mirror_systemd.service ${RPM_BUILD_ROOT}/lib/systemd/system/xe_mirror.service

%files
/opt/xe_mirror
/lib/systemd/system/xe_mirror.service

%post
useradd -M -s /bin/bash mirror || echo "mirror user already exists"
mkdir -p ~mirror/.ssh
chmod 700 ~mirror/.ssh
ssh-keyscan banner-src.ellucian.com localhost >>~mirror/.ssh/known_hosts
echo "StrictHostKeyChecking no" >>~mirror/.ssh/config
chmod 600 ~mirror/.ssh/*
chown -R mirror ~mirror/.ssh
chown mirror ~mirror
which systemctl && echo "Enabling xe_mirror systemd service" && systemctl enable xe_mirror.service || echo "systemctl not present, not enabling service"
