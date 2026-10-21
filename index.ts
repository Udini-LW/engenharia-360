// Engenharia 360 · função de servidor "admin-usuarios"
// Faz o que exige a chave de serviço (que nunca sai do Supabase):
// cadastrar usuário com senha inicial, redefinir senha e excluir usuário.
// Só atende quem estiver logado e tiver a permissão usuarios.gerenciar.
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const resp = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

function senhaFraca(s: unknown): string | null {
  const v = String(s ?? "");
  if (v.length < 8) return "A senha precisa ter pelo menos 8 caracteres.";
  if (v.length > 72) return "Senha longa demais (máximo 72 caracteres).";
  if (!/[A-Za-z]/.test(v) || !/\d/.test(v)) return "Use letras e números na senha.";
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return resp(405, { erro: "Método não permitido." });
  try {
    const adm = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: quem } = await adm.auth.getUser(token);
    if (!quem?.user) return resp(401, { erro: "Sessão expirada. Entre de novo." });
    const autor = quem.user.id;

    const { data: pode, error: ePode } = await adm.rpc("svc_pode", { p_uid: autor, p_perm: "usuarios.gerenciar" });
    if (ePode) throw ePode;
    if (!pode) return resp(403, { erro: "Só o Admin altera usuários." });

    const b = await req.json();

    if (b.acao === "criar") {
      const { data: v, error: eVal } = await adm.rpc("svc_validar", { b });
      if (eVal) return resp(400, { erro: eVal.message });
      const f = senhaFraca(b.senha);
      if (f) return resp(400, { erro: f });
      const { data: novo, error: eNovo } = await adm.auth.admin.createUser({
        email: v.email, password: String(b.senha), email_confirm: true,
      });
      if (eNovo || !novo?.user) return resp(400, { erro: "Não foi possível criar o acesso: " + (eNovo?.message ?? "erro desconhecido") });
      const { error: ePerf } = await adm.rpc("svc_criar_perfil", { p_autor: autor, p_id: novo.user.id, b });
      if (ePerf) {
        await adm.auth.admin.deleteUser(novo.user.id);
        return resp(400, { erro: ePerf.message });
      }
      return resp(200, { ok: true, id: novo.user.id });
    }

    if (b.acao === "senha") {
      if (!b.id) return resp(400, { erro: "Usuário não informado." });
      if (b.id === autor) return resp(400, { erro: "Para a sua senha, use “Trocar senha”." });
      const f = senhaFraca(b.senha);
      if (f) return resp(400, { erro: f });
      const { error } = await adm.auth.admin.updateUserById(b.id, { password: String(b.senha) });
      if (error) return resp(400, { erro: "Não foi possível redefinir: " + error.message });
      const { error: eReg } = await adm.rpc("svc_senha_redefinida", { p_autor: autor, p_id: b.id });
      if (eReg) return resp(400, { erro: eReg.message });
      return resp(200, { ok: true });
    }

    if (b.acao === "excluir") {
      if (!b.id) return resp(400, { erro: "Usuário não informado." });
      const { error: eAntes } = await adm.rpc("svc_antes_de_excluir", { p_autor: autor, p_id: b.id });
      if (eAntes) return resp(400, { erro: eAntes.message });
      const { error } = await adm.auth.admin.deleteUser(b.id);
      if (error) return resp(400, { erro: "Não foi possível excluir: " + error.message });
      return resp(200, { ok: true });
    }

    return resp(400, { erro: "Ação desconhecida." });
  } catch (e) {
    console.error(e);
    return resp(400, { erro: "Pedido inválido." });
  }
});
