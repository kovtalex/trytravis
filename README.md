# kovtalex_infra
kovtalex Infra repository

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
ssh -i ~/.ssh/appuser appuser@34.90.214.206
```

Подключение к someinternalhost с локальной машины реализуем черем SSH Agent Forwarding:
```
eval `ssh-agent -s`
ssh-add -L
ssh-add ~/.ssh/appuser
ssh -i ~/.ssh/appuser -A appuser@34.90.214.206
ssh 10.164.0.4
```

Подключение к someinternalhost в одну команду:
```
ssh -i ~/.ssh/appuser -tt -A appuser@34.90.214.206 ssh appuser@10.164.0.4
```


Подключение к someinternalhost по алиасу реализуем с помощью внесения конфигурации в ~/.ssh/config :
```
host someinternalhost
     hostname 10.164.0.4
     user appuser
     ProxyCommand ssh appuser@34.90.214.206 -W %h:%p
```

Для доступа к частной сети через bastion используем VPN сервер Pritunl:
```
Разрешаем http и https трафик на брандмауэре GCP для bastion
sudo bash setupvpn.sh
Настраиваем Pritunl https://34.90.214.206/setup
```

После полной настройки Pritunl проверяем работоспособность:
```
openvpn --config cloud-bastion.ovpn
ssh -i ~/.ssh/appuser appuser@10.164.0.4
```

Устанавливаем валидный сертификат для панели управления Pritunl с помощью сервисов sslip.io и Lets's Encrypt указав доменное имя 34.90.214.206.sslip.io в настройках VPN сервера.

Данные для проверки VPN:
```
bastion_IP = 34.90.214.206
someinternalhost_IP = 10.164.0.4
```
