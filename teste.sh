#!/bin/bash

# Verifique se o script está sendo executado como root
if [ "$(id -u)" -ne 0 ]; then
  echo "Este script precisa ser executado como root."
  exit 1
fi

# Atualizar a lista de pacotes e atualizar pacotes
echo "Atualizando a lista de pacotes..."
sudo apt-get update
sudo apt-get upgrade -y

# Definir variáveis principais
ServerName=$1
CloudflareAPI=$2
CloudflareEmail=$3

Domain=$(echo $ServerName | cut -d "." -f2-)
DKIMSelector=$(echo $ServerName | awk -F[.:] '{print $1}')
ServerIP=$(wget -qO- http://ip-api.com/line\?fields=query)

echo "Configurando Servidor: $ServerName"
echo "Domain: $Domain"
echo "DKIMSelector: $DKIMSelector"
echo "ServerIP: $ServerIP"

sleep 5

# Função para garantir que as dependências necessárias estejam instaladas
install_dependencies() {
    echo "Instalando dependências necessárias..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update -y || { echo "Erro ao atualizar o repositório"; exit 1; }

    # Verificar se o repositório universe está habilitado e habilitá-lo se necessário
    if ! grep -q "^deb .*universe" /etc/apt/sources.list; then
        echo "Habilitando repositório 'universe'..."
        sudo apt-add-repository "deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc) universe" -y || { echo "Erro ao habilitar repositório 'universe'"; exit 1; }
        sudo apt-get update -y || { echo "Erro ao atualizar repositórios"; exit 1; }
    fi

    # Instalar pacotes via apt-get
    echo "Instalando pacotes necessários via apt-get..."
    if ! sudo apt-get install -y postfwd libsys-syslog-perl libnet-cidr-perl libmail-sender-perl libdata-dumper-perl libnet-dns-perl libmime-tools-perl liblog-any-perl perl postfix; then
        echo "Erro ao instalar dependências com apt-get. Tentando instalar pacotes Perl via CPAN." >&2

        # Verificar se o CPAN está instalado
        if ! command -v cpan &> /dev/null; then
            echo "CPAN não encontrado, instalando..."
            sudo apt-get install -y perl || { echo "Erro ao instalar Perl."; exit 1; }
            sudo cpan install Data::Dumper || { echo "Erro ao instalar Data::Dumper via CPAN."; exit 1; }
        else
            echo "Instalando pacotes Perl necessários via CPAN..."
            sudo cpan install Data::Dumper || { echo "Erro ao instalar Data::Dumper via CPAN."; exit 1; }
            sudo cpan install Sys::Syslog || { echo "Erro ao instalar Sys::Syslog via CPAN."; exit 1; }
            sudo cpan install Net::CIDR || { echo "Erro ao instalar Net::CIDR via CPAN."; exit 1; }
            sudo cpan install Mail::Sender || { echo "Erro ao instalar Mail::Sender via CPAN."; exit 1; }
            sudo cpan install Net::DNS || { echo "Erro ao instalar Net::DNS via CPAN."; exit 1; }
            sudo cpan install MIME::Tools || { echo "Erro ao instalar MIME::Tools via CPAN."; exit 1; }
            sudo cpan install Log::Any || { echo "Erro ao instalar Log::Any via CPAN."; exit 1; }
        fi
    fi
}

# Verificar se as dependências estão instaladas
echo "Verificando dependências..."
if ! dpkg -l | grep -q postfwd; then
    install_dependencies
else
    echo "Postfwd e dependências já instalados."
fi

# Continuar execução após instalação de dependências ou após erro
echo "Continuando a execução do script..."

# Criar usuário e grupo 'postfwd', se necessário
if ! id "postfwd" &>/dev/null; then
    echo "Usuário 'postfwd' não encontrado. Tentando criar..."
    
    # Tentar criar o grupo 'postfwd'
    if ! getent group postfwd &>/dev/null; then
        sudo groupadd postfwd || { echo "Erro ao criar grupo 'postfwd'. Abortando..."; exit 1; }
    fi

    # Tentar criar o usuário 'postfwd'
    sudo useradd -r -g postfwd -s /usr/sbin/nologin postfwd || { echo "Erro ao criar usuário 'postfwd'. Abortando..."; exit 1; }
fi

# Verificar novamente se o usuário foi criado
if ! id "postfwd" &>/dev/null; then
    echo "Usuário 'postfwd' não foi criado corretamente. Tentando solução alternativa..."
    
    # Tentar recriar tudo
    sudo groupdel postfwd &>/dev/null || true # Excluir o grupo, se ele estiver corrompido
    sudo userdel postfwd &>/dev/null || true # Excluir o usuário, se ele estiver corrompido
    
    # Criar novamente o grupo e o usuário
    sudo groupadd postfwd || { echo "Erro crítico ao criar grupo 'postfwd'. Abortando..."; exit 1; }
    sudo useradd -r -g postfwd -s /usr/sbin/nologin postfwd || { echo "Erro crítico ao criar usuário 'postfwd'. Abortando..."; exit 1; }
fi

# Mensagem de sucesso após garantir a criação
echo "Usuário e grupo 'postfwd' configurados com sucesso."

# Garantir que o grupo 'nobody' exista
if ! getent group nobody &>/dev/null; then
    echo "Criando grupo 'nobody'..."
    sudo groupadd nobody || { echo "Erro ao criar grupo 'nobody'. Abortando..."; exit 1; }
else
    echo "Grupo 'nobody' já existe."
fi

# Instalar Postfwd, se não estiver instalado
if ! command -v postfwd &>/dev/null; then
    echo "Postfwd não encontrado. Instalando..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update -y && sudo apt-get install -y postfwd || { echo "Erro ao instalar o postfwd."; exit 1; }
else
    echo "Postfwd já está instalado."
fi

POSTFWD_CONF="/etc/postfix/postfwd.cf"

# Criar arquivo de configuração do Postfwd
if [ ! -f "$POSTFWD_CONF" ]; then
    echo "Criando arquivo de configuração do Postfwd..."
    cat <<EOF > "$POSTFWD_CONF"
pidfile=/run/postfwd/postfwd.pid
#######################################################
# Regras de Controle de Limites por Servidor
#######################################################
# KingHost
id=limit-kinghost
pattern=recipient mx=.*kinghost.net
action=rate(global/300/3600) defer_if_permit "Limite de 300 e-mails por hora atingido para KingHost."

# UOL Host
id=limit-uolhost
pattern=recipient mx=.*uhserver
action=rate(global/300/3600) defer_if_permit "Limite de 300 e-mails por hora atingido para UOL Host."

# LocaWeb
id=limit-locaweb
pattern=recipient mx=.*locaweb.com.br
action=rate(global/500/3600) defer_if_permit "Limite de 500 e-mails por hora atingido para LocaWeb."

# Yahoo (Contas Pessoais)
id=limit-yahoo
pattern=recipient mx=.*yahoo.com
action=rate(global/150/3600) defer_if_permit "Limite de 150 e-mails por hora atingido para Yahoo."

# Mandic
id=limit-mandic
pattern=recipient mx=.*mandic.com.br
action=rate(global/200/3600) defer_if_permit "Limite de 200 e-mails por hora atingido para Mandic."

# Titan
id=limit-titan
pattern=recipient mx=.*titan.email
action=rate(global/500/3600) defer_if_permit "Limite de 500 e-mails por hora atingido para Titan."

# Google (Contas Pessoais e G Suite)
id=limit-google
pattern=recipient mx=.*google
action=rate(global/2000/3600) defer_if_permit "Limite de 2000 e-mails por hora atingido para Google."

# Hotmail (Contas Pessoais)
id=limit-hotmail
pattern=recipient mx=.*hotmail.com
action=rate(global/1000/86400) defer_if_permit "Limite de 1000 e-mails por dia atingido para Hotmail."

# Office 365 (Contas Empresariais)
id=limit-office365
pattern=recipient mx=.*outlook.com
action=rate(global/2000/3600) defer_if_permit "Limite de 2000 e-mails por hora atingido para Office 365."

# Secureserver (GoDaddy)
id=limit-secureserver
pattern=recipient mx=.*secureserver.net
action=rate(global/300/3600) defer_if_permit "Limite de 300 e-mails por hora atingido para GoDaddy."

# Zimbra
id=limit-zimbra
pattern=recipient mx=.*zimbra
action=rate(global/400/3600) defer_if_permit "Limite de 400 e-mails por hora atingido para Zimbra."

# Provedores na Argentina
# Fibertel
id=limit-fibertel
pattern=recipient mx=.*fibertel.com.ar
action=rate(global/200/3600) defer_if_permit "Limite de 200 e-mails por hora atingido para Fibertel."

# Speedy
id=limit-speedy
pattern=recipient mx=.*speedy.com.ar
action=rate(global/200/3600) defer_if_permit "Limite de 200 e-mails por hora atingido para Speedy."

# Personal (Arnet)
id=limit-personal
pattern=recipient mx=.*personal.com.ar
action=rate(global/200/3600) defer_if_permit "Limite de 200 e-mails por hora atingido para Personal Arnet."

# Telecom
id=limit-telecom
pattern=recipient mx=.*telecom.com .ar
action=rate(global/200/3600) defer_if_permit "Limite de 200 e-mails por hora atingido para Telecom."

# Claro
id=limit-claro
pattern=recipient mx=.*claro.com.ar
action=rate(global/200/3600) defer_if_permit "Limite de 200 e-mails por hora atingido para Claro."

# Provedores no México
# Telmex
id=limit-telmex
pattern=recipient mx=.*prodigy.net.mx
action=rate(global/200/3600) defer_if_permit "Limite de 200 e-mails por hora atingido para Telmex."

# Axtel
id=limit-axtel
pattern=recipient mx=.*axtel.net
action=rate(global/200/3600) defer_if_permit "Limite de 200 e-mails por hora atingido para Axtel."

# Izzi Telecom
id=limit-izzi
pattern=recipient mx=.*izzi.net.mx
action=rate(global/200/3600) defer_if_permit "Limite de 200 e-mails por hora atingido para Izzi Telecom."

# Megacable
id=limit-megacable
pattern=recipient mx=.*megacable.com.mx
action=rate(global/200/3600) defer_if_permit "Limite de 200 e-mails por hora atingido para Megacable."

# TotalPlay
id=limit-totalplay
pattern=recipient mx=.*totalplay.net.mx
action=rate(global/200/3600) defer_if_permit "Limite de 200 e-mails por hora atingido para TotalPlay."

# Telcel
id=limit-telcel
pattern=recipient mx=.*telcel.net
action=rate(global/200/3600) defer_if_permit "Limite de 200 e-mails por hora atingido para Telcel."

# Outros (Sem Limite)
id=no-limit
pattern=recipient
action=permit
EOF
fi

# Criar e ajustar permissões do diretório de PID
echo "Criando e ajustando permissões do diretório de PID..."
sudo mkdir -p "/var/run/postfwd" || { echo "Erro ao criar diretório /var/run/postfwd."; exit 1; }
sudo chown postfwd:postfwd "/var/run/postfwd" || { echo "Erro ao ajustar proprietário do diretório /var/run/postfwd."; exit 1; }
sudo chmod 750 "/var/run/postfwd" || { echo "Erro ao ajustar permissões do diretório /var/run/postfwd."; exit 1; }

# Criar e ajustar permissões do diretório temporário para cache
echo "Criando e ajustando permissões do diretório temporário para cache..."
sudo mkdir -p "/var/tmp/postfwd" || { echo "Erro ao criar diretório /var/tmp/postfwd."; exit 1; }
sudo chown postfwd:postfwd "/var/tmp/postfwd" || { echo "Erro ao ajustar proprietário do diretório /var/tmp/postfwd."; exit 1; }
sudo chmod 750 "/var/tmp/postfwd" || { echo "Erro ao ajustar permissões do diretório /var/tmp/postfwd."; exit 1; }

echo "Permissões ajustadas com sucesso!"

# Criar arquivo de serviço systemd, se não existir
if [ ! -f /etc/systemd/system/postfwd.service ]; then
    echo "Criando arquivo de serviço systemd para postfwd..."
    sudo tee /etc/systemd/system/postfwd.service > /dev/null <<EOF
[Unit]
Description=Postfwd - Postfix Policy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/postfwd -f /etc/postfix/postfwd.cf -vv --pidfile /run/postfwd/postfwd.pid
PIDFile=/run/postfwd/postfwd.pid
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable postfwd
else
    echo "Arquivo de serviço systemd já existe."
fi

# Adicionar Postfwd ao master.cf, se ainda não estiver presente
echo "Verificando se a entrada do Postfwd já está presente no /etc/postfix/master.cf..."
if ! grep -q "127.0.0.1:10040 inet" /etc/postfix/master.cf; then
    echo "Adicionando entrada do Postfwd ao /etc/postfix/master.cf..."
    sudo tee -a /etc/postfix/master.cf > /dev/null <<EOF

# Postfwd Policy Server
127.0.0.1:10040 inet  n  -  n  -  1  spawn
  user=postfwd argv=/usr/sbin/postfwd2 -f /etc/postfix/postfwd.cf
EOF
    echo "Entrada adicionada com sucesso!"
else
    echo "A entrada do Postfwd já existe no /etc/postfix/master.cf."
fi

# Iniciar e verificar o serviço postfwd
sudo systemctl start postfwd || { echo "Erro ao iniciar o serviço postfwd."; exit 1; }
sudo systemctl restart postfix || { echo "Erro ao reiniciar o Postfix."; exit 1; }
sudo systemctl restart postfwd || { echo "Erro ao reiniciar o serviço postfwd."; exit 1; }

# Verificar o status do serviço
sudo systemctl status postfwd --no-pager || { echo "Verifique manualmente o status do serviço postfwd."; exit 1; }

echo "Configuração do Postfwd concluída com sucesso!"



echo "==================================================== POSTFIX ===================================================="

echo "==================================================== OpenDMARC ===================================================="

# Configurar o debconf para modo não interativo globalmente
export DEBIAN_FRONTEND=noninteractive

# Criar os diretórios necessários para o OpenDMARC
sudo mkdir -p /run/opendmarc
sudo mkdir -p /etc/opendmarc
sudo mkdir -p /var/log/opendmarc
sudo mkdir -p /var/lib/opendmarc

# Ajustar permissões e propriedade dos diretórios
sudo chown opendmarc:opendmarc /run/opendmarc
sudo chmod 750 /run/opendmarc
sudo chown opendmarc:opendmarc /etc/opendmarc
sudo chmod 750 /etc/opendmarc
sudo chown opendmarc:opendmarc /var/log/opendmarc
sudo chmod 750 /var/log/opendmarc
sudo chown opendmarc:opendmarc /var/lib/opendmarc
sudo chmod 750 /var/lib/opendmarc

# Criar o arquivo de configuração do OpenDMARC
sudo tee /etc/opendmarc.conf > /dev/null <<EOF
# Configuração de logs
Syslog true

# Definição do socket onde o OpenDMARC escuta
Socket inet:54321@localhost

# Definição do arquivo PID para controle do processo
PidFile /run/opendmarc/opendmarc.pid

# ID do autenticador usado nos cabeçalhos de autenticação
AuthservID OpenDMARC

# Localização do arquivo de hosts a serem ignorados
IgnoreHosts /etc/opendmarc/ignore.hosts

# Definição de se rejeitar falhas de DMARC
RejectFailures false

# IDs de servidores de autenticação confiáveis
TrustedAuthservIDs ${ServerName}

# Arquivo de histórico para relatórios detalhados
HistoryFile /var/lib/opendmarc/opendmarc.dat
EOF

# Criar o arquivo de hosts a serem ignorados se não existir
sudo touch /etc/opendmarc/ignore.hosts
sudo chown opendmarc:opendmarc /etc/opendmarc/ignore.hosts
sudo chmod 644 /etc/opendmarc/ignore.hosts

# Criar o arquivo de histórico do OpenDMARC
sudo touch /var/lib/opendmarc/opendmarc.dat
sudo chown opendmarc:opendmarc /var/lib/opendmarc/opendmarc.dat
sudo chmod 644 /var/lib/opendmarc/opendmarc.dat

# Criar o arquivo PID do OpenDMARC
sudo touch /run/opendmarc/opendmarc.pid
sudo chown opendmarc:opendmarc /run/opendmarc/opendmarc.pid
sudo chmod 600 /run/opendmarc/opendmarc.pid

# Configurar e reiniciar o OpenDKIM
sudo systemctl restart opendkim
wait # adiciona essa linha para esperar que o comando seja concluído

# Configurar e reiniciar o OpenDMARC
sudo systemctl restart opendmarc
wait # adiciona essa linha para esperar que o comando seja concluído

echo "==================================================== OpenDMARC ===================================================="

echo "==================================================== CLOUDFLARE ===================================================="

# Gerar código DKIM
DKIMCode=$(/root/dkimcode.sh)

# Obter o ID da zona do Cloudflare
echo "  -- Obtendo Zona"
CloudflareZoneID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$Domain&status=active" \
  -H "X-Auth-Email: $CloudflareEmail" \
  -H "X-Auth-Key: $CloudflareAPI" \
  -H "Content-Type: application/json" | jq -r '.result[0].id')

if [ -z "$CloudflareZoneID" ]; then
  echo "Erro: Não foi possível obter o ID da zona do Cloudflare." >&2
  exit 1
fi

# Função para obter detalhes de um registro existente
get_record_details() {
  local record_name=$1
  local record_type=$2
  curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CloudflareZoneID/dns_records?name=$record_name&type=$record_type" \
    -H "X-Auth-Email: $CloudflareEmail" \
    -H "X-Auth-Key: $CloudflareAPI" \
    -H "Content-Type: application/json"
}

# Função para criar ou atualizar registros DNS
create_or_update_record() {
  local record_name=$1
  local record_type=$2
  local record_content=$3
  local record_ttl=120
  local record_priority=$4
  local record_proxied=false

  # Obter os detalhes do registro existente
  response=$(get_record_details "$record_name" "$record_type")
  existing_content=$(echo "$response" | jq -r '.result[0].content')
  existing_ttl=$(echo "$response" | jq -r '.result[0].ttl')
  existing_priority=$(echo "$response" | jq -r '.result[0].priority')

  # Verificar se o registro está atualizado
  if [ "$record_type" == "MX" ] && [ "$existing_content" == "$record_content" ] && [ "$existing_ttl" -eq "$record_ttl" ] && [ "$existing_priority" -eq "$record_priority" ]; then
    echo "Registro $record_type para $record_name já está atualizado. Pulando."
  elif [ "$record_type" != "MX" ] && [ "$existing_content" == "$record_content" ] && [ "$existing_ttl" -eq "$record_ttl" ]; then
    echo "Registro $record_type para $record_name já está atualizado. Pulando."
  else
    echo "  -- Criando ou atualizando registro $record_type para $record_name"
    if [ "$record_type" == "MX" ]; then
      data=$(jq -n --arg type "$record_type" --arg name "$record_name" --arg content "$record_content" --arg ttl "$record_ttl" --argjson proxied "$record_proxied" --arg priority "$record_priority" \
            '{type: $type, name: $name, content: $content, ttl: ($ttl | tonumber), proxied: $proxied, priority: ($priority | tonumber)}')
    else
      data=$(jq -n --arg type "$record_type" --arg name "$record_name" --arg content "$record_content" --arg ttl "$record_ttl" --argjson proxied "$record_proxied" \
            '{type: $type, name: $name, content: $content, ttl: ($ttl | tonumber), proxied: $proxied}')
    fi

    # Verificar se o JSON foi gerado corretamente
    if [ -z "$data" ]; then
      echo "Erro ao gerar o corpo do JSON. Verifique as variáveis." >&2
      return 1
    fi

    # Enviar a solicitação para criar ou atualizar o registro
    response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CloudflareZoneID/dns_records" \
         -H "X-Auth-Email: $CloudflareEmail" \
         -H "X-Auth-Key: $CloudflareAPI" \
         -H "Content-Type: application/json" \
         --data "$data")

    echo "$response"
  fi
}

# Criar ou atualizar registros DNS
echo "  -- Configurando registros DNS"
create_or_update_record "$DKIMSelector" "A" "$ServerIP" ""
create_or_update_record "$ServerName" "TXT" "\"v=spf1 a:$ServerName ~all\"" ""
#create_or_update_record "_dmarc.$ServerName" "TXT" "\"v=DMARC1; p=quarantine; sp=quarantine; rua=mailto:dmarc@$ServerName; rf=afrf; fo=0:1:d:s; ri=86000; adkim=r; aspf=r\"" ""
create_or_update_record "_dmarc.$ServerName" "TXT" "\"v=DMARC1; p=reject; rua=mailto:dmarc-reports@$ServerName; ruf=mailto:dmarc-reports@$ServerName; sp=reject; adkim=s; aspf=s\"" ""

# Atualização para garantir que o DKIM seja uma única string
DKIMCode=$(echo "$DKIMCode" | tr -d '\n' | tr -s ' ')  # Limpar quebras de linha e espaços extras
EscapedDKIMCode=$(printf '%s' "$DKIMCode" | sed 's/\"/\\\"/g')
create_or_update_record "mail._domainkey.$ServerName" "TXT" "\"v=DKIM1; h=sha256; k=rsa; p=$EscapedDKIMCode\"" ""

create_or_update_record "$ServerName" "MX" "$ServerName" "10"
echo "==================================================== APPLICATION ===================================================="

# Instala Apache, PHP e módulos necessários
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install apache2 php php-cli php-dev php-curl php-gd libapache2-mod-php --assume-yes
wait # adiciona essa linha para esperar que o comando seja concluído

# Verifica a existência do diretório /var/www/html
if [ ! -d "/var/www/html" ]; then
    echo "Folder /var/www/html does not exist"
    exit 1
fi

# Remove o arquivo index.html se existir
sudo rm -f /var/www/html/index.html

# Adiciona o código PHP ao arquivo index.php
echo "<?php
header('HTTP/1.0 403 Forbidden');
http_response_code(401);
exit();
?>" | sudo tee /var/www/html/index.php > /dev/null

# Instala a extensão php-mbstring
sudo apt-get install php-mbstring -y

# Reinicia o serviço Apache
sudo /etc/init.d/apache2 restart

echo "==================================================== APPLICATION ===================================================="

echo "================================= Todos os comandos foram executados com sucesso! ==================================="

echo "======================================================= FIM =========================================================="

echo "================================================= Reiniciar servidor ================================================="
# Verificar se o reboot é necessário
if [ -f /var/run/reboot-required ]; then
  echo "Reiniciando o servidor em 5 segundos devido a atualizações críticas..."
  sleep 5
  sudo reboot
else
  echo "Reboot não necessário. Finalizando o script."
fi
