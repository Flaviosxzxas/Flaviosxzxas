#!/bin/bash

ServerName=$1
CloudflareAPI=$2
CloudflareEmail=$3

Domain=$(echo $ServerName | cut -d "." -f2-)
DKIMSelector=$(echo $ServerName | awk -F[.:] '{print $1}')
ServerIP=$(wget -qO- http://ip-api.com/line\?fields=query)

echo "Configuando Servidor: $ServerName"

sleep 10


echo "==================================================================== Hostname && SSL ===================================================================="




# Função para verificar e instalar dependências
install_dependencies() {
    echo "Instalando pacotes via apt-get..."
    apt-get update || { echo "Erro ao atualizar repositórios"; exit 1; }

    sudo apt-get install -y wget unzip libidn2-0-dev || {
        echo "Erro ao instalar pacotes básicos via apt-get"; exit 1;
    }

# Baixar e instalar o Postfwd
cd /tmp
wget https://github.com/postfwd/postfwd/archive/master.zip -O postfwd.zip
unzip postfwd.zip
sudo mv postfwd-master /opt/postfwd

# Verificar e instalar módulos Perl necessários
check_and_install_perl_module() {
    local module_name=$1
    if perl -M"$module_name" -e '1' 2>/dev/null; then
        echo "Módulo Perl $module_name já está instalado. Pulando."
    else
        echo "Módulo Perl $module_name não encontrado. Instalando..."
        sudo cpan -i "$module_name" || { echo "Erro ao instalar $module_name."; exit 1; }
    fi
}

# Instalar módulos necessários
modules=("Net::Server::Daemonize" "Net::Server::Multiplex" "Net::Server::PreFork" "Net::DNS" "IO::Multiplex")
for module in "${modules[@]}"; do
    check_and_install_perl_module "$module"
done

# Criar arquivo de configuração do Postfwd
if [ ! -f "/opt/postfwd/etc/postfwd.cf" ]; then
    echo "Arquivo de configuração /opt/postfwd/etc/postfwd.cf não encontrado. Criando..."
    sudo bash -c "cat > /opt/postfwd/etc/postfwd.cf" <<EOF
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
pattern=recipient mx=.*telecom.com.ar
action=rate(global /200/3600) defer_if_permit "Limite de 200 e-mails por hora atingido para Telecom."

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
pattern=recipient mx=.*
action=permit
EOF
    echo "Arquivo de configuração criado com sucesso."
else
    echo "Arquivo de configuração /opt/postfwd/etc/postfwd.cf já existe. Nenhuma ação necessária."
fi

# Criar script de inicialização do Postfwd
sudo tee /opt/postfwd/bin/postfwd-script.sh > /dev/null <<'EOF'
#!/bin/sh
#
# Startscript for the postfwd daemon
#
# by JPK

PATH=/bin:/usr/bin:/usr/local/bin

# path to program
PFWCMD=/opt/postfwd/sbin/postfwd3
# rulesetconfig file
PFWCFG=/opt/postfwd/etc/postfwd.cf
# pidfile
PFWPID=/var/tmp/postfwd3-master.pid

# daemon settings
PFWUSER=postfix
PFWGROUP=postfix
PFWINET=127.0.0.1
PFWPORT=10045

# recommended extra arguments
PFWARG="--shortlog --summary=600 --cache=600 --cache-rbl-timeout=3600 --cleanup-requests=1200 --cleanup-rbls=1800 --cleanup-rates=1200"

## should be no need to change below

P1="`basename ${PFWCMD}`"
case "$1" in

 start*)  [ /var/tmp/postfwd3-master.pid ] && rm -Rf /var/tmp/postfwd3-master.pid;
          echo "Starting ${P1}...";
   ${PFWCMD} ${PFWARG} --daemon --file=${PFWCFG} --interface=${PFWINET} --port=${PFWPORT} --user=${PFWUSER} --group=${PFWGROUP} --pidfile=${PFWPID};
   ;;

 debug*)  echo "Starting ${P1} in debug mode...";
   ${PFWCMD} ${PFWARG} -vv --daemon --file=${PFWCFG} --interface=${PFWINET} --port=${PFWPORT} --user=${PFWUSER} --group=${PFWGROUP} --pidfile=${PFWPID};
   ;;

 stop*)  ${PFWCMD} --interface=${PFWINET} --port=${PFWPORT} --pidfile=${PFWPID} --kill;
   ;;

 reload*) ${PFWCMD} --interface=${PFWINET} --port=${PFWPORT} --pidfile=${PFWPID} -- reload;
   ;;

 restart*) $0 stop;
   sleep 4;
   $0 start;
   ;;

 *)  echo "Unknown argument \"$1\"" >&2;
   echo "Usage: `basename $0` {start|stop|debug|reload|restart}"
   exit 1;;
esac
exit $?
EOF

# Tornar o script executável
sudo chmod +x /opt/postfwd/bin/postfwd-script.sh

# Criar link simbólico para o script de inicialização
sudo ln -s /opt/postfwd/bin/postfwd-script.sh /etc/init.d/postfwd

# Reiniciar serviços
sudo /etc/init.d/postfwd start
sudo systemctl restart postfix

# Verificar o status do serviço
sudo systemctl status postfwd --no-pager || { echo "Verifique manualmente o status do serviço postfwd."; exit 1; }

echo "Configuração do Postfwd concluída com sucesso!"


echo "==================================================== POSTFIX ===================================================="

echo "======================================================= FIM =========================================================="

echo "================================================= Reiniciar servidor ================================================="
# Verificar se o reboot é necessário
if [ -f /var/run/reboot-required ]; then
  echo "Reiniciando o servidor em 5 segundos devido a atualizações críticas..."
  sleep 5
  sudo reboot
else
  echo "Reboot não necessário. Aguardando 5 segundos para leitura antes de finalizar o script..."
  sleep 5
fi

# Finaliza o script explicitamente
echo "Finalizando o script."
exit 0
