#!/bin/bash
clear
echo "#############################################################"
echo "# Install ocserv for Debian or Ubuntu (32bit/64bit)"
echo "# Intro: http://www.tennfy.com"
echo "#"
echo "# Author: tennfy <admin@tennfy.com>"
echo "#"
echo "#############################################################"
echo ""
# Check if user is root
if [ $(id -u) != "0" ]; then
    printf "Error: You must be root to run this script!\n"
    exit 1
fi

# add source
	dv=$(cut -d. -f1 /etc/debian_version)
	if [ "$dv" = "7" ]; then
	echo "deb http://http.debian.net/debian wheezy-backports main" >> /etc/apt/sources.list
	elif [ "$dv" = "6" ]; then
    echo -e 'deb http://http.debian.net/debian-backports squeeze-backports(-sloppy) main' >> /etc/apt/sources.list
	fi
# update source
apt-get update

# install packges
dv=$(cut -d. -f1 /etc/debian_version)
	if [ "$dv" = "7" ]; then
	apt-get -t wheezy-backports install libgnutls28-dev
	elif [ "$dv" = "6" ]; then
    apt-get -t squeeze-backports install libgnutls28-dev
	fi
	
#install other packges
apt-get install libgmp3-dev m4 gcc pkg-config make gnutls-bin build-essential libwrap0-dev libpam0g-dev libdbus-1-dev libreadline-dev libnl-route-3-dev libprotobuf-c0-dev libpcl1-dev libopts25-dev autogen libseccomp-dev liblz4-dev git build-essential -y

#ssl certificate

#download ocserv and compile
wget ftp://ftp.infradead.org/pub/ocserv/ocserv-0.9.0.1.tar.xz
tar xf ocserv-0.10.6.tar.xz
rm ocserv-0.10.6.tar.xz
cd ocserv-0.10.6
./configure --prefix=/usr --sysconfdir=/etc --enable-linux-namespaces
make && make install

#generate CA key
certtool --generate-privkey --outfile ca-key.pem
cat << _EOF_ >ca.tmpl
	cn = "VPN CA"
	organization = "Big Corp"
	serial = 1
	expiration_days = 9999
	ca
	signing_key
	cert_signing_key
	crl_signing_key
_EOF_
 
certtool --generate-self-signed --load-privkey ca-key.pem --template ca.tmpl --outfile ca-cert.pem
 
certtool --generate-privkey --outfile server-key.pem
cat << _EOF_ >server.tmpl 
	cn = "www.example.com"
	organization = "MyCompany"
	expiration_days = 9999
	signing_key
	encryption_key
	tls_www_server
_EOF_
 
certtool --generate-certificate --load-privkey server-key.pem --load-ca-certificate ca-cert.pem --load-ca-privkey ca-key.pem --template server.tmpl --outfile server-cert.pem

cp ca-cert.pem /etc/ssl/certs
cp ca-key.pem /etc/ssl/private
cp server-cert.pem /etc/ssl/certs
cp server-key.pem /etc/ssl/private

#download and config ocserv
mkdir /etc/ocserv 



cd /etc/ocserv

mkdir defaults
cat << _EOF_ >/etc/ocserv/defaults/group.conf
	route = 0.0.0.0/128.0.0.0
	route = 128.0.0.0/128.0.0.0
_EOF_

mkdir config-per-group
cd config-per-group
wget https://github.com/rankjie/anyconnect-gfw-list/raw/master/gfwiplist.txt -O routed

#add user and password
ocpasswd -g global,routed -c /etc/ocserv/ocpasswd tennfy

#set autostart
wget https://gist.github.com/kevinzhow/9661623/raw/9d2c80e7a86eed514165bf7c9fce777bfe775f37/ocserv -O /etc/init.d/ocserv
chmod 755 /etc/init.d/ocserv
update-rc.d ocserv defaults

#permmit forward
sed -i 's/#net\.ipv4\.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p

#set iptables
if [ -f /proc/user_beancounters ] || [ -d /proc/bc ]; then
    INTERFACE=venet0
else
    INTERFACE=eth0
fi

iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -o $INTERFACE -j MASQUERADE
iptables -A FORWARD -s 192.168.10.0/24 -j ACCEPT

sed -i 's/exit\ 0/#exit\ 0/' /etc/rc.local
echo iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -o $INTERFACE -j MASQUERADE >> /etc/rc.local
echo iptables -A FORWARD -s 192.168.10.0/24 -j ACCEPT >> /etc/rc.local
echo exit 0 >> /etc/rc.local