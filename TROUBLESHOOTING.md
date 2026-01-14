# Solução de Problemas de Conexão

Se o Safari diz "não foi possível conectar ao servidor", geralmente é uma dessas 3 coisas:

## 1. Firewall do Mac (O mais comum)
O Mac bloqueia conexões vindas de fora por segurança.
1.  Vá em **Ajustes do Sistema** -> **Rede** -> **Firewall**.
2.  Se estiver **Ativado**, clique em "Opções".
3.  Desative temporariamente ou adicione o "python3" na lista de permitidos (Allow incoming connections).

## 2. Redes Diferentes
O iPhone e o Mac **precisam** estar no mesmo Wi-Fi.
*   Se o Mac estiver no cabo e o iPhone no Wi-Fi, às vezes eles não se "enxergam" dependendo do roteador.
*   Se o iPhone estiver no 4G/5G, **não vai funcionar**.

## 3. Endereço IP Errado
O script tenta adivinhar o IP, mas às vezes ele pega o IP errado.
Tente os outros IPs listados no terminal quando você roda o script.

---

## Solução Definitiva (Se nada funcionar) -> Ngrok
Se a rede local estiver impossível, podemos usar o Ngrok para criar um link de internet (que funciona até no 4G).

1.  Instale o Ngrok no terminal: `brew install ngrok/ngrok/ngrok` (ou baixe no site).
2.  Rode o servidor normal (`./run_studio.sh`).
3.  Abra **outra aba** do terminal e digite:
    ```bash
    ngrok http 8502
    ```
4.  Use o link `https://....ngrok-free.app` que aparecer no iPhone.
