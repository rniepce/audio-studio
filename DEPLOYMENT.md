# Guia de Instalação Online (Deployment)

Você tem duas ótimas opções para acessar seu aplicativo de qualquer lugar. Como você tem um **MacBook M3 Pro**, a **Opção 2** é a mais recomendada para performance (o M3 voa no processamento de áudio via IA), mas a **Opção 1** é mais fácil de compartilhar.

---

## Opção 1: Streamlit Cloud (Grátis & Fácil)
Hospeda o site nos servidores do Streamlit. Ideal para acesso rápido, mas pode ser lento na separação de faixas (Demucs) devido aos limites de processamento da conta grátis.

**Passos:**

1.  **Crie um repositório no GitHub:**
    *   Acesse [github.com/new](https://github.com/new).
    *   Crie um repositório chamado `audio-studio`.
    *   Não marque "Initialize with README" (você já tem os arquivos).

2.  **Envie os arquivos para o GitHub:**
    Abra o terminal na pasta do projeto (`/Users/rafaelpimentel/Downloads/master audio`) e rode:
    ```bash
    git init
    git add .
    git commit -m "Primeira versão do Audio Studio"
    git branch -M main
    git remote add origin https://github.com/SEU_USUARIO/audio-studio.git
    git push -u origin main
    ```
    *(Troque `SEU_USUARIO` pelo seu username do GitHub)*.

3.  **Conecte ao Streamlit Cloud:**
    *   Acesse [share.streamlit.io](https://share.streamlit.io/).
    *   Faça login com seu GitHub.
    *   Clique em **"New app"**.
    *   Selecione o repositório `audio-studio`.
    *   Branch: `main`.
    *   Main file path: `app.py`.
    *   Clique em **Deploy!**.

O Streamlit vai instalar tudo automaticamente (graças ao arquivo `packages.txt` e `requirements.txt` que criei) e te dar um link público (ex: `https://audio-studio.streamlit.app`).

---

## Opção 2: Servidor Caseiro no MacBook M3 Pro (Alta Performance)
Você roda o aplicativo no super processador do M3 Pro e acessa do outro computador via internet. Isso usa o poder do seu Mac.

**Passos:**

1.  **No MacBook M3 Pro:**
    *   Baixe os arquivos deste projeto.
    *   Instale e rode o app normalmente (`./run_app.sh`).

2.  **Expondo para a Internet (Ngrok):**
    Para acessar de fora da sua rede Wi-Fi, usaremos o **Ngrok** (ferramenta segura de túnel).
    
    *   Instale o Ngrok (se não tiver): `brew install ngrok/ngrok/ngrok` ou baixe no site.
    *   Crie uma conta grátis em [ngrok.com](https://ngrok.com) para pegar seu `Authtoken`.
    *   Autentique: `ngrok config add-authtoken SEU_TOKEN_AQUI`
    *   Com o app rodando (ele usa a porta 8501), abra **outro terminal** e rode:
        ```bash
        ngrok http 8501
        ```

3.  **Acessando:**
    O Ngrok vai te dar um link (algo como `https://a1b2-c3d4.ngrok-free.app`). 
    *   Envie esse link para você mesmo.
    *   Abra no seu computador sem GPU.
    *   Pronto! Você está usando a interface no PC fraco, mas todo o processamento pesado está sendo feito no M3 Pro da sua esposa.

---

### Resumo
*   **Quer facilidade e não se importa se demorar um pouco para separar as faixas?** -> Vá de **Streamlit Cloud**.
*   **Quer velocidade máxima usando o poder do M3?** -> Vá de **Opção 2 (Ngrok)**.
