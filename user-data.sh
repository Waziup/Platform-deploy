#!/bin/bash
set -x

# 1. Update packages & install Certbot, Cronie, and Python Pip
dnf update -y
dnf install -y certbot cronie python3-pip

# Enable and start cron service for certificate renewals
systemctl enable --now cronie

# Install Certbot IONOS DNS plugin
pip3 install certbot-dns-ionos --break-system-packages || pip3 install certbot-dns-ionos

# 2. Retrieve Instance ID and AWS Region via IMDSv2
TOKEN=$(curl -s -S -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -s -S -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -S -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)

# 3. Retrieve IONOS INI text directly from AWS Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id "org/waziup/ionos-credentials" \
  --region "$REGION" \
  --query SecretString \
  --output text > /root/ionos-credentials.ini

chmod 600 /root/ionos-credentials.ini

# 4. Reattach Elastic IP
aws ec2 associate-address --instance-id "$INSTANCE_ID" --allocation-id eipalloc-61f3b74f --allow-reassociation --region "$REGION"

# 5. Attach instance to ECS cluster
echo ECS_CLUSTER=waziup-frontend >> /etc/ecs/ecs.config
echo ECS_BACKEND_HOST= >> /etc/ecs/ecs.config

# 6. Install and configure OpenVPN
curl -fsSL https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh \
  -o /usr/local/sbin/openvpn-install
chmod 700 /usr/local/sbin/openvpn-install
/usr/local/sbin/openvpn-install install \
  --endpoint vpn.waziup.org \
  --client waziup \
  --no-color \
  --log /var/log/openvpn-install.log

# 7. Issue HTTP Standalone SSL Certificates (all waziup.io and related domains)
mkdir -p /var/www/html/.well-known/acme-challenge/

certbot certonly \
  --cert-name waziup.io \
  --email contact@waziup.org \
  --standalone \
  --webroot-path /var/www/html \
  --agree-tos \
  --non-interactive \
  -d waziup.io \
  -d www.waziup.io \
  -d api.waziup.io \
  -d keycloak.waziup.io \
  -d dashboard.waziup.io \
  -d login.waziup.io \
  -d remote.waziup.io \
  -d diy.waziup.io \
  -d install.waziup.io \
  -d waziup.org \
  -d www.waziup.org \
  -d forum.waziup.io \
  -d downloads.waziup.io \
  -d lab.waziup.io \
  -d innotec21.de -d www.innotec21.de \
  -d osirris.waziup.io -d osirris.waziup.org \
  -d kijanibox.eu -d www.kijanibox.eu \
  -d kijanicooling.eu -d www.kijanicooling.eu \
  -d kijanispace.eu -d www.kijanispace.eu \
  -d majiup.com -d www.majiup.com \
  -d app.wazilab.io

# 8. Issue IONOS DNS-01 SSL Certificates (porai.ai & *.porai.ai)
certbot certonly \
  --cert-name porai.ai \
  --email contact@waziup.org \
  --authenticator dns-ionos \
  --dns-ionos-credentials /root/ionos-credentials.ini \
  --dns-ionos-propagation-seconds 900 \
  --server https://acme-v02.api.letsencrypt.org/directory \
  --agree-tos \
  --non-interactive \
  --rsa-key-size 4096 \
  -d 'porai.ai' -d '*.porai.ai'

# Notify after a successful certificate renewal and reload the tagged Nginx container
cat > /usr/local/sbin/certbot-renewal-hook.sh <<'EOF'
#!/bin/bash
set -u

CERTIFICATE_PATH=/etc/letsencrypt/live/$1/cert.pem
TOKEN=$(curl -s -S -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -s -S -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -S -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)

RELOAD_OUTPUT=""
if ! CONTAINERS=$(docker container ls --quiet --filter label=cerbot-renewal-target 2>&1); then
  RELOAD_OUTPUT="Docker container lookup failed: ${CONTAINERS}"
elif [ -z "$CONTAINERS" ]; then
  RELOAD_OUTPUT="No running Docker container was found with label cerbot-renewal-target."
else
  for container_id in $CONTAINERS; do
    reload_result=$(docker exec "$container_id" nginx -s reload 2>&1)
    reload_status=$?
    if [ "$reload_status" -eq 0 ]; then
      RELOAD_OUTPUT="${RELOAD_OUTPUT}Container ${container_id}: nginx reload succeeded\n${reload_result}\n"
    else
      RELOAD_OUTPUT="${RELOAD_OUTPUT}Container ${container_id}: nginx reload failed (exit ${reload_status})\n${reload_result}\n"
    fi
  done
fi

CERTIFICATE_EXPIRY=$(openssl x509 -enddate -noout -in "$CERTIFICATE_PATH" | sed 's/^notAfter=//')
MIME_BOUNDARY="waziup-renewal-${INSTANCE_ID}-$(date +%s)"
RAW_EMAIL=/tmp/waziup-certificate-renewal-email.eml
{
  printf 'From: no-reply@waziup.org\r\n'
  printf 'To: contact@waziup.org\r\n'
  printf 'Cc: corentin.dupont@waziup.org, johann.forster@waziup.org\r\n'
  printf 'Subject: Certificate renewal succeeded for %s\r\n' "$CERT_NAME"
  printf 'MIME-Version: 1.0\r\n'
  printf 'Content-Type: multipart/mixed; boundary="%s"\r\n\r\n' "$MIME_BOUNDARY"
  printf -- '--%s\r\n' "$MIME_BOUNDARY"
  printf 'Content-Type: text/plain; charset=UTF-8\r\n\r\n'
  printf 'Certificate renewal succeeded on EC2 instance %s.\r\n\r\n' "$INSTANCE_ID"
  printf 'Certificate renewed: %s\r\n' "$CERT_NAME"
  printf 'Certificate expiry date: %s\r\n\r\n' "$CERTIFICATE_EXPIRY"
  printf 'Nginx reload output:\r\n%b\r\n' "$RELOAD_OUTPUT"
  printf -- '--%s--\r\n' "$MIME_BOUNDARY"
} > "$RAW_EMAIL"

aws ses send-raw-email \
  --region "$REGION" \
  --raw-message "Data=fileb://$RAW_EMAIL"
rm -f "$RAW_EMAIL"
EOF
chmod 700 /usr/local/sbin/certbot-renewal-hook.sh

# Keep the renewal commands readable while leaving the cron entry short.
cat > /usr/local/sbin/certbot-renew.sh <<'EOF'
#!/bin/bash
set -u

/usr/bin/certbot renew \
  --cert-name waziup.io \
  --webroot \
  --webroot-path /var/www/html \
  --deploy-hook "/usr/local/sbin/certbot-renewal-hook.sh waziup.io"

/usr/bin/certbot renew \
  --cert-name porai.ai \
  --deploy-hook "/usr/local/sbin/certbot-renewal-hook.sh porai.ai"
EOF
chmod 700 /usr/local/sbin/certbot-renew.sh

# Schedule certificate renewal for all certificates
echo "17 */12 * * * root /usr/local/sbin/certbot-renew.sh" > /etc/cron.d/certbot

# 9. Send notification email with the OpenVPN profile and certificate expiry details
OPENVPN_PROFILE=/root/waziup.ovpn
test -s "$OPENVPN_PROFILE"
WAZIUP_CERT_EXPIRY=$(openssl x509 -enddate -noout -in /etc/letsencrypt/live/waziup.io/cert.pem | sed 's/^notAfter=//')
PORAI_CERT_EXPIRY=$(openssl x509 -enddate -noout -in /etc/letsencrypt/live/porai.ai/cert.pem | sed 's/^notAfter=//')
MIME_BOUNDARY="waziup-${INSTANCE_ID}-$(date +%s)"
RAW_EMAIL=/tmp/waziup-startup-email.eml
{
  printf 'From: no-reply@waziup.org\r\n'
  printf 'To: contact@waziup.org\r\n'
  printf 'Cc: corentin.dupont@waziup.org, johann.forster@waziup.org\r\n'
  printf 'Subject: EC2 Instance Restart: %s\r\n' "$INSTANCE_ID"
  printf 'MIME-Version: 1.0\r\n'
  printf 'Content-Type: multipart/mixed; boundary="%s"\r\n' "$MIME_BOUNDARY"
  printf '\r\n'
  printf -- '--%s\r\n' "$MIME_BOUNDARY"
  printf 'Content-Type: text/plain; charset=UTF-8\r\n\r\n'
  printf 'The Amazon Linux 2023 EC2 instance (%s) has successfully started and executed its launch script.\r\n\r\n' "$INSTANCE_ID"
  printf 'Certificate expiry dates:\r\n'
  printf '  waziup.io and related domains: %s\r\n' "$WAZIUP_CERT_EXPIRY"
  printf '  porai.ai and *.porai.ai: %s\r\n' "$PORAI_CERT_EXPIRY"
  printf '\r\n--%s\r\n' "$MIME_BOUNDARY"
  printf 'Content-Type: application/x-openvpn-profile; name="waziup.ovpn"\r\n'
  printf 'Content-Disposition: attachment; filename="waziup.ovpn"\r\n'
  printf 'Content-Transfer-Encoding: base64\r\n\r\n'
  base64 -w 76 "$OPENVPN_PROFILE"
  printf '\r\n--%s--\r\n' "$MIME_BOUNDARY"
} > "$RAW_EMAIL"

aws ses send-raw-email \
  --region "$REGION" \
  --raw-message "Data=fileb://$RAW_EMAIL"
rm -f "$RAW_EMAIL"