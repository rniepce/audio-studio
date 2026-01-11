#!/bin/bash

echo "🎵 Configurando o Audio Mastering App..."

# Verifica se o python3 está instalado
if ! command -v python3 &> /dev/null; then
    echo "❌ Python3 não encontrado. Por favor, instale o Python antes de continuar."
    exit 1
fi

# Cria um ambiente virtual (opcional, mas recomendado)
if [ ! -d "venv" ]; then
    echo "📦 Criando ambiente virtual..."
    python3 -m venv venv
fi

# Ativa o ambiente virtual
source venv/bin/activate

# Instala dependências
echo "⬇️ Instalando dependências..."
pip install -r requirements.txt

# Executa o aplicativo
echo "🚀 Iniciando o aplicativo..."
streamlit run app.py
