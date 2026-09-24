#!/bin/bash
# EC2 user data script for an Amazon Linux 2023 AMI.
#
# Output of this script is collected in 
#   cat /var/log/cloud-init-output.log
#

set -Eeuox pipefail

# 1. Configure default SSH access
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDf4iVKWrUaf8uV2Y4JIYovicPoqCIJRNlTpseFlizzMCa2CpicyrXgbvaZN6TeJoGuPlVMH0hzmMPuezDFyrSWpn71YBMT8KKXhB5jbR0RrMVSCqLlgWdXzmjeH1qxhdY1bu/q9t1oot6MWYEXkdTJOwKwDI8jzwiSfoZu1LR6tLNNdHAFLI8/NF+UKcvYCS8lIr9zF3zPBdMR7Y7rg973wW+JFUFuk5typa6i7EfFcT74j7lrgeO/lZgJY0BG1J5jsgiXDn37NrcgupJMPrJiW2y25RnflMJQ0XIp4DCblviJxEOFUflW9rZ8xowqbY0nM82v7y9eI6zHZAP3qSeB9Eo6hE9Lv1KavgVs9ilSZJc1w8FhHd3se/3mWqUqqWWoiLvWm3QvjCaZ/DLU9gZAvCzPwnicoQ+89JhppW9vsbK4SZM/avo4lIevqkOtrY0CjaL+0vZF2ow16laWP4f226nyJ5gSmPA1b6Ml8BERDE0wYWeMdKyp8Bmd7JmJXTk= cdupont" >> /home/ec2-user/.ssh/authorized_keys
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCYaBsTtmINbbUuFQ/ElY2ni/7QZltmr56hEzdHVmKpN3lPZY1Q01L5TokbYU7tQMRc2ZDwqLvmLrTpF5uCZe8bwBKjKlM4PVasdX/uvnCoc6gfugtjibacXALHzbPawdgeT9H5P78lU9g0hECt32D0AvOqWa9VuBruYXk9NfU0nXTQERrNffpFmQVb5FF2ibG2wGU4MCe3lhmKZou2OgvTSgGQkZSnQv3rkEpB3G7Zy9fnGWdlbbAmlYod0B7XWtTy+HKDNRD4ahbKexs3nqR7We4JHsUSLtTotpC6aL5Aly+pWDMEaUZ71a8dvVT8VHmbDrR6LYeo7+/lqZKNrP3htCafzOkAK6PXL0rHt1ZSdxRjmOOjMtUd9Am0/lL14BOwI82F3vVl/Ui3pOF2FWMSgNHflpY27EkoAC7BNPc6/Jqjh6lY24PO36Cnry2PboWtpzTFxRvJiMsGiyLjagSZ5pFI6KP8olrrvKdw6ntL8+KGrl5A0blWqA2Z0HL287eFBLSHnJaHxmWdL+nEMLebp/a8/I4eVQc9y7AVy1H39Lvj5WShmGB+IOHIMRG5NN5ByoTt3i/KgtC2Zd5PawjAvMlV2kbuFz+U7057hzPL/WbhELkpDJ3LuGug1aoRn6Rs6lVfGw7rg5lkBj37M/Ilpt9syj1rfG+6sxwDwVcfVw== johann.forster@waziup.org" >> /home/ec2-user/.ssh/authorized_keys
chmod 600 /home/ec2-user/.ssh/authorized_keys
chown ec2-user:ec2-user /home/ec2-user/.ssh/authorized_keys


# 2. Update packages & install Certbot, Cronie, and Python Pip
dnf update -y
dnf swap curl-minimal curl -y
dnf install -y certbot cronie python3-pip ecs-init

# Enable and start cron service for certificate renewals
systemctl enable --now crond.service

# Install Certbot IONOS DNS plugin
python3 -m venv /opt/certbot/
/opt/certbot/bin/pip install --upgrade pip
/opt/certbot/bin/pip install certbot certbot-dns-ionos
ln -sf /opt/certbot/bin/certbot /usr/bin/certbot


# 3. Retrieve Instance ID and AWS Region via IMDSv2
TOKEN=$(curl -s -S -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -s -S -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -S -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)


# 4. Retrieve IONOS INI text directly from AWS Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id "org/waziup/ionos-credentials" \
  --region "$REGION" \
  --query SecretString \
  --output text > /root/ionos-credentials.ini

chmod 600 /root/ionos-credentials.ini


# 5. Reattach Elastic IP
aws ec2 associate-address --instance-id "$INSTANCE_ID" --allocation-id eipalloc-61f3b74f --allow-reassociation --region "$REGION"


# 6. Install and configure OpenVPN
curl -fsSL https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh \
  -o /usr/local/sbin/openvpn-install
chmod 700 /usr/local/sbin/openvpn-install
/usr/local/sbin/openvpn-install install \
  --endpoint "18.195.197.182" \
  --client waziup \
  --tls-sig crypt


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
  --dns-ionos-propagation-seconds 60 \
  --server https://acme-v02.api.letsencrypt.org/directory \
  --agree-tos \
  --non-interactive \
  --rsa-key-size 4096 \
  -d 'porai.ai' -d '*.porai.ai'


# 9. Configure the certificate renewal hook and renewal script
cat > /usr/local/sbin/certbot-renewal-hook.sh <<'EOF'
#!/bin/bash
set -u

CERT_NAME=$1
CERTIFICATE_PATH=/etc/letsencrypt/live/"$CERT_NAME"/cert.pem
TOKEN=$(curl -s -S -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -s -S -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -S -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)

RELOAD_OUTPUT=""
if ! CONTAINERS=$(docker container ls --quiet --filter label=certbot-renewal-target 2>&1); then
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
  printf 'This is an automated message generated by the user data script running on your EC2 instance. Do not reply.\r\n\r\n'
  printf 'Certificate renewed: %s\r\n' "$CERT_NAME"
  printf 'Certificate expiry date: %s\r\n\r\n' "$CERTIFICATE_EXPIRY"
  printf 'Nginx reload output:\r\n%b\r\n' "$RELOAD_OUTPUT"
  printf -- '--%s--\r\n' "$MIME_BOUNDARY"
} > "$RAW_EMAIL"

aws ses send-raw-email \
  --region "$REGION" \
  --raw-message "Data=$(base64 -w 0 "$RAW_EMAIL")"
rm -f "$RAW_EMAIL"
EOF
chmod 700 /usr/local/sbin/certbot-renewal-hook.sh

# Create a certbot renewal script
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

# 10. Schedule certificate renewal for all certificates
echo "17 */12 * * * root /usr/local/sbin/certbot-renew.sh" > /etc/cron.d/certbot


# 11. Attach instance to ECS cluster
echo "ECS_CLUSTER=waziup-frontend" >> /etc/ecs/ecs.config


# 12. Send notification email with the OpenVPN profile and certificate expiry details
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
  printf 'This is an automated message generated by the user data script running on your EC2 instance. Do not reply.\r\n\r\n'
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
  --raw-message "Data=$(base64 -w 0 "$RAW_EMAIL")"
rm -f "$RAW_EMAIL"

# 13. Signal to Auto Scaling that this instance is ready
# # TODO: The template uses a fixed timeout (300s) now
# aws autoscaling complete-lifecycle-action \
#   --lifecycle-hook-name "wait-for-user-script" \
#   --auto-scaling-group-name "Front-End" \
#   --lifecycle-action-result CONTINUE \
#   --instance-id "$INSTANCE_ID"
