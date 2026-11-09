// Função HTTP (Cloud Functions 2ª geração) que repassa ao Claude os pedidos de leitura do app.
// Segurança:
// - exige o token de login do Firebase (Google) no cabeçalho Authorization;
// - aceita somente o e-mail definido em DONO_EMAIL, com e-mail verificado;
// - a chave da API da Anthropic fica no Secret Manager (variável ANTHROPIC_API_KEY), nunca no navegador;
// - responde CORS apenas para as origens em ORIGENS.
// A função não grava nada: só lê texto/imagem e devolve o texto do Claude.

const functions = require("@google-cloud/functions-framework");
const admin = require("firebase-admin");
const Anthropic = require("@anthropic-ai/sdk");

const PROJETO = process.env.PROJETO;
const DONO_EMAIL = (process.env.DONO_EMAIL || "").trim().toLowerCase();
const ORIGENS = (process.env.ORIGENS || "").split(",").map((s) => s.trim()).filter(Boolean);
const MODELO = "claude-opus-5-5";
const TIPOS_IMAGEM = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);
const MAX_IMAGENS = 4;
const MAX_TEXTO = 200000; // caracteres somados de todas as mensagens
const MAX_IMAGEM_B64 = 6 * 1024 * 1024;

admin.initializeApp({ projectId: PROJETO });
let cliente = null;
const claude = () => (cliente ||= new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY }));

function cors(req, res) {
  const origem = req.get("Origin");
  if (origem && ORIGENS.includes(origem)) {
    res.set("Access-Control-Allow-Origin", origem);
    res.set("Vary", "Origin");
    res.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Max-Age", "3600");
  }
}
const erro = (res, status, codigo, mensagem) => res.status(status).json({ erro: codigo, mensagem });

function validarCorpo(corpo) {
  if (!corpo || typeof corpo !== "object") return "corpo inválido";
  const { messages, images } = corpo;
  if (!Array.isArray(messages) || !messages.length || messages.length > 40) return "messages inválido";
  let total = 0;
  for (const m of messages) {
    if (!m || (m.role !== "user" && m.role !== "assistant") || typeof m.content !== "string" || !m.content.trim()) return "mensagem inválida";
    total += m.content.length;
  }
  if (total > MAX_TEXTO) return "texto grande demais";
  if (messages[0].role !== "user" || messages[messages.length - 1].role !== "user") return "a conversa deve começar e terminar com o usuário";
  if (images != null) {
    if (!Array.isArray(images) || images.length > MAX_IMAGENS) return "imagens inválidas";
    for (const i of images) {
      if (!i || !TIPOS_IMAGEM.has(i.mediaType) || typeof i.data !== "string" || !i.data || i.data.length > MAX_IMAGEM_B64) return "imagem inválida";
    }
  }
  return null;
}

// Junta mensagens consecutivas do mesmo papel (o app às vezes envia duas do usuário seguidas).
function normalizar(messages, images) {
  const out = [];
  for (const m of messages) {
    const ultimo = out[out.length - 1];
    if (ultimo && ultimo.role === m.role) ultimo.content += "\n\n" + m.content;
    else out.push({ role: m.role, content: m.content });
  }
  const fim = out[out.length - 1];
  const blocos = (images || []).map((i) => ({ type: "image", source: { type: "base64", media_type: i.mediaType, data: i.data } }));
  fim.content = [...blocos, { type: "text", text: fim.content }];
  return out;
}

functions.http("claude", async (req, res) => {
  cors(req, res);
  if (req.method === "OPTIONS") return res.status(204).send("");
  if (req.method !== "POST") return erro(res, 405, "metodo", "Use POST.");
  if (!PROJETO || !DONO_EMAIL || !process.env.ANTHROPIC_API_KEY) return erro(res, 500, "configuracao", "Função sem PROJETO, DONO_EMAIL ou ANTHROPIC_API_KEY.");

  const m = /^Bearer (.+)$/.exec(req.get("Authorization") || "");
  if (!m) return erro(res, 401, "nao_autenticado", "Faça login.");
  let token;
  try {
    token = await admin.auth().verifyIdToken(m[1]);
  } catch (e) {
    return erro(res, 401, "nao_autenticado", "Login expirado. Entre de novo.");
  }
  if (!token.email_verified || String(token.email || "").toLowerCase() !== DONO_EMAIL) {
    return erro(res, 403, "sem_permissao", "Esta conta não tem acesso.");
  }

  const problema = validarCorpo(req.body);
  if (problema) return erro(res, 400, "pedido_invalido", problema);

  try {
    const resposta = await claude().beta.messages.create({
      model: MODELO,
      max_tokens: 16000,
      output_config: { effort: "medium" },
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      messages: normalizar(req.body.messages, req.body.images),
    });
    if (resposta.stop_reason === "refusal") return erro(res, 422, "recusado", "O Claude recusou esta leitura.");
    const texto = resposta.content.filter((b) => b.type === "text").map((b) => b.text).join("");
    if (!texto.trim()) return erro(res, 502, "vazio", "O Claude não devolveu texto.");
    return res.json({ text: texto, truncated: resposta.stop_reason === "max_tokens" });
  } catch (e) {
    if (e instanceof Anthropic.RateLimitError) return erro(res, 429, "limite", "Limite de uso da API atingido. Tente mais tarde.");
    if (e instanceof Anthropic.AuthenticationError) return erro(res, 500, "chave_invalida", "A chave da API da Anthropic é inválida.");
    if (e instanceof Anthropic.PermissionDeniedError) return erro(res, 500, "chave_sem_permissao", "A chave da API não tem permissão ou crédito.");
    if (e instanceof Anthropic.BadRequestError) return erro(res, 400, "pedido_recusado_api", e.message);
    if (e instanceof Anthropic.APIError) return erro(res, 502, "api", `Erro da API (${e.status}).`);
    console.error(e);
    return erro(res, 502, "falha", "Falha ao falar com o Claude.");
  }
});
