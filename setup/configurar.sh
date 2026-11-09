#!/usr/bin/env bash
# Configura o backend do app de prestação de contas num projeto Firebase já criado.
# Rode no Google Cloud Shell (shell.cloud.google.com), logado com a sua conta Google:
#   git clone https://github.com/ernandes-sobreira/presta-conta-fapemat && cd presta-conta-fapemat && bash setup/configurar.sh
# Pode rodar de novo quantas vezes quiser: cada passo verifica o que já existe.
set -euo pipefail
cd "$(dirname "$0")/.."

REGIAO="southamerica-east1"
DOMINIO="ernandes-sobreira.github.io"
ORIGEM="https://${DOMINIO}"
SEGREDO="anthropic-api-key"

ok(){ printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
passo(){ printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
falha(){ printf '\n\033[1;31m✘ %s\033[0m\n' "$*"; exit 1; }
json(){ python3 -c "import sys,json;d=json.load(sys.stdin);$1"; }

EMAIL="$(gcloud config get-value account 2>/dev/null || true)"
[ -n "$EMAIL" ] || falha "Nenhuma conta Google logada. Abra este script no Google Cloud Shell."
EMAIL_MIN="$(printf '%s' "$EMAIL" | tr '[:upper:]' '[:lower:]')"
echo "Conta Google: $EMAIL"
echo "Só esta conta poderá ler e gravar os dados e usar a IA."

P="${1:-}"
if [ -z "$P" ]; then read -rp "ID do projeto Firebase (aparece em Configurações do projeto, ex.: presta-conta-abc12): " P; fi
[ -n "$P" ] || falha "Informe o ID do projeto."
gcloud config set project "$P" >/dev/null 2>&1 || true

api(){ # api MÉTODO URL [JSON]  -> imprime a resposta; retorna erro se HTTP não for 2xx
  local saida codigo
  saida="$(mktemp)"
  if [ -n "${3:-}" ]; then
    codigo="$(curl -sS -o "$saida" -w '%{http_code}' -X "$1" "$2" -H "Authorization: Bearer $(gcloud auth print-access-token)" -H "X-Goog-User-Project: $P" -H "Content-Type: application/json" --data-binary "$3")"
  else
    codigo="$(curl -sS -o "$saida" -w '%{http_code}' -X "$1" "$2" -H "Authorization: Bearer $(gcloud auth print-access-token)" -H "X-Goog-User-Project: $P")"
  fi
  cat "$saida"; rm -f "$saida"
  [ "${codigo:0:1}" = "2" ]
}

passo "1/6 Ativando as APIs do Firebase"
gcloud services enable firebase.googleapis.com firestore.googleapis.com firebaserules.googleapis.com identitytoolkit.googleapis.com --project "$P"
api GET "https://firebase.googleapis.com/v1beta1/projects/$P" >/dev/null || falha "O projeto $P não é um projeto Firebase. Crie-o em console.firebase.google.com e rode de novo."
ok "Projeto Firebase $P"

passo "2/6 Login Google"
if ! api GET "https://identitytoolkit.googleapis.com/admin/v2/projects/$P/defaultSupportedIdpConfigs/google.com" 2>/dev/null | json 'sys.exit(0 if d.get("enabled") else 1)'; then
  echo "O login Google ainda não está ativo. Abra:"
  echo "  https://console.firebase.google.com/project/$P/authentication/providers"
  echo "Clique em Começar (se aparecer) → Google → Ativar → escolha seu e-mail de suporte → Salvar. Depois rode este script de novo."
  exit 1
fi
CFG="$(api GET "https://identitytoolkit.googleapis.com/admin/v2/projects/$P/config")" || falha "Não consegui ler a configuração de login."
DOMS="$(printf '%s' "$CFG" | json "a=d.get('authorizedDomains',[]); a=a+['$DOMINIO'] if '$DOMINIO' not in a else a; print(json.dumps(a))")"
api PATCH "https://identitytoolkit.googleapis.com/admin/v2/projects/$P/config?updateMask=authorizedDomains" "{\"authorizedDomains\":$DOMS}" >/dev/null || falha "Não consegui autorizar o domínio $DOMINIO."
ok "Login Google ativo e domínio $DOMINIO autorizado"

passo "3/6 Banco Firestore"
if gcloud firestore databases describe --database="(default)" --project "$P" >/dev/null 2>&1; then
  ok "Banco já existe"
else
  gcloud firestore databases create --database="(default)" --location="$REGIAO" --type=firestore-native --project "$P"
  ok "Banco criado em $REGIAO"
fi

passo "4/6 Regras de segurança"
REGRAS="$(sed "s/__DONO_EMAIL__/$EMAIL_MIN/" firestore.rules)"
CORPO="$(REGRAS="$REGRAS" python3 -c 'import os,json;print(json.dumps({"source":{"files":[{"name":"firestore.rules","content":os.environ["REGRAS"]}]}}))')"
RS="$(api POST "https://firebaserules.googleapis.com/v1/projects/$P/rulesets" "$CORPO" | json 'print(d["name"])')" || falha "As regras foram recusadas."
REL="projects/$P/releases/cloud.firestore"
if ! api PATCH "https://firebaserules.googleapis.com/v1/$REL" "{\"release\":{\"name\":\"$REL\",\"rulesetName\":\"$RS\"}}" >/dev/null 2>&1; then
  api POST "https://firebaserules.googleapis.com/v1/projects/$P/releases" "{\"name\":\"$REL\",\"rulesetName\":\"$RS\"}" >/dev/null || falha "Não consegui publicar as regras."
fi
ok "Regras publicadas: só $EMAIL_MIN lê e grava"

passo "5/6 App web"
APP="$(api GET "https://firebase.googleapis.com/v1beta1/projects/$P/webApps" | json 'a=d.get("apps",[]);print(a[0]["appId"] if a else "")')"
if [ -z "$APP" ]; then
  api POST "https://firebase.googleapis.com/v1beta1/projects/$P/webApps" '{"displayName":"presta-conta"}' >/dev/null || falha "Não consegui registrar o app web."
  for _ in $(seq 1 30); do
    sleep 3
    APP="$(api GET "https://firebase.googleapis.com/v1beta1/projects/$P/webApps" | json 'a=d.get("apps",[]);print(a[0]["appId"] if a else "")')"
    [ -n "$APP" ] && break
  done
fi
[ -n "$APP" ] || falha "O app web não apareceu. Rode de novo em um minuto."
WEBCFG="$(api GET "https://firebase.googleapis.com/v1beta1/projects/$P/webApps/$APP/config" | json 'print(json.dumps({k:d[k] for k in ["apiKey","authDomain","projectId","storageBucket","messagingSenderId","appId"] if k in d}))')"
ok "App web $APP"

passo "6/6 IA do Claude (opcional)"
echo "A IA lê fotos de notas e extratos e responde perguntas. Ela precisa de:"
echo "  - faturamento ativo neste projeto (plano Blaze; o uso normal fica no nível gratuito do Google);"
echo "  - uma chave da API da Anthropic (console.anthropic.com), que é paga por uso e separada da assinatura do Claude."
read -rp "Configurar a IA agora? (s/n) " RESP
IA_URL="null"
if [ "${RESP,,}" = "s" ]; then
  if [ "$(gcloud billing projects describe "$P" --format='value(billingEnabled)' 2>/dev/null)" != "True" ]; then
    CONTAS="$(gcloud billing accounts list --filter='open=true' --format='value(name)' 2>/dev/null || true)"
    if [ "$(printf '%s\n' "$CONTAS" | grep -c .)" = "1" ]; then
      gcloud billing projects link "$P" --billing-account="$CONTAS"
    else
      echo "Ative o faturamento (plano Blaze) em: https://console.firebase.google.com/project/$P/usage/details"
      falha "Faturamento não ativo. Depois de ativar, rode o script de novo."
    fi
  fi
  ok "Faturamento ativo"
  gcloud services enable run.googleapis.com cloudfunctions.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com --project "$P"
  if ! gcloud secrets describe "$SEGREDO" --project "$P" >/dev/null 2>&1; then
    gcloud secrets create "$SEGREDO" --replication-policy=automatic --project "$P"
  fi
  if [ -z "$(gcloud secrets versions list "$SEGREDO" --project "$P" --filter='state=enabled' --format='value(name)' 2>/dev/null)" ] || { read -rp "Já existe uma chave salva. Trocar? (s/n) " T; [ "${T,,}" = "s" ]; }; then
    read -rsp "Cole a chave da API da Anthropic (não aparece na tela) e tecle Enter: " CHAVE; echo
    [ -n "$CHAVE" ] || falha "Chave vazia."
    printf '%s' "$CHAVE" | gcloud secrets versions add "$SEGREDO" --data-file=- --project "$P" >/dev/null
    unset CHAVE
  fi
  ok "Chave guardada no Secret Manager"
  PN="$(gcloud projects describe "$P" --format='value(projectNumber)')"
  SA="${PN}-compute@developer.gserviceaccount.com"
  gcloud secrets add-iam-policy-binding "$SEGREDO" --member="serviceAccount:$SA" --role=roles/secretmanager.secretAccessor --project "$P" >/dev/null
  gcloud projects add-iam-policy-binding "$P" --member="serviceAccount:$SA" --role=roles/cloudbuild.builds.builder --condition=None >/dev/null
  echo "Publicando a função (leva de 2 a 5 minutos)…"
  gcloud functions deploy claude --gen2 --region="$REGIAO" --runtime=nodejs22 --source=functions --entry-point=claude \
    --trigger-http --allow-unauthenticated --memory=512Mi --timeout=300s --max-instances=3 \
    --set-env-vars="PROJETO=$P,DONO_EMAIL=$EMAIL_MIN,ORIGENS=$ORIGEM" \
    --set-secrets="ANTHROPIC_API_KEY=$SEGREDO:latest" --project "$P"
  IA_URL="\"$(gcloud functions describe claude --gen2 --region="$REGIAO" --project "$P" --format='value(serviceConfig.uri)')\""
  ok "Função de IA publicada: $IA_URL"
fi

SAIDA="$HOME/firebase-config.js"
cat > "$SAIDA" <<EOF
// Configuração pública do app web do Firebase (não é segredo: a proteção dos dados vem das regras do Firestore
// e da verificação de login na função de IA). Gerado por setup/configurar.sh.
window.FIREBASE_CONFIG = $WEBCFG;
// Endereço da função de IA (Cloud Functions). null = sem IA fora do Claude.
window.FIREBASE_IA_URL = $IA_URL;
EOF
printf '\n\033[1;32mPronto.\033[0m Copie o bloco abaixo e cole na conversa com o Claude (não é segredo):\n\n'
cat "$SAIDA"
