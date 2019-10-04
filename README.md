# kovtalex_infra
kovtalex Infra repository

# Практика IaC с использованием Terraform

Скачиваем архив, распаковываем и перемещаем бинарный файл Terraform в /usr/local/bin/
```
https://www.terraform.io/downloads.html
terraform -v
```

Создаем .gitignore со следующим содержимым:
```
*.tfstate
*.tfstate.*.backup
*.tfstate.backup
*.tfvars
.terraform/
```

Комманды Terraform:
```
terraform plan - просмотр будущих изменений относительно текущего состояния ресурсов
terraform apply - применение изменений (-auto-approve без подтверждений)
terraform show | grep nat_ip - просмотр атрибутов, к примеру ip
terraform output - просмотр выходных переменных
terraform taint - пометка ресурса для пересоздания
terraform fmt - форматирование конфигурационных файлов
```

Конфигурационные файлы проекта:
```
main.tf - основной файл конфигурации
lb.tf - описание балансировщика
variables.tf - определение входных переменных
terraform.tfvars - входные переменные
outputs.tf - определение выходных переменных
```

Задание со *:
 - Добавление ssh ключа пользователя appuser1 в метаданные проекта:
 ```
 ssh-keys = "appuser:${file(var.public_key_path)} appuser1:${file(var.public_key_path)}"
 ```
 - Добавление ssh ключа пользователей appuser1 и appuser2 в метаданные проекта:
 ```
 ssh-keys = "appuser:${file(var.public_key_path)} appuser1:${file(var.public_key_path)} appuser2:${file(var.public_key_path)}"
 ```
 - При попытке добавить ssh ключ пользователя appuser_web через веб интерфейс в метаданные проекта и выполнить terraform apply происходит удаление данного ssh ключа
 - Конфигурация балансировщика приведена в файле lb.tf
 - Добавлена конфигурация нового инстанса reddit-app2 к балансировщику. При остановке сервиса на одном из инстансов, приложение продолжает быть доступным для конечных пользователей
 - При добавлении нового инстанса необходимо полностью копировать код, что нерационально + нет общей базы у приложений на инстансах
 - Избавится от этого процесса позволит использование переменной count, указав ее значение равным 2


# Сборка образов VM при помощи Packer

Скачиваем архив, распаковываем и перемещаем бинарный файл Packer в /usr/local/bin/
```
https://www.packer.io/downloads.html
packer -v 
```

Создаем ADC и смотрим Project_id:
```
gcloud auth application-default login
gcloud projects list
```

Создаем Packer шаблон ubuntu16.json:
```
{
    "builders": [
        {
            "type": "googlecompute",
            "project_id": "{{user `project_id`}}",
            "image_name": "reddit-base-{{timestamp}}",
            "image_family": "reddit-base",
            "source_image_family": "{{user `source_image_family`}}",
            "zone": "europe-west1-b",
            "ssh_username": "appuser",
            "machine_type": "{{user `machine-type`}}",
            "disk_type": "{{user `disk_type`}}",
            "disk_size": "{{user `disk_size`}}",
            "image_description": "{{user `image_description`}}",
            "network": "{{user `network`}}",
            "tags": "{{user `tags`}}"
        }
    ],
    "provisioners": [
        {
            "type": "shell",
            "script": "scripts/install_ruby.sh",
            "execute_command": "sudo {{.Path}}"
        },
        {
            "type": "shell",
            "script": "scripts/install_mongodb.sh",
            "execute_command": "sudo {{.Path}}"
        }
    ]
}
```

Создаем файл с пользовательскими переменными variables.json:
```
{
  "project_id": "",
  "source_image_family": "",
  "machine_type": "f1-micro",
  "disk_type": "pd-standard",
  "disk_size": "10",
  "image_description": "",
  "tags": "puma-server",
  "network": "default"
}
```

Проверка шаблона на ошибки:
```
packer validate -var-file=./variables.json -var 'project_id=infra-253207' -var 'source_image_family=ubuntu-1604-lts' ./ubuntu16.json
```

Построение образа reddit-base:
```
packer build -var-file=./variables.json -var 'project_id=infra-253207' -var 'source_image_family=ubuntu-1604-lts' ./ubuntu16.json
```

Построение образа reddit-full:
```
packer build -var-file=./variables.json -var 'project_id=infra-253207' -var 'source_image_family=ubuntu-1604-lts' ./immutable.json
```

Запуск вируальной машины из образа reddit-full:
```
gcloud compute instances create reddit-app \
--boot-disk-size=10GB \
--machine-type=g1-small \
--tags=puma-server \
--image=reddit-full \
--restart-on-failure
```


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


Подключение к someinternalhost по алиасу реализуем с помощью внесения конфигурации в ~/.ssh/config:
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
