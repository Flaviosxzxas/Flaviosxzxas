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

POSTFWD_CONF="/etc/postfix/postfwd.cf"

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
echo "Continuando a execução do script...

# Criar usuário e grupo 'postfwd', se necessário
if ! id "postfwd" &>/dev/null; then
    echo "Usuário 'postfwd' não encontrado. Tentando criar..."
    
    # Tentar criar o grupo 'postfwd'
    if ! getent group postfwd &>/dev/null; then
        sudo groupadd postfwd || { echo "Erro ao criar grupo 'postfwd'. Verificando novamente..."; }
    fi

    # Tentar criar o usuário 'postfwd'
    sudo useradd -r -g postfwd -s /usr/sbin/nologin postfwd || {
        echo "Erro ao criar usuário 'postfwd'. Verificando novamente..."
    }
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
    sudo groupadd nobody || { echo "Erro ao criar grupo 'nobody'."; exit 1; }
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

# Verificar se o arquivo de configuração do Postfwd existe
if [ ! -f "$POSTFWD_CONF" ]; then
    echo "Arquivo $POSTFWD_CONF não encontrado. Criando..."
    sudo tee "$POSTFWD_CONF" > /dev/null <<EOF
pidfile=/run/postfwd/postfwd.pid
#######################################################
# Regras de Controle de Limites por Servidor
#######################################################
# KingHost
id=limit-kinghost
pattern=recipient mx=.*kinghost.net
action="rate(global\/300\/3600) defer_if_permit \"Limite de 300 e-mails por hora atingido para KingHost.\""

# UOL Host
id=limit-uolhost
pattern=recipient mx=.*uhserver
action="rate(global\/300\/3600) defer_if_permit \"Limite de 300 e-mails por hora atingido para UOL Host.\""

# LocaWeb
id=limit-locaweb
pattern=recipient mx=.*locaweb.com.br
action="rate(global\/500\/3600) defer_if_permit \"Limite de 500 e-mails por hora atingido para LocaWeb.\""

# Yahoo (Contas Pessoais)
id=limit-yahoo
pattern=recipient mx=.*yahoo.com
action="rate(global\/150\/3600) defer_if_permit \"Limite de 150 e-mails por hora atingido para Yahoo.\""

# Mandic
id=limit-mandic
pattern=recipient mx=.*mandic.com.br
action="rate(global\/200\/3600) defer_if_permit \"Limite de 200 e-mails por hora atingido para Mandic.\""

# Titan
id=limit-titan
pattern=recipient mx=.*titan.email
action="rate(global\/500\/3600) defer_if_permit \"Limite de 500 e-mails por hora atingido para Titan.\""

# Google (Contas Pessoais e G Suite)
id=limit-google
pattern=recipient mx=.*google
action="rate(global\/2000\/3600) defer_if_permit \"Limite de 2000 e-mails por hora atingido para Google.\""

# Hotmail (Contas Pessoais)
id=limit-hotmail
pattern=recipient mx=.*hotmail.com
action="rate(global\/1000\/86400) defer_if_permit \"Limite de 1000 e-mails por dia atingido para Hotmail.\""

# Office 365 (Contas Empresariais)
id=limit-office365
pattern=recipient mx=.*outlook.com
action="rate(global\/2000\/3600) defer_if_permit \"Limite de 2000 e-mails por hora atingido para Office 365.\""

# Secureserver (GoDaddy)
id=limit-secureserver
pattern=recipient mx=.*secureserver.net
action="rate(global\/300\/3600) defer_if_permit \"Limite de 300 e-mails por hora atingido para GoDaddy.\""

# Zimbra
id=limit-zimbra
pattern=recipient mx=.*zimbra
action="rate(global\/400\/3600) defer_if_permit \"Limite de 400 e-mails por hora atingido para Zimbra.\""

# Provedores na Argentina
# Fibertel
id=limit-fibertel
pattern=recipient mx=.*fibertel.com.ar
action="rate(global\/200\/3600) defer_if_permit \"Limite de 200 e-mails por hora atingido para Fibertel.\""

# Speedy
id=limit-speedy
pattern=recipient mx=.*speedy.com.ar
action="rate(global\/200\/3600) defer_if_permit \"Limite de 200 e-mails por hora atingido para Speedy.\""

# Personal (Arnet)
id=limit-personal
pattern=recipient mx=.*personal.com.ar
action="rate(global\/200\/3600) defer_if_permit \"Limite de 200 e-mails por hora atingido para Personal (Arnet).\""

# Telecom
id=limit-telecom
pattern=recipient mx=.*telecom.com.ar
action="rate(global\/200\/3600) defer_if_permit \"Limite de 200 e-mails por hora atingido para Telecom.\""

# Claro
id=limit-claro
pattern=recipient mx=.*claro.com.ar
action="rate(global\/200\/3600) defer_if_permit \"Limite de 200 e-mails por hora atingido para Claro.\""

# Provedores no México
# Telmex
id=limit-telmex
pattern=recipient mx=.*prodigy.net.mx
action="rate(global\/200\/3600) defer_if_permit \"Limite de 200 e-mails por hora atingido para Telmex.\""

# Axtel
id=limit-axtel
pattern=recipient mx=.*axtel.net
action="rate(global\/200\/3600) defer_if_permit \"Limite de 200 e-mails por hora atingido para Axtel.\""

# Izzi Telecom
id=limit-izzi
pattern=recipient mx=.*izzi.net.mx
action="rate(global\/200\/3600) defer_if_permit \"Limite de 200 e-mails por hora atingido para Izzi Telecom.\""

# Megacable
id=limit-megacable
pattern=recipient mx=.*megacable.com.mx
action="rate(global\/200\/3600) defer_if_permit \"Limite de 200 e-mails por hora atingido para Megacable.\""

# TotalPlay
id=limit-totalplay
pattern=recipient mx=.*totalplay.net.mx
action="rate(global\/200\/3600) defer_if_permit \"Limite de 200 e-mails por hora atingido para TotalPlay.\""

# Telcel
id=limit-telcel
pattern=recipient mx=.*telcel.net
action="rate(global\/200\/3600) defer_if_permit \"Limite de 200 e-mails por hora atingido para Telcel.\""

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

