# 📱 Como Usar no iPhone (Web App)

Como migramos para uma interface web moderna, você não precisa mais do Xcode ou de cabos. Basta usar o **Safari** e adicionar à tela de início.

## 1. Descubra o IP do Mac e Inicie o App
1.  No Mac, abra o terminal e rode:
    ```bash
    ./run_studio.sh
    ```
2.  O terminal vai mostrar algo como:
    ```
    LINK DO IPHONE (Tente estes IPs):
    http://192.168.1.15:8502
    ```
3.  Anote esse endereço (`http://...:8502`).

## 2. Abra no iPhone
1.  Verifique se o seu iPhone está conectado no **MESMO WI-FI** que o Mac.
2.  Abra o **Safari**.
3.  Digite o endereço que apareceu no terminal (ex: `192.168.1.15:8502`).
4.  O App deve carregar! 🎉

## 3. Instale como "Aplicativo"
Para tirar a barra de endereços e parecer um app nativo:
1.  No Safari, toque no botão **Compartilhar** (quadrado com seta para cima).
2.  Role para baixo e toque em **"Adicionar à Tela de Início"** (Add to Home Screen).
3.  Dê o nome de "Song Manager".
4.  Pronto! Agora você tem um ícone no seu celular que abre o app direto em tela cheia.

---

## ⚠️ Solução de Problemas

**"Não carrega / Site não encontrado"**
*   **Firewall**: O Firewall do Mac pode estar bloqueando.
    *   Vá em `Ajustes do Sistema` -> `Rede` -> `Firewall` e desative temporariamente para testar.
*   **Wi-Fi**: Confirme que Mac e iPhone estão na mesma rede (às vezes um está no 5G e outro no 2.4G, mas geralmente funciona se for o mesmo roteador).
*   **IP Mudou**: Se você reiniciou o roteador, o IP do Mac pode ter mudado. Rode `./run_studio.sh` de novo para ver o novo IP.
