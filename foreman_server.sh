#!/bin/bash

# PUPPETMASTER is the fqdn that needs to be resolvable by clients.
# Change if needed

# start with a subscribed RHEL6 box.  hint:
#    subscription-manager register
#    subscription-manager subscribe --auto
yum install -y yum-utils yum-rhn-plugin

rpm -Uvh http://download.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
yum-config-manager --enable rhel-6-server-optional-rpms

# install puppetlabs repo
yum -y install https://yum.puppetlabs.com/el/6/products/x86_64/puppetlabs-release-6-7.noarch.rpm
yum clean all

# install dependent packages
yum install -y augeas puppet git policycoreutils-python

# enable ip forwarding
sudo sysctl -w net.ipv4.ip_forward=1
sudo sed -i 's/net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/g' /etc/sysctl.conf

# disable selinux in /etc/selinux/config
# TODO: selinux policy
setenforce 0

# Set PuppetServer
export PUPPETMASTER=puppet.example.com
augtool -s set /files/etc/puppet/puppet.conf/agent/server $PUPPETMASTER

# Puppet Plugins
augtool -s set /files/etc/puppet/puppet.conf/main/pluginsync true

# TODO: correctly configure iptables
service iptables stop

workdir=/root
pushd $workdir

# Get foreman-installer modules
git clone --recursive https://github.com/theforeman/foreman-installer.git $workdir/foreman-installer -b 1.1.1

# Install Foreman
puppet apply --verbose -e "include puppet, puppet::server, passenger, foreman_proxy, foreman" --modulepath=$workdir/foreman-installer

popd

# Configure defaults, host groups, proxy, etc
sed -i "s/foreman_hostname/$(hostname)/s" foreman-params.json
ruby foreman-setup.rb proxy

# install puppet modules
mkdir -p /etc/puppet/modules/production
cp -r puppet/* /etc/puppet/modules/production/
pushd /usr/share/foreman 
RAILS_ENV=production rake puppet:import:puppet_classes[batch]
popd

ruby foreman-setup.rb globals
ruby foreman-setup.rb hostgroups

export PUPPETMASTER=$(hostname)

# write client-register-to-foreman script
# TODO don't hit yum unless packages are not installed
cat >/tmp/foreman_client.sh <<EOF

# start with a subscribed RHEL6 box
rpm -Uvh http://download.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
rpm -Uvh https://yum.puppetlabs.com/el/6/products/x86_64/puppetlabs-release-6-7.noarch.rpm
yum-config-manager --enable rhel-6-server-optional-rpms
yum clean all

# install dependent packages
yum install -y augeas puppet git policycoreutils-python

# Set PuppetServer
augtool -s set /files/etc/puppet/puppet.conf/agent/server $PUPPETMASTER

# Puppet Plugins
augtool -s set /files/etc/puppet/puppet.conf/main/pluginsync true

# check in to foreman
puppet agent --test

/etc/init.d/puppet start
EOF

echo "Foreman is installed and almost ready for setting up your OpenStack"
echo "First, you need to input a few parameters into foreman."
echo "Visit https://$(hostname)/common_parameters"
echo ""
echo "Then copy /tmp/foreman_client.sh to your openstack client nodes"
echo "Run that script and visit the HOSTS tab in foreman. Pick CONTROLLER"
echo "host group for your controller node and COMPUTE host group for the rest"
echo ""
echo "Once puppet runs on the machines, OpenStack is ready!"