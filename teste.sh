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
echo "Continuando a execução do script..."

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
