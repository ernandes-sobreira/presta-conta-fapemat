# presta-conta-fapemat

App de prestação de contas do projeto **Transforma-ações: Integrando Saberes para ações sustentáveis**
(processo FAPEMAT-PRO.0002209/2025, RN FAPEMAT 008/2021). Uso pessoal do coordenador.

## O que faz
- Registro de gastos por texto livre ou foto (nota, recibo, bilhete, extrato), com cartão de confirmação: nada é gravado sem confirmar.
- Validações da norma feitas em código (vigência, item 3.8, saldo por item, capital × custeio, equipe e parentesco, diárias, vedações do item 3.13, item 3.4.1).
- Estados: pendente, comprovada, irregular, a confirmar com a FAPEMAT.
- Painel de saldos por rubrica, orçamento item a item, prazos, assistente e exportação CSV/JSON.

## Onde roda
O arquivo `index.html` foi feito para rodar como **artifact do Claude** (claude.ai), que fornece:
- `db`: armazenamento persistente;
- `sample`: leitura de texto e imagem pela IA, sem chave de API;
- `downloads`: salvar CSV e JSON.

Aberto fora do Claude (arquivo local ou GitHub Pages), o app funciona em modo reduzido:
sem IA, com os dados guardados só no `localStorage` do navegador, e avisa isso na tela.
Nesse modo, faça backup JSON com frequência.

## Limitações conhecidas
- Imagens são reduzidas pela plataforma a ~1,2 megapixel; fotografe extratos longos em partes. PDF não é aceito.
- Vedações por palavra-chave podem gerar falso positivo; o app permite dispensar esses alertas com justificativa registrada.
- O CSV não é o formulário oficial da FAPEMAT; confira as colunas com o modelo vigente.
