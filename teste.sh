#!/bin/bash

# Caminho do arquivo de configuração do Postfwd
POSTFWD_CONF="/etc/postfix/postfwd.cf"

# Criar usuário 'postfw' e associar ao grupo 'postfix'
if ! id "postfw" &>/dev/null; then
    echo "Criando usuário 'postfw'..."
    sudo useradd -r -g postfix -s /usr/sbin/nologin postfw || { echo "Erro ao criar usuário 'postfw'."; exit 1; }
else
    echo "Usuário 'postfw' já existe."
fi

# Verificar se o postfwd está instalado
if ! command -v postfwd &>/dev/null; then
    echo "Postfwd não encontrado. Instalando..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt update && sudo apt install postfwd -y || { echo "Erro ao instalar o postfwd."; exit 1; }
fi

# Verificar e corrigir permissões do arquivo de configuração
if [ -f "$POSTFWD_CONF" ]; then
    sudo chown root:postfix "$POSTFWD_CONF"
    sudo chmod 640 "$POSTFWD_CONF"
else
    echo "Erro: Arquivo $POSTFWD_CONF não encontrado. Verifique a instalação do Postfwd."
    exit 1
fi

# Corrigir permissões do diretório /var/tmp
sudo mkdir -p /var/tmp
sudo chmod 1777 /var/tmp

# Criar arquivo de serviço systemd, se não existir
if [ ! -f /etc/systemd/system/postfwd.service ]; then
    echo "Criando arquivo de serviço systemd para postfwd..."
    sudo tee /etc/systemd/system/postfwd.service > /dev/null <<EOF
[Unit]
Description=Postfwd - Postfix Policy Server
After=network.target postfix.service
Requires=postfix.service

[Service]
ExecStart=/usr/sbin/postfwd
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=/var/run/postfwd/postfwd.pid
Restart=on-failure
User=postfw
Group=postfix

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable postfwd
else
    echo "Arquivo de serviço systemd já existe."
fi

# Adicionar regras ao arquivo postfwd.cf
if grep -q "id=limit-kinghost" "$POSTFWD_CONF"; then
    echo "Regras já configuradas no $POSTFWD_CONF."
else
    echo "Adicionando regras ao arquivo postfwd.cf..."
    sudo tee -a "$POSTFWD_CONF" > /dev/null <<EOF
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
action=rate(global/200/3600) defer_if_permit "Limite de 200 e-mails por hora atingido para Personal (Arnet)."

# Telecom
id=limit-telecom
pattern=recipient mx=.*telecom.com.ar
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

# Iniciar e verificar o serviço postfwd
sudo systemctl start postfwd || { echo "Erro ao iniciar o serviço postfwd."; exit 1; }
sudo systemctl restart postfix || { echo "Erro ao reiniciar o Postfix."; exit 1; }
sudo systemctl restart postfwd || { echo "Erro ao reiniciar o serviço postfwd."; exit 1; }
sudo systemctl status postfwd --no-pager || { echo "Verifique manualmente o status do serviço postfwd."; exit 1; }

echo "Configuração do Postfwd concluída com sucesso!"
