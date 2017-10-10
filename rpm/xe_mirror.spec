Name:     xe_mirror
Version:  2.0
Release:  1%{?dist}
Requires: libffi,openssl,readline,zlib
Summary:  XE Mirror Script
URL:      http://sigcorp.com
License:  Direct

Source0: https://cache.ruby-lang.org/pub/ruby/2.3/ruby-2.3.3.tar.bz2

%define __requires_exclude /usr/bin/ruby

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
${RPM_BUILD_ROOT}/opt/xe_mirror/ruby/bin/gem install net-ssh:2.9.2 git:1.2.9 gitlab:3.7.0
%{buildroot}/opt/xe_mirror/ruby/bin/gem install net-ssh:2.9.2 git:1.2.9 gitlab:3.7.0
rm -f /opt/xe_mirror %{buildroot}/opt/xe_mirror/xe_mirror
cp ${CODEBUILD_SRC_DIR}/ellucian_git_mirror.rb ${RPM_BUILD_ROOT}/opt/xe_mirror
cp ${CODEBUILD_SRC_DIR}/mirror_conf.example.yml ${RPM_BUILD_ROOT}/opt/xe_mirror/mirror_conf.yml

%files
/opt/xe_mirror
