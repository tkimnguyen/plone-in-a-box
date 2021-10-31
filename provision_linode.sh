#!/bin/bash

# update packages
sudo apt update -y && sudo apt upgrade -y

apt-get install -y curl gpg git nginx

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo   "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update

apt-get install -y docker-ce docker-ce-cli containerd.io

apt-get install -y docker-compose

rm /etc/nginx/sites-enabled/default

cat <<EOT > /etc/nginx/conf.d/default.conf
upstream backend {
  server localhost:8080;
}
upstream frontend {
  server localhost:3000;
}

server {
  listen 80;
  server_name  localhost;

  location ~ /\+\+api\+\+(\$|/.*) {
      rewrite ^/\+\+api\+\+(\$|/.*) /VirtualHostBase/http/\$server_name/Plone/++api++/VirtualHostRoot/\$1 break;
      proxy_pass http://backend;
  }

  location ~ / {
      location ~* \.(js|jsx|css|less|swf|eot|ttf|otf|woff|woff2)\$ {
          add_header Cache-Control "public";
          expires +1y;
          proxy_pass http://frontend;
      }
      location ~* static.*\.(ico|jpg|jpeg|png|gif|svg)\$ {
          add_header Cache-Control "public";
          expires +1y;
          proxy_pass http://frontend;
      }

      location ~ /(@@download|@@images|@@ical_view) {
          rewrite ^(.*) /VirtualHostBase/http/\$server_name/Plone/VirtualHostRoot\$1 break;
          proxy_pass http://backend;
          break;
      }

      proxy_set_header        Host \$host;
      proxy_set_header        X-Real-IP \$remote_addr;
      proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header        X-Forwarded-Proto \$scheme;
#      proxy_redirect http:// https://;
      proxy_pass http://frontend;
  }
}
EOT

service nginx reload

useradd -G docker -m plone
echo plone:plone | chpasswd

cat << EOT > /home/plone/docker-compose.yml
version: "3"
services:

  frontend:
    image: plone/plone-frontend:14.0.0-alpha-node14
    environment:
      RAZZLE_INTERNAL_API_PATH: http://backend:8080/Plone
      RAZZLE_DEV_PROXY_API_PATH: http://backend:8080/Plone
    restart: always
    ports:
    - "3000:3000"
    depends_on:
      - backend

  backend:
    image: plone/plone-backend:6.0-dev-python39
    environment:
      RELSTORAGE_DSN: "dbname='plone' user='plone' host='db' password='plone'"
    restart: always
    ports:
    - "8080:8080"
    depends_on:
      - db

  db:
    image: postgres
    environment:
      POSTGRES_USER: plone
      POSTGRES_PASSWORD: plone
      POSTGRES_DB: plone
    restart: always
    volumes:
      - data:/var/lib/postgresql/data
    ports:
    - "5432:5432"

volumes:
  data: {}
EOT
chown plone:plone /home/plone/docker-compose.yml
cd /home/plone && docker-compose up -d

sleep 120

# create the default Plone site
curl --user admin:admin 'http://localhost:8080/@@plone-addsite' -X POST -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8' -H 'Accept-Language: en-US,en;q=0.5' --compressed -H 'Content-Type: application/x-www-form-urlencoded' -H 'Connection: keep-alive' -H 'Upgrade-Insecure-Requests: 1' -H 'Sec-GPC: 1' -H 'Pragma: no-cache' -H 'Cache-Control: no-cache' --data-raw 'site_id=Plone&title=Site&default_language=en-us&portal_timezone=America%2FChicago&setup_content%3Aboolean=on&extension_ids%3Alist=plonetheme.barceloneta%3Adefault&extension_ids%3Alist=plone.app.caching%3Adefault&extension_ids%3Alist=plone.volto%3Adefault-homepage&extension_ids%3Alist=plone.volto%3Adefault&form.submitted%3Aboolean=True'

service nginx reload
