# presta-conta-fapemat

App web de prestação de contas para projetos financiados pela FAPEMAT (RN 008/2021).

O código não contém dados de projeto. Orçamento, equipe, prazos e despesas ficam no banco de cada usuário:

- **No GitHub Pages:** Firebase (login Google + Firestore). Cada conta só acessa `users/{uid}/…`, conforme `firestore.rules`.
- **Dentro do Claude (artifact):** banco do próprio artifact, com leitura de texto e foto pela IA.
- **Sem nenhum dos dois:** navegador (localStorage), com aviso na tela.

No primeiro acesso, o app pede o arquivo `plano-de-trabalho.json` (formato `plano-fapemat-v1`), que não fica neste repositório.

## Configurar o Firebase
1. Crie um projeto em console.firebase.google.com.
2. Authentication → Sign-in method → ative **Google**. Em Settings → Authorized domains, adicione o domínio do GitHub Pages.
3. Firestore Database → criar banco em modo de produção.
4. Firestore → Rules → cole o conteúdo de `firestore.rules` → Publicar.
5. Configurações do projeto → Seus apps → Web → copie o `firebaseConfig` para `firebase-config.js`.

## Validações
Feitas em código, nunca pela IA: vigência, item 3.8, saldo por item, capital × custeio, equipe e parentesco, diárias, vedações do item 3.13 e item 3.4.1.
