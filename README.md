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
