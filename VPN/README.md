WAZIUP VPN Server
=================

The Waziup VPN Server serves all Wazigates at http://gateway-id. E.g. http://vpn.waziup.org/gateway-dca632a4dd33294f
The VPN server is hosted on a micro AWS VM. It has a DNS vpn.waziup.org.


Deployment
----------

Install openVPN, following the instructions at:
https://github.com/angristan/openvpn-install

Then install and run Waziup OpenVPN Rest API:
https://github.com/Waziup/openvpn-api/tree/main

Also install NGINX and set the [wazigate.conf](./wazigate.conf) file in the folder /etc/nginx/conf/.

