# presta-conta-fapemat

App web de prestação de contas para projetos financiados pela FAPEMAT (RN 008/2021).

O código não contém dados de projeto. Orçamento, equipe, prazos e despesas ficam no banco do usuário:

- **No GitHub Pages:** Firebase. Login Google; Firestore com regras que só deixam a conta do dono (e-mail verificado) ler e gravar a própria pasta `users/{uid}/…`.
- **IA fora do Claude (opcional):** função em `functions/` (Cloud Functions 2ª geração) que confere o login, aceita só o e-mail do dono e chama o Claude com a chave guardada no Secret Manager.
- **Dentro do Claude (artifact):** banco do próprio artifact e IA do Claude, sem chave.
- **Sem nada disso:** navegador (localStorage), com aviso na tela.

No primeiro acesso, o app pede o arquivo `plano-de-trabalho.json` (formato `plano-fapemat-v1`), que não fica neste repositório.

## Configurar o backend
1. Em console.firebase.google.com, crie um projeto.
2. No projeto: Authentication → Começar → Google → Ativar → Salvar.
3. Abra o Google Cloud Shell (shell.cloud.google.com), logado com a mesma conta, e rode:
   ```
   git clone https://github.com/ernandes-sobreira/presta-conta-fapemat && cd presta-conta-fapemat && bash setup/configurar.sh
   ```
   O script cria o banco, publica as regras com o seu e-mail, autoriza o domínio do GitHub Pages, registra o app web e, se você quiser, publica a função de IA (pede faturamento ativo e a chave da API da Anthropic, digitada só no Cloud Shell).
4. O script imprime o conteúdo de `firebase-config.js`. Ele não é segredo; substitua o arquivo do repositório por ele.

## Validações
Feitas em código, nunca pela IA: vigência, item 3.8, saldo por item, capital × custeio, equipe e parentesco, diárias, vedações do item 3.13 e item 3.4.1.
