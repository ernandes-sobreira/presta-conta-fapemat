// Configuração pública do app web do Firebase (não é segredo: a proteção dos dados vem das regras do Firestore
// e da verificação de login na função de IA). O script setup/configurar.sh gera este conteúdo.
window.FIREBASE_CONFIG = null;
// Endereço da função de IA (Cloud Functions). null = sem IA fora do Claude.
window.FIREBASE_IA_URL = null;
