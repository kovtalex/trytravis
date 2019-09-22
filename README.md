# kovtalex_infra
kovtalex Infra repository

# Деплой тестового приложения в GCP

Устанавливаем Google Cloud SDK и проверяем:
```
gcloud auth list
```

Создаем скрипт установки Ruby и Bundler (install_ruby.sh):
```
#!/bin/bash
sudo apt update
sudo apt install -y ruby-full ruby-bundler build-essential
```

Создаем скрипт установки MongoDB (install_mongodb.sh):
```
#!/bin/bash
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys D68FA50FEA312927
sudo bash -c 'echo "deb http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.2 multiverse" > /etc/apt/sources.list.d/mongodb-org-3.2.list'
sudo apt update
sudo apt install -y mongodb-org
sudo systemctl start mongod
sudo systemctl enable mongod
```

Создаем скрипт деплоя приложения (deploy.sh):
```
#!/bin/bash
git clone -b monolith https://github.com/express42/reddit.git
cd reddit && bundle install
bundle install
puma -d
```

Создаем скрипт объединяющий в себе три выше указанных скрипта (startup_script.sh):
```
#!/bin/bash
sudo apt update
sudo apt install -y ruby-full ruby-bundler build-essential
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys D68FA50FEA312927
sudo bash -c 'echo "deb http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.2 multiverse" > /etc/apt/sources.list.d/mongodb-org-3.2.list'
sudo apt update
sudo apt install -y mongodb-org
sudo systemctl start mongod
sudo systemctl enable mongod
git clone -b monolith https://github.com/express42/reddit.git
cd reddit && bundle install
bundle install
puma -d
```

Даем право на выполнение скриптов:
```
chmod u+x install_ruby.sh
chmod u+x install_mongodb.sh
chmod u+x deploy.sh
chmod u+x startup_script.sh
```

Создаем новый инстанс через gcloud CLI с заранее подготовленным startup script:
```
gcloud compute instances create reddit-app \
--boot-disk-size=10GB \
--image-family ubuntu-1604-lts \
--image-project=ubuntu-os-cloud \
--machine-type=g1-small \
--tags puma-server \
--restart-on-failure \
--metadata-from-file startup-script=startup_script.sh
```

Создаем новый инстанс через gcloud CLI со скриптом загружаемым по URL:
```
gcloud compute instances create reddit-app \
--boot-disk-size=10GB \
--image-family ubuntu-1604-lts \
--image-project=ubuntu-os-cloud \
--machine-type=g1-small \
--tags puma-server \
--restart-on-failure \
--metadata startup-script-url=https://gist.githubusercontent.com/kovtalex/207a691769cdc057505ca65051dfa54d/raw/5f4632a4b43e39b46310892dc415b9144fe24494/startup_script.sh
```

Создает правило fw через gcloud CLI:
```
gcloud compute firewall-rules create default-puma-server --action=ALLOW --rules=tcp:9292 --source-ranges=0.0.0.0/0 --target-tags=puma-server
```

Данные для проверки ДЗ:
```
testapp_IP = 35.204.90.255
testapp_port = 9292
```


# GCP

Создаем два микро инстанса:
```
bastion с внешним и внутренним интерфейсами
someinternalhost с одним внутренним интерфейсом
```

Генерируем пару ключей (для пользователя appuser) и заливаем публичный ключ на GCP:
```
ssh-keygen -t rsa -f ~/.ssh/appuser -C appuser -P ""
```

Проверяем подключение с локальной машины к bastion:
```
ssh -i ~/.ssh/appuser appuser@35.204.134.231
```

Подключение к someinternalhost с локальной машины реализуем черем SSH Agent Forwarding:
```
eval `ssh-agent -s`
ssh-add -L
ssh-add ~/.ssh/appuser
ssh -i ~/.ssh/appuser -A appuser@35.204.134.231
ssh 10.164.0.4
```

Подключение к someinternalhost в одну команду:
```
ssh -i ~/.ssh/appuser -tt -A appuser@35.204.134.231 ssh appuser@10.164.0.4
```


Подключение к someinternalhost по алиасу реализуем с помощью внесения конфигурации в ~/.ssh/config :
```
host someinternalhost
     hostname 10.164.0.4
     user appuser
     ProxyCommand ssh appuser@35.204.134.231 -W %h:%p
```

Для доступа к частной сети через bastion используем VPN сервер Pritunl:
```
Разрешаем http и https трафик на брандмауэре GCP для bastion
sudo bash setupvpn.sh
Настраиваем Pritunl https://35.204.134.231/setup
```

После полной настройки Pritunl проверяем работоспособность:
```
openvpn --config cloud-bastion.ovpn
ssh -i ~/.ssh/appuser appuser@10.164.0.4
```

Устанавливаем валидный сертификат для панели управления Pritunl с помощью сервисов sslip.io и Lets's Encrypt указав доменное имя 35.204.134.231.sslip.io в настройках VPN сервера.

Данные для проверки VPN:
```
bastion_IP = 35.204.134.231
someinternalhost_IP = 10.164.0.4
```
