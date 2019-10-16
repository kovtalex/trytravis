# kovtalex_infra
kovtalex Infra repository

# Знакомство с Ansible

Проверяем установку Python 2.7 и устанавливаем pip:
```
python --version
wget https://bootstrap.pypa.io/get-pip.py
python2.7 get-pip.py
```

requirements.txt:
```
ansible>=2.4
```

Устанавлием ansible
```
pip install -r requirements.txt
ansible --version
```

Поднимаем инфраструктуру окружения stage и проверяем SSH достук к ней:
```
terraform apply
```

Пишем файл конфигурации ansible.cfg:
```
[defaults]
inventory = ./inventory
remote_user = appuser
private_key_file = ~/.ssh/appuser
host_key_checking = False
retry_files_enabled = False
```

Файл inventory:
```
[app]
appserver ansible_host=34.76.137.86

[db]
dbserver ansible_host=34.77.107.107
```

Используем команду ansible для вызова модуля ping:
```
ansible appserver -i ./inventory -m ping
-m ping - вызываемый модуль
-i ./inventory - путь до файла инвентори
appserver - имя хоста или имя группы, которое указан в инвентори, откуда Ansible yзнает, как подключаться к хосту
```

Используем модуль command, который позволяет запускать произвольные команды на удаленном хосте:
```
ansible dbserver -m command -a uptime

Модуль command выполняет команды, не используя оболочку (sh, bash), поэтому в нем не работают перенаправления потоков и нет доступа к некоторым переменным окружения.

```

Простой плейбук inventory.yml
```
app:
  hosts:
    appserver:
      ansible_host: 34.76.137.86

db:
  hosts:
    dbserver:
      ansible_host: 34.77.107.107
```

Использование YAML inventory
```
Ключ -i переопределяет путь к инвентори файлу
ansible all -m ping -i inventory.yml
```

Используем модуль shell, который позволяет запускать произвольные команды на удаленном хосте:
```
ansible app -m shell -a 'ruby -v; bundler -v'
```

Используем модуль command для проверки статуса сервиса MongoDB:
```
Эта операция аналогична запуску на хосте команды systemctl status mongod
ansible db -m command -a 'systemctl status mongod'
```

Используем модуль systemd, который предназначен для управления сервисами:
```
ansible db -m systemd -a name=mongod
```

Используем модуль git для клонирования репозитория с приложением на app сервер:
```
ansible app -m git -a \
'repo=https://github.com/express42/reddit.git dest=/home/appuser/reddit
повторное выполнение этой команды проходит успешно, только переменная changed будет false (что значит, что изменения не произошли)
```

Тоже самое с модулем command:
```
в этом примере, повторное выполнение завершается ошибкой
ansible app -m command -a \
'git clone https://github.com/express42/reddit.git /home/appuser/reddit'
```

Создадим плейбук clone.yml:
```
---
- name: Clone
  hosts: app
  tasks:
    - name: Clone repo
      git:
        repo: https://github.com/express42/reddit.git
        dest: /home/appuser/reddit
```

И выполним его:
```
ansible-playbook clone.yml
Изменения не произошли так как репозиторий уже клонирован
```

Теперь выполним:
```
ansible app -m command -a 'rm -rf ~/reddit'
ansible-playbook clone.yml
После выполнения будут изменения, т.к. мы удалили ~/reddit и клонировали репозиторий по новому
```

Для задания со * готовим inventory.json:
```
{
    "app": {
        "hosts": ["34.76.137.86"]
    },
    "db": {
        "hosts": ["34.77.107.107"]
    }
}
```

Описание динамического inventory доступно по ссылке:
```
https://medium.com/@Nklya/%D0%B4%D0%B8%D0%BD%D0%B0%D0%BC%D0%B8%D1%87%D0%B5%D1%81%D0%BA%D0%BE%D0%B5-%D0%B8%D0%BD%D0%B2%D0%B5%D0%BD%D1%82%D0%BE%D1%80%D0%B8-%D0%B2-ansible-9ee880d540d6
```

Для работы динамического inventory:
 - пишем скрипт inventory.sh, который получает состояние инфраструктуры и выполняет python скрипт для получения ip хостов из output переменных terraform:
```
#!/bin/bash
cd ../terraform/stage
terraform state pull | python ../../ansible/inventory.py
cd ../../ansible
```
- пишет jsons.py скрипт:
```
#!/usr/bin/env python

import json
import sys

if __name__ == '__main__':
  out_str = ""
  try:
    data = sys.stdin.read()
    f = json.loads(data)
    app = f["outputs"]["app_external_ip"]["value"]
    db = f["outputs"]["db_external_ip"]["value"]
    out = {'app': {'hosts': [str(app)]},'db': {'hosts': [str(db)]}}
    out_str = json.dumps(out)
  except:
    pass

  sys.stdout.write(out_str)
```
- в ansible.cfg меняем значение для inventory на ./json.sh:

Результатом выполнения команды ansible all -m ping будет:
```
34.76.137.86 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}
34.77.107.107 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}
```

Динамическое инвентори позволяет формировать список хостов для Ansible динамически c применением скриптов.
Динамическое инвентори представляет собой простой исполняемый скрипт (+x), который при запуске с параметром --list возвращает список хостов в формате JSON.
Его необходимо указывать при выполнении Ansible с помощью опции -i/--inventory, либо в конфигурационном файле ansible.cfg.
Сам скрипт может быть написан на любом языке (bash, python, ruby, etc.)
Когда инвентори скрипт запущен с параметром --list, он возвращает JSON с данными о хостах и группах, которые он получил.
Помимо имен групп, хостов и IP адресов там могут быть различные переменные и другие данные.
При запуске скрипта с параметром --host <hostname> (где <hostname> это один из хостов), скрипт должен вернуть JSON с переменными для этого хоста.
Также можно использовать элемент _meta, в котором перечислены все переменные для хостов.


# Принципы организации инфраструктурного кода и работа над инфраструктурой на примере Terraform

Комманды Terraform:
```
terraform import - Импорт существующей инфраструктуры в Terraform (пример: terraform import google_compute_firewall.firewall_ssh default-allow-ssh)
terraform get - Загрузка модулей (в данном случает из локальной папки)
```

Выносим БД на отдельный инстанс (c помощью Packer создаем шаблоны VM db.json и app.json на основе шаблона ubuntu16.json)


Создаем инфраструктуру для двух окружений (stage и prod) используя модули:
```
stage - SSH доступ для всех IP адресов
prod - SSH доступ только с IP пользователя
```

Пример инфраструктуры stage (main.tf):
```
provider "google" {
  version = "~>2.15"
  project = var.project
  region  = var.region
}
module "app" {
  source           = "../modules/app"
  name             = "reddit-app"
  machine_type     = "g1-small"
  zone             = var.zone
  tags             = ["reddit-app"]
  public_key_path  = var.public_key_path
  private_key_path = var.private_key_path
  app_disk_image   = var.app_disk_image
  db_internal_ip   = "${module.db.db_internal_ip}"
}
module "db" {
  source           = "../modules/db"
  name             = "reddit-db"
  machine_type     = "g1-small"
  zone             = var.zone
  tags             = ["reddit-db"]
  public_key_path  = var.public_key_path
  private_key_path = var.private_key_path
  db_disk_image    = var.db_disk_image
}
module "vpc" {
  source        = "../modules/vpc"
  source_ranges = ["0.0.0.0/0"]
}
```

Модули:
```
/modules/app - приложение
/modules/db - база данных
/modules/vpc - firewall для ssh
```

Создаем Storage Bucket (storage-bucket.tf):
```
provider "google" {
  version = "~> 2.15"
  project = var.project
  region  = var.region
}

module "storage-bucket" {
  source  = "SweetOps/storage-bucket/google"
  version = "0.3.0"
  location = var.region

  name = "storage-bucket-kovtalex"
}

output storage-bucket_url {
  value = module.storage-bucket.url
}
```

*Выносим хранение стейт файла в удаленный бекенд на примере окружения stage (/stage/backend.tf):
```
terraform {
  backend "gcs" {
    bucket = "storage-bucket-kovtalex"
    prefix = "state"
  }
}
```

 - *Переносим конфигурационные файлы Terraform вне репозитория и проверяем, что Terraform видит текущее состояние используя хранилище storage bucket
 - *Проверяет работу блокировок при единовременной применении конфигураций
 - **Добавляем provisioner для деплоя приложения в модуль /module/app и передачи значения в переменную DATABASE_URL для успешного подключения нашего приложения к БД:
```
  provisioner "file" {
    source      = "../modules/app/files/puma.service"
    destination = "/tmp/puma.service"
  }

  provisioner "remote-exec" {
    inline = [
      "echo export DATABASE_URL=\"${var.db_internal_ip}\" >> ~/.profile"
    ]
  }

  provisioner "remote-exec" {
    script = "../modules/app/files/deploy.sh"
  }
```


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
