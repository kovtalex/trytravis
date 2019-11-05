# kovtalex_infra

[![Build Status](https://travis-ci.com/Otus-DevOps-2019-08/kovtalex_infra.svg?branch=master)](https://travis-ci.com/Otus-DevOps-2019-08/kovtalex_infra)

## Локальная разработка с Vagrant

### Установка Vagrant

https://www.vagrantup.com/downloads.html скачиваем и устанавливаем в /usr/local/bin

Проверяем установку: vagrant -v

Так как на Ubuntu в виртуалке не завелся VirtualBox, пришлось воспользоваться libvirt и установить Vagrant через apt.

Перед началом работы с Vagrant и Molecule обновим наш .gitignore:

```
.gitignore
... <- предыдущие записи
# Vagrant & molecule
.vagrant/
*.log
*.pyc
.molecule
.cache
.pytest_cache
```

### Далее опишем локальную инфраструктуру, которую использовали в GCE и применим на своей локальной машине, используя Vagrant и libvirt

Vagrantfile:
```
Vagrant.configure("2") do |config|

  config.vm.provider :libvirt do |v|
    v.memory = 512
  end


  config.vm.define "dbserver" do |db|
    db.vm.box = "generic/ubuntu1604"
    db.vm.hostname = "dbserver"
    db.vm.network :private_network, ip: "10.10.10.10"
    
    db.vm.provision "ansible" do |ansible|
      ansible.playbook = "playbooks/site.yml"
      ansible.groups = {
      "db" => ["dbserver"],
      "db:vars" => {"mongo_bind_ip" => "0.0.0.0"}
      }
    end
  end

  config.vm.define "appserver" do |app|
    app.vm.box = "generic/ubuntu1604"
    app.vm.hostname = "appserver"
    app.vm.network :private_network, ip: "10.10.10.20"

    app.vm.provision "ansible" do |ansible|
      ansible.playbook = "playbooks/site.yml"
      ansible.groups = {
      "app" => ["appserver"],
      "app:vars" => { "db_host" => "10.10.10.10"}
      }
      ansible.extra_vars = {
        "deploy_user" => "vagrant",
        "nginx_sites" => {
          "default" => [
            "listen 80",
            "server_name \"reddit\"",
            "location / {
              proxy_pass http://127.0.0.1:9292;
            }"
          ]
        }
      }
    end
  end
end
```

Образ generic/ubuntu1604 для libvirt скачивается из Vagrant Cloud - главного хранилища Vagrant боксов.

Команды:
- vagrant up - создание VM и провижининг
- vagrant box list - просмотр списка скаченных боксов для наших VM
- vagrant status - просмотр статуса VM
- vagrant ssh appserver - подключение к VM по SSH
- vagrant provision dbserver - запуск провижинера
- cat .vagrant/provisioners/ansible/inventory/vagrant_ansible_inventory - просмотр сформированного инвентори

При выполнении vagrant up с libvirt не стартует один из провижинеров, поэтому указываем аргумент --no-parallel, для последовательного выполнения развертывания:
vagrant up --no-parallel

### Доработка ролей

Вынесем для роли db:
- задачи по установке Mongo DB в ansible/roles/db/tasks/install_mongo.yml
- задачи по настройке Mongo DB в ansible/roles/db/tasks/config_mongo.yml
- запуск этих задач из ansible/roles/db/tasks/main.yml

Вынесем для роли app:
- задачи по установке Ruby в ansible/roles/app/tasks/ruby.yml
- задачи по настройке Puma в ansible/roles/app/tasks/puma.yml
- запуск этих задач из ansible/roles/app/tasks/main.yml

Также введем переопределение имени пользовавателя в нашем боксе. Для этого воспользуемся переменными, имеющими самый высокий приоритет по сравнению со всеми остальными (extra_vars):

```
Vagrantfile:
ansible.extra_vars = {
  "deploy_user" => "vagrant",
  ...
```

Заменим все упоминания о appuser на {{ deploy_user }} в наших тасках, шаблоне и проверим работу приложения по адресу app хоста: 10.10.10.20:9292

В случае, если vagrant provision падает с ошибкой из-за невозможности записать в директорию /home/<имя пользователя>, проверим под каким
пользователем Vagrant выполняет плейбуки.

Задание со *

Дополним в Vagrantfile раздел exra_vars для передачи параметров конфигурации nginx:
```
ansible.extra_vars = {
  "nginx_sites" => {
    "default" => [
      "listen 80",
      "server_name \"reddit\"",
      "location / {
        proxy_pass http://127.0.0.1:9292;
      }"
    ]
}
```
и проверим работу приложения по адресу app хоста: 10.10.10.20:80

### Тестирование ролей с помощью Molecule и Testinfra

Для начала добавим все необходимые компоненты для тестирования в requirements.txt и установим их: pip install -r requirements.txt (используем venv):

```
molecule>=2.6
testinfra>=1.10
python-vagrant>=0.5.15
```

Проверим версию molecule: molecule --version 

Используем команду molecule init для создания заготовки тестов роли db в директории ansible/roles/db:

molecule init scenario --scenario-name default -r db -d vagrant

Добавим несколько тестов, используя модули Testinfra для проверки конфигурации, настраиваемой ролью db:

db/molecule/default/test_default.py
```
import os

import testinfra.utils.ansible_runner

testinfra_hosts = testinfra.utils.ansible_runner.AnsibleRunner(
    os.environ['MOLECULE_INVENTORY_FILE']).get_hosts('all')


# check if MongoDB is enabled and running
def test_mongo_running_and_enabled(host):
    mongo = host.service("mongod")
    assert mongo.is_running
    assert mongo.is_enabled


# check if configuration file contains the required line
def test_config_file(host):
    config_file = host.file('/etc/mongod.conf')
    assert config_file.contains('bindIp: 0.0.0.0')
    assert config_file.is_file
```

Опишем тестовую машину db/molecule/default/molecule.yml:

```
---
dependency:
  name: galaxy
driver:
  name: vagrant
  provider:
    name: libvirt
lint:
  name: yamllint
platforms:
  - name: instance
    box: generic/ubuntu1604
provisioner:
  name: ansible
  lint:
    name: ansible-lint
verifier:
  name: testinfra
  lint:
    name: flake8
```

и создадим ее: molecule create

Просмотр списка VM, которыми управляет Molecule: molecule list 

Подключение к VM по SSH для проверки ее работы: molecule login -h instance

Также дополним наш db/molecule/default/playbook.yml:

```
---
- name: Converge
  become: true
  hosts: all
  vars:
    mongo_bind_ip: 0.0.0.0
  roles:
    - role: db
```

Применим конфигурацию: molecule converge и прогоним тесты: molecule verify

Об успешном прохождении тестов будет свидетельствовать сообщение: Verifier completed successfully.

Дополним наш тест проверкой того, что БД слушает порт 27017:

db/molecule/default/test_default.py
```
# check if mongo port 27017 is listening
def test_mongo_port_listening(host):
    mongo_port = host.socket('tcp://27017')
    assert mongo_port.is_listening
```

Исправим наши роли и шаблоны Packer для использования ролей db и app совместно с тегами:

ansible/playbooks/packer_db.yml

```
- { role:  db }
```

ansible/playbooks/packer_app.yml

```
- { role:  app }
```

packer/db.json:

```
"provisioners": [
  {
    "type": "ansible",
    "playbook_file": "ansible/playbooks/packer_db.yml",
    "extra_arguments": ["--tags","mongo"],
    "ansible_env_vars": ["ANSIBLE_ROLES_PATH={{ pwd }}/ansible/roles"]
  }
]
```

packer/app.json:

```
"provisioners": [
  {
    "type": "ansible",
    "playbook_file": "ansible/playbooks/packer_app.yml",
    "extra_arguments": ["--tags","ruby"],
    "ansible_env_vars": ["ANSIBLE_ROLES_PATH={{ pwd }}/ansible/roles"]
  }
]
```

ansible/roles/db/main.yml (теги)

```
- include: install_mongo.yml
  tags:
    - mongo
```

ansible/roles/app/main.yml (теги):

```
- include: ruby.yml
  tags:
    - ruby
- include: puma.yml
  tags:
    - puma
```

### Задание со *

Вынесем роль db в отдельный репозитарий:
- добавим ansible/roles/db/ в .gitignore в осном репозитории обучения
- Вынесем роль db в отдельный репозитарий kovtalex/ansible-role-db и подключим через requirements.yml обоих окружений:

```
- name: db
  src: https://github.com/kovtalex/ansible-role-db
```

Для репозитария ansible-role-db и роли db подключим Travis CI для автоматического прогона тестов на GCE.

Пример роли: https://github.com/Artemmkin/db-role-example

Пройдем шаги ниже:
- добавим в .gitignore следующее:
```
*.log
*.tar
*.pub
credentials.json
google_compute_engine
```
- wget https://raw.githubusercontent.com/vitkhab/gce_test/c98d97ea79bacad23fd26106b52dee0d21144944/.travis.yml
- ssh-keygen -t rsa -f google_compute_engine -C 'travis' -q -N '' (генерируем ключ для подключения по SSH)
- добавим открытый ключ в meta данные в GCP
- используем key.json -> credentials.json из прошлого ДЗ и скопируем в корень репозитория
- выполним команды шифрования переменных:
```
travis encrypt GCE_SERVICE_ACCOUNT_EMAIL='993674103918-compute@developer.gserviceaccount.com' --add --com
travis encrypt GCE_CREDENTIALS_FILE="$(pwd)/credentials.json" --add --com
travis encrypt GCE_PROJECT_ID='infra-253207' --add --com
```
- зашифруем файлы:
```
tar cvf secrets.tar credentials.json google_compute_engine
travis login
travis encrypt-file secrets.tar --add --com
```
- пушим и проверяем изменения:
```
git commit -m 'Added Travis integration'
git push
```
- в molecule/gce/playbook.yml меняет имя роли на: "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') | basename }}"
- в molecule/gce/molecule.yml меняем имя образа на один из последних: ubuntu-1604-xenial-v20191024
- в .travis.yml для настройки оповещения о билде в Slack chat добавляем секрет зашифрованный по команде:
```
travis encrypt "devops-team-otus:<token>#alexey_kovtunovich" --com --add notifications.slack.rooms
```
- в README.md добавляем бейдж со статусом билда
- также правим в .travis.yml:
```
install:
- pip install ansible==2.8.6 molecule[gce] apache-libcloud ([gce] - указываем использовать соответсвующий драйвер)
script:
- molecule test --scenario-name gce (указываем имя нашего сценария)
after_script:
- molecule destroy --scenario-name gce (указываем имя нашего сценария)
```
Также можно использовать --debug для включения отладочной информации.


## Ansible: работа с ролями и окружениями

### Переносим созданные плейбуки в раздельные роли

Роли представляют собой основной механизм группировки и переиспользования конфигурационного кода в Ansible. Роли позволяют сгруппировать в единое целое описание конфигурации отдельных сервисов и компонент системы (таски, хендлеры, файлы, шаблоны, переменные). Роли можно затем переиспользовать при настройке окружений, тем самым избежав дублирования кода. Ролями можно также делиться и брать у сообщества (community).
в Ansible Galaxy.

Ansible Galaxy - это централизованное место, где хранится информация о ролях, созданных сообществом (community roles).
Ansible имеет специальную команду для работы с Galaxy. Получить справку по этой команде можно на сайте или использовав команду:

```
ansible-galaxy -h
```
Также команда ansible-galaxy init позволяет нам создать структуру роли в соответсвии с принятым на Galaxy форматом.

```
ansible-galaxy init app
ansible-galaxy init db
```

Структура роли:

```
tree db
db
├── README.md
├── defaults # <-- Директория для переменных по умолчанию
│ └── main.yml
├── handlers
│ └── main.yml
├── meta # <-- Информация о роли, создателе и зависимостях
│ └── main.yml
├── tasks # <-- Директория для тасков
│ └── main.yml
├── tests
│ ├── inventory
│ └── test.yml
└── vars # <-- Директория для переменных, которые не должны
└── main.yml # переопределяться пользователем
6 directories, 8 files
```

Определим роли для базы данных, приложения и проведем их проверку:

```
ansible-playbook playbooks/site.yml --check
ansible-playbook playbooks/site.yml
```

### Окружения

Обычно инфраструктура состоит из нескольких окружений. Эти окружения могут иметь небольшие отличия в настройках инфраструктуры и конфигурации управляемых хостов.

В директории ansible/environments создадим две директории для наших окружений stage и prod.

Примеры деплоя из окружения:

```
ansible-playbook playbooks/site.yml (stage)
ansible-playbook -i environments/prod/inventory playbooks/site.yml (prod)
```

### Работа с Community-ролями

Используем роль jdauphant.nginx и настроим обратное проксирование для нашего приложения с помощью nginx.

- Создадим файлы environments/stage/requirements.yml и environments/prod/requirements.yml
- Добавим в них запись вида:
  
  ```
  - src: jdauphant.nginx
    version: v2.21.1
  ```

- Установим роль: ansible-galaxy install -r environments/stage/requirements.yml
- Добавим в /roles/jdauphant.nginx/tasks/installation.packages.yml (иначе ругается на отсутствие python-get):

```
   - name: Install Python-apt
     command: apt install python-apt
```

- Комьюнити-роли не стоит коммитить в свой репозиторий, для этого добавим в .gitignore запись: jdauphant.nginx
- Добавим переменные в stage/group_vars/app и prod/group_vars/app:
  
  ```
  nginx_sites:
  default:
   - listen 80
   - server_name "reddit"
   - location / {
       proxy_pass http://127.0.0.1:9292;
     }
  ```

- Добавьте в конфигурацию Terraform открытие 80 порта для инстанса приложения. Для этого добавим к tags "http-server" в /terraform/stage/main.tf
- Добавим вызов роли jdauphant.nginx в плейбук app.yml: { role: jdauphant.nginx }
- Проверим работу приложения на 80 порту

### Работа с Ansible Vault

Для безопасной работы с приватными данными (пароли, приватные ключи и т.д.) используется механизм Ansible Vault.
Данные сохраняются в зашифрованных файлах, которые при выполнении плейбука автоматически расшифровываются. Таким образом, приватные данные можно хранить в системе контроля версий.
Для шифрования используется мастер-пароль (aka vault key). Его нужно передавать команде ansible-playbook при запуске, либо указать файл с ключом в ansible.cfg. Не допускается хранения этого ключ-файла в Git! Необходимо использовать для разных окружений разный vault key.

Команды:

```
ansible-vault encrypt <file> - шифрование файла используя vault.key
ansible-vault edit <file> - редактирование файла
ansible-vault decrypt <file> - расшифровка файла
```

Задание со * - Динамический инвентори
Для использования динамического инвентори применяем gcp_compute.

```
ansible-playbook playbooks/site.yml - будет задействован динамический инвентори для stage окружения
ansible-playbook -i environments/prod/inventory.gcp.yml playbooks/site.yml - будет задействован динамический инвентори для prod окружения
```
Задание с ** - Настройка Travis CI

Было выполнено:
- в .travis.yml дописаны команды установки terraform, packer, tflint, ansible-lint
- для terraform init и подключению к GCS для state реализовано хранение access_token в шифрованной переменной Travis, добавляемой через web интерфейс Travis (gcloud auth application-default print-access-token)
- в .travis.yml добавлена команда запуска скрипта (выполняется только для коммитов в master и PR) для:
```
packer validate для всех шаблонов
terraform validate и tflint для окружений stage и prod
ansible-lint для плейбуков Ansible
```
- в README.md добавлен бейдж с статусом билда
- скрипт копирует .example-файлы в нормальные для проведения тестов

Результат:
```
Packer
Packer: packer/ubuntu16.json validated successfully
Packer: packer/db.json validated successfully
Packer: packer/immutable.json validated successfully
Packer: packer/app.json validated successfully
Ansible Lint
Ansible Lint: ansible/playbooks/packer_app.yml validated successfully
Ansible Lint: ansible/playbooks/packer_db.yml validated successfully
Ansible Lint: ansible/playbooks/app.yml validated successfully
Ansible Lint: ansible/playbooks/db.yml validated successfully
Ansible Lint: ansible/playbooks/reddit_app_multiple_plays.yml validated successfully
Ansible Lint: ansible/playbooks/site.yml validated successfully
Ansible Lint: ansible/playbooks/users.yml validated successfully
Ansible Lint: ansible/playbooks/deploy.yml validated successfully
Ansible Lint: ansible/playbooks/reddit_app_one_play.yml validated successfully
Ansible Lint: ansible/playbooks/clone.yml validated successfully
Initializing modules...
- app in ../modules/app
- db in ../modules/db
- vpc in ../modules/vpc
Initializing the backend...
Successfully configured the backend "gcs"! Terraform will automatically
use this backend unless the backend configuration changes.
Initializing provider plugins...
- Checking for available provider plugins...
- Downloading plugin for provider "google" (hashicorp/google) 2.18.1...
Terraform has been successfully initialized!
You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.
If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
Success! The configuration is valid.
TFLint Stage
TFLint: Stage env validated successfully
Initializing modules...
- app in ../modules/app
- db in ../modules/db
- vpc in ../modules/vpc
Initializing the backend...
Successfully configured the backend "gcs"! Terraform will automatically
use this backend unless the backend configuration changes.
Initializing provider plugins...
- Checking for available provider plugins...
- Downloading plugin for provider "google" (hashicorp/google) 2.18.1...
Terraform has been successfully initialized!
You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.
If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
Success! The configuration is valid.
TFLint Prod
TFLint: Prod env validated successfully
```

## Деплой и управление конфигурацией с Ansible

Чтобы не запушить в репу временные файлы Ansible, добавим в файл .gitignore следующую строку:

```
*.retry
```

Создадим плейбук для управления конфигурацией и деплоя нашего приложения.
Плейбук может состоять из одного или нескольких сценариев (plays).
Сценарий позволяет группировать набор заданий (tasks), который Ansible должен выполнить на конкретном хосте (или группе).
В нашем плейбуке мы будем использовать один сценарий для управления конфигурацией обоих хостов (приложения и БД).

reddit_app_one_play.yml:

```
---
- name: Configure hosts & deploy application # <-- Словесное описание сценария (name)
  hosts: all # <-- Для каких хостов будут выполняться описанные ниже таски (hosts)
  vars:
    mongo_bind_ip: 0.0.0.0 # <-- Переменная задается в блоке vars
    db_host: 10.132.0.10
  tasks: # <-- Блок тасков (заданий), которые будут выполняться для данных хостов
    - name: Change mongo config file
      become: true # <-- Выполнить задание от root
      template:
        src: templates/mongod.conf.j2 # <-- Путь до локального файла-шаблона
        dest: /etc/mongod.conf # <-- Путь на удаленном хосте
        mode: 0644 # <-- Права на файл, которые нужно установить
      tags: db-tag # <-- Список тэгов для задачи
      notify: restart mongod

    - name: Add unit file for Puma
      become: true
      copy:
        src: files/puma.service
        dest: /etc/systemd/system/puma.service
      tags: app-tag
      notify: reload puma

    - name: enable puma
      become: true
      systemd: name=puma enabled=yes
      tags: app-tag

    - name: Add config for DB connection
      template:
        src: templates/db_config.j2
        dest: /home/appuser/db_config
      tags: app-tag

    - name: enable puma
      become: true
      systemd: name=puma enabled=yes
      tags: app-tag

    - name: Fetch the latest version of application code
      git:
        repo: 'https://github.com/express42/reddit.git'
        dest: /home/appuser/reddit
        version: monolith # <-- Указываем нужную ветку
      tags: deploy-tag
      notify: reload puma

    - name: Bundle install
      bundler:
        state: present
        chdir: /home/appuser/reddit # <-- В какой директории выполнить команду bundle
      tags: deploy-tag

  handlers:  # <-- Добавим блок handlers и задачу
  - name: restart mongod
    become: true
    service: name=mongod state=restarted
  - name: reload puma
    become: true
    systemd: name=puma state=restarted
```

Шаблон конфига MongoDB:

```
# Where and how to store data.
storage:
  dbPath: /var/lib/mongodb
  journal:
    enabled: true

# where to write logging data.
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

# network interfaces
net:
  port: {{ mongo_port | default('27017') }}
  bindIp: {{ mongo_bind_ip }}
```  

Шаблон для приложения.
Данный шаблон содержит присвоение переменной DATABASE_URL значения, которое мы передаем через Ansible переменную db_host:

```
DATABASE_URL={{ db_host }}
```

Опции Ansible:

```
--check- позволяет произвести "пробный прогон" плейбука
--limit - ограничиваем группу хостов, для которых применить плейбук
```

Handlers
Handlers похожи на таски, однако запускаются только по оповещению от других задач.
Таск шлет оповещение handler-у в случае, когда он меняет свое состояние.
По этой причине handlers удобно использовать для перезапуска сервисов.
Это, например, позволяет перезапускать сервис, только в случае если поменялся его конфиг-файл.

Проверка плейбука:

```
ansible-playbook reddit_app_one_play.yml --check --limit db --tags db-tag
ansible-playbook reddit_app_one_play.yml --check --limit app --tags app-tag
ansible-playbook reddit_app_one_play.yml --check --limit app --tags deploy-tag
```

Один плейбук, несколько сценариев
reddit_app_multiple_plays.yml:

```
---
- name: Configure MongoDB
  hosts: db
  tags: db-tag
  become: true
  vars:
    mongo_bind_ip: 0.0.0.0
  tasks:
    - name: Change mongo config file
      template:
        src: templates/mongod.conf.j2
        dest: /etc/mongod.conf
        mode: 0644
      notify: restart mongod

  handlers:
  - name: restart mongod
    service: name=mongod state=restarted

- name: Configure Puma
  hosts: app
  tags: app-tag
  become: true
  vars:
   db_host: 10.132.0.12
  tasks:
    - name: Add unit file for Puma
      copy:
        src: files/puma.service
        dest: /etc/systemd/system/puma.service
      notify: reload puma

    - name: Add config for DB connection
      template:
        src: templates/db_config.j2
        dest: /home/appuser/db_config
        owner: appuser
        group: appuser

    - name: enable puma
      systemd: name=puma enabled=yes

  handlers:
  - name: reload puma
    systemd: name=puma state=restarted

- name: Deploy App
  hosts: app
  tags: deploy-tag
  tasks:
    - name: Fetch the latest version of application code
      git:
        repo: 'https://github.com/express42/reddit.git'
        dest: /home/appuser/reddit
        version: monolith
      notify: restart puma

    - name: bundle install
      bundler:
        state: present
        chdir: /home/appuser/reddit

  handlers:
  - name: restart puma
    become: true
    systemd: name=puma state=restarted
```

Проверка работы сценария: ansible-playbook reddit_app_multiple_plays.yml --tags db-tag --check

Несколько плейбуков.

app.yml:

```
---
- name: Configure Puma
  hosts: app
  become: true
  vars:
   db_host: 10.132.0.16
  tasks:
    - name: Add unit file for Puma
      copy:
        src: files/puma.service
        dest: /etc/systemd/system/puma.service
      notify: reload puma

    - name: Add config for DB connection
      template:
        src: templates/db_config.j2
        dest: /home/appuser/db_config
        owner: appuser
        group: appuser

    - name: enable puma
      systemd: name=puma enabled=yes

  handlers:
  - name: reload puma
    systemd: name=puma state=restarted
```

db.yml:

```
---
- name: Configure MongoDB
  hosts: db
  become: true
  vars:
    mongo_bind_ip: 0.0.0.0
  tasks:
    - name: Change mongo config file
      template:
        src: templates/mongod.conf.j2
        dest: /etc/mongod.conf
        mode: 0644
      notify: restart mongod

  handlers:
  - name: restart mongod
    service: name=mongod state=restarted
```

deploy.yml:

```
---
- name: Deploy App
  hosts: app
  tasks:
    - name: Fetch the latest version of application code
      git:
        repo: 'https://github.com/express42/reddit.git'
        dest: /home/appuser/reddit
        version: monolith
      notify: restart puma

    - name: bundle install
      bundler:
        state: present
        chdir: /home/appuser/reddit

  handlers:
  - name: restart puma
    become: true
    systemd: name=puma state=restarted
```

Создадим файл site.yml, в котором опишем управление конфигурацией всей нашей инфраструктуры.
Это будет нашим главным плейбуком, который будет включать в себя все остальные.

site.yml:

```
---
- import_playbook: db.yml
- import_playbook: app.yml
- import_playbook: deploy.yml
```

Проверка и выполнение:

```
ansible-playbook site.yml --check
ansible-playbook site.yml
```

Провижининг в Packer.
Интегрируем Ansible в Packer.

packer_app.yml:

```
---
- name: Install Ruby && Bundler
  hosts: all
  become: true
  tasks:
  - name: Install ruby and rubygems and required packages
    apt: "name={{ item }} state=present"
    with_items:
      - ruby-full
      - ruby-bundler
      - build-essential
```

packer_db.yml:

```
---
- name: Install MongoDB 3.2
  hosts: all
  become: true
  tasks:
  # Добавим ключ репозитория для последующей работы с ним
  - name: Add APT key
    apt_key:
      id: EA312927
      keyserver: keyserver.ubuntu.com

  # Подключаем репозиторий с пакетами mongodb
  - name: Add APT repository
    apt_repository:
      repo: deb [ arch=amd64,arm64 ] http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.2 multiverse
      state: present

  # Выполним установку пакета
  - name: Install mongodb package
    apt:
      name: mongodb-org
      state: present

  # Включаем сервис
  - name: Configure service supervisor
    systemd:
      name: mongod
      enabled: yes
```

Заменим секцию Provision в образе packer/app.json на Ansible:

```
"provisioners": [
  {  
    "type": "ansible",
    "playbook_file": "ansible/packer_app.yml"
  }
]
```

Такие же изменения выполним и для packer/db.json:

```
"provisioners": [
  {
    "type": "ansible",
    "playbook_file": "ansible/packer_db.yml"
  }
]
```

Выполним билд образов из корня репозитория.

Задание со *
Для использования динамического инвентори применяем gcp_compute.
Для начала добавляем google-auth>=1.3.0 в requirements.txt.

Генерируем json service account key

```
gcloud iam service-accounts keys create ~/key.json \
   --iam-account [SA-NAME]@[PROJECT-ID].iam.gserviceaccount.com
```

Пример inventory.gcp.yml:

```
---
plugin: gcp_compute  
projects:
  - infra-253207 # id gcp проекта
regions:
  - europe-west1 # регион
hostnames:
  - name # обозначение хостов, может быть: public_ip, private_ip или name
groups:
  app: "'-app' in name" # группирование хостов по именам
  db:  "'-db' in name"
compose:
  ansible_host: networkInterfaces[0].accessConfigs[0].natIP # внешний IP хоста
  internal_ip:  networkInterfaces[0].networkIP # внутренний IP хоста
filters: []
auth_kind: serviceaccount
service_account_file: /root/key.json # Service account json keyfile
```

Просмотр дерева хостов: ansible-inventory -i inventory.gcp.yml --graph

```
@all:
  |--@app:
  |  |--reddit-app
  |--@db:
  |  |--reddit-db
  |--@ungrouped:
```

Просмотр динамического инвентори json: ansible-inventory -i inventory.gcp.yml --list

Применение динамического инвентори по умолчанию (ansible.cfg):

```
[defaults]
inventory = ./inventory.gcp.yml
```

Выполнение: ansible -i inventory.gcp.yml all -m ping

```
reddit-app | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}
reddit-db | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}
```

Пример применения динамического инвентори в плейбуке:

```
---
- name: Configure Puma
  hosts: app
  become: true
  vars:
    db_host: "{{ hostvars['reddit-db'].internal_ip }}"
  tasks:
    - name: Add unit file for Puma
      copy:
        src: files/puma.service
        dest: /etc/systemd/system/puma.service
      notify: reload puma

    - name: Add config for DB connection
      template:
        src: templates/db_config.j2
        dest: /home/appuser/db_config
        owner: appuser
        group: appuser

    - name: enable puma
      systemd: name=puma enabled=yes

  handlers:
  - name: reload puma
    systemd: name=puma state=restarted
```

## Знакомство с Ansible

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

Устанавлием ansible:

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

Простой плейбук inventory.yml:

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

Использование YAML inventory:

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

- пишет inventory.py скрипт:
  
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

- в ansible.cfg меняем значение для inventory на ./inventory.sh:

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
При запуске скрипта с параметром --host hostname (где hostname это один из хостов), скрипт должен вернуть JSON с переменными для этого хоста.
Также можно использовать элемент _meta, в котором перечислены все переменные для хостов.

## Принципы организации инфраструктурного кода и работа над инфраструктурой на примере Terraform

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

## Практика IaC с использованием Terraform

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

## Сборка образов VM при помощи Packer

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

## Деплой тестового приложения в GCP

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

## GCP

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
