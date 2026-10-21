-- =====================================================================
-- Engenharia 360 · estrutura do banco (Supabase)
-- Cole tudo no SQL Editor do Supabase e clique em Run. Pode rodar de novo
-- sem perder dados (cria só o que falta e atualiza as funções).
--
-- Segurança: as tabelas ficam FECHADAS (RLS ligado e nenhuma política).
-- Todo acesso passa pelas funções abaixo, que conferem perfil, permissão
-- e alcance de quem chamou. A tela só esconde; quem protege é o banco.
-- =====================================================================

-- ---------- tabelas ----------
create table if not exists public.org (
  k text primary key, nome text not null, deps text[] not null default '{}', ordem int not null default 0
);
insert into public.org (k, nome, deps, ordem) values
  ('DIR','Diretoria de Engenharia','{}',1),
  ('CAP','Capacita','{Experts,Academy,Comunidades}',2),
  ('PDSC','P&D e Soluções Construtivas','{Projetos,Orçamentos,"Customer Success","Suporte Técnico","P&D Sistema Construtivo"}',3),
  ('PDPS','P&D Produto e Sustentabilidade','{Produto,Sustentabilidade}',4),
  ('TRV','Transversal','{"Processos e Resultados","LightHub e IA aplicada"}',5)
on conflict (k) do nothing;

create table if not exists public.usuarios (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  email text not null unique,
  perfil text not null check (perfil in ('Admin','Diretor','Gestor','Analista','Consulta')),
  area text not null default '',
  depto text not null default '',
  status text not null default 'Ativo' check (status in ('Ativo','Inativo')),
  mods text[] not null default '{gpd.ver,wbr.ver}',
  areas_vis text[] not null default '{}',
  senha_provisoria boolean not null default true,
  ultimo_acesso timestamptz,
  criado_em timestamptz not null default now(),
  criado_por uuid,
  atualizado_em timestamptz,
  atualizado_por uuid
);

create table if not exists public.matriz (
  perfil text not null, permissao text not null, primary key (perfil, permissao)
);

create table if not exists public.acoes (
  id text primary key default gen_random_uuid()::text,
  titulo text not null,
  tipo text not null default 'Tarefa',
  origem text not null default '',
  area text not null default '',
  prioridade text not null default '',
  responsavel text not null default '',
  prazo date,
  status text not null default 'Aberta',
  meta text not null default '',
  obs text not null default '',
  links jsonb not null default '[]',
  criado_em timestamptz not null default now(),
  criado_por uuid,
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid
);

create table if not exists public.pauta (
  usuario uuid primary key references public.usuarios(id) on delete cascade,
  itens text[] not null default '{}',
  atualizado_em timestamptz not null default now()
);

create table if not exists public.historico (
  id bigserial primary key,
  quando timestamptz not null default now(),
  quem uuid, quem_nome text, quem_email text, perfil text,
  acao text not null, modulo text not null, registro text, area text,
  mudancas jsonb not null default '[]'
);

create table if not exists public.app_codigo (
  id int primary key default 1 check (id = 1),
  js text not null,
  versao text not null default '',
  atualizado_em timestamptz not null default now()
);

create table if not exists public.painel_dados (
  id int primary key default 1 check (id = 1),
  dados jsonb not null,
  atualizado_em timestamptz not null default now()
);

-- tabelas fechadas: só as funções abaixo acessam
alter table public.org enable row level security;
alter table public.usuarios enable row level security;
alter table public.matriz enable row level security;
alter table public.acoes enable row level security;
alter table public.pauta enable row level security;
alter table public.historico enable row level security;
alter table public.painel_dados enable row level security;
alter table public.app_codigo enable row level security;
revoke all on public.org, public.usuarios, public.matriz, public.acoes, public.pauta, public.historico, public.painel_dados, public.app_codigo from anon, authenticated;

-- matriz padrão (só na primeira vez)
insert into public.matriz (perfil, permissao)
select p, x from (values
  ('Diretor', array['gpd.ver','wbr.ver','ocupacao.ver','ocupacao.pessoas','custos.ver','acoes.ver','acoes.criar','acoes.editar','acoes.gerenciar','pauta.marcar','usuarios.ver','historico.baixar']),
  ('Gestor',  array['gpd.ver','wbr.ver','ocupacao.ver','ocupacao.pessoas','acoes.ver','acoes.criar','acoes.editar','acoes.gerenciar','pauta.marcar','usuarios.ver','historico.baixar']),
  ('Analista',array['gpd.ver','wbr.ver','ocupacao.ver','acoes.ver','acoes.criar','acoes.editar','pauta.marcar']),
  ('Consulta',array['gpd.ver','wbr.ver','ocupacao.ver','acoes.ver','custos.ver'])
) v(p, arr), unnest(arr) x
where not exists (select 1 from public.matriz);

-- ---------- funções de apoio (internas) ----------
create or replace function public._todas() returns text[] language sql immutable as $$
  select array['gpd.ver','wbr.ver','ocupacao.ver','ocupacao.pessoas','custos.ver','acoes.ver','acoes.criar','acoes.editar','acoes.gerenciar','pauta.marcar','usuarios.ver','historico.baixar','usuarios.gerenciar','permissoes.editar'] $$;
create or replace function public._so_admin() returns text[] language sql immutable as $$ select array['usuarios.gerenciar','permissoes.editar'] $$;
create or replace function public._consulta_max() returns text[] language sql immutable as $$ select array['gpd.ver','wbr.ver','ocupacao.ver','acoes.ver','custos.ver'] $$;
create or replace function public._escopo(p text) returns text language sql immutable as $$
  select case p when 'Admin' then 'eng' when 'Diretor' then 'eng' when 'Gestor' then 'area' when 'Analista' then 'proprio' else 'marcado' end $$;

create or replace function public._norm(s text) returns text language sql immutable as $$
  select btrim(regexp_replace(translate(lower(coalesce(s,'')), 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'), '\s+', ' ', 'g')) $$;

create or replace function public._mesmo_nome(resp text, nome text) returns boolean language sql immutable as $$
  select case when public._norm(nome) = '' then false else exists (
    select 1 from regexp_split_to_table(public._norm(resp), '\s*(/|,|;|\me\M)\s*') p
    where length(p) >= 3 and (p = public._norm(nome) or position(public._norm(nome) in p) > 0 or public._norm(nome) like p || ' %')
  ) end $$;

create or replace function public._area_of(label text) returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select k from public.org where k = label or nome = label or label = any(deps) limit 1),
    case label when 'Engenharia' then 'DIR' when 'Diretoria' then 'DIR' when 'Gestão e Performance' then 'DIR'
      when 'Pós-Venda' then 'PDSC' when 'Pós-venda / CS' then 'PDSC' when 'Sistemas Construtivos' then 'PDSC'
      when 'P&D Produto' then 'PDPS' when 'P&D Sustentabilidade' then 'PDPS' when 'Outra' then 'DIR' end) $$;

create or replace function public._area_nome(k text) returns text language sql stable security definer set search_path = public as $$
  select coalesce((select nome from public.org where org.k = _area_nome.k), coalesce(k,'')) $$;

create or replace function public._perms(u public.usuarios) returns text[] language plpgsql stable security definer set search_path = public as $$
declare p text[];
begin
  if u.id is null or u.status <> 'Ativo' then return '{}'; end if;
  if u.perfil = 'Admin' then return public._todas(); end if;
  select coalesce(array_agg(permissao), '{}') into p from public.matriz
   where perfil = u.perfil and permissao = any(public._todas()) and not (permissao = any(public._so_admin()));
  if u.perfil = 'Consulta' then
    select coalesce(array_agg(x), '{}') into p from unnest(p) x where x = any(public._consulta_max()) and x = any(u.mods);
  end if;
  return p;
end $$;

-- usuário ativo que está chamando (ou erro)
create or replace function public._eu() returns public.usuarios language plpgsql stable security definer set search_path = public as $$
declare u public.usuarios;
begin
  select * into u from public.usuarios where id = auth.uid();
  if u.id is null then raise exception 'Seu usuário não está cadastrado no Engenharia 360. Fale com um Admin.' using errcode = '28000'; end if;
  if u.status <> 'Ativo' then raise exception 'Seu acesso está inativo. Fale com um Admin do Engenharia 360.' using errcode = '28000'; end if;
  return u;
end $$;

create or replace function public._exige(u public.usuarios, perm text, msg text) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not (perm = any(public._perms(u))) then raise exception '%', msg using errcode = '42501'; end if;
end $$;

create or replace function public._fmt(v jsonb) returns text language sql immutable as $$
  select case
    when v is null or v = 'null'::jsonb then ''
    when jsonb_typeof(v) = 'array' then coalesce((select string_agg(
        case when jsonb_typeof(e) = 'object' then (case when coalesce(e->>'rotulo','') <> '' then (e->>'rotulo') || ': ' else '' end) || coalesce(e->>'url','')
             else e #>> '{}' end, case when jsonb_typeof(v->0) = 'object' then ' | ' else ', ' end)
        from jsonb_array_elements(v) e), '')
    else v #>> '{}' end $$;

create or replace function public._diff(a jsonb, b jsonb, campos text[]) returns jsonb language sql immutable as $$
  select coalesce(jsonb_agg(jsonb_build_object('campo', c, 'anterior', public._fmt(a->c), 'novo', public._fmt(b->c))), '[]'::jsonb)
  from unnest(campos) c where public._fmt(a->c) is distinct from public._fmt(b->c) $$;

create or replace function public._reg(u public.usuarios, acao text, modulo text, registro text, area text, mudancas jsonb) returns void
language sql security definer set search_path = public as $$
  insert into public.historico (quem, quem_nome, quem_email, perfil, acao, modulo, registro, area, mudancas)
  values (u.id, u.nome, u.email, u.perfil, acao, modulo, left(coalesce(registro,''), 200), area, coalesce(mudancas, '[]'::jsonb)) $$;

create or replace function public._eh_proprio(x public.acoes, u public.usuarios) returns boolean language sql stable as $$
  select (x.criado_por is not null and x.criado_por = u.id) or public._mesmo_nome(x.responsavel, u.nome) $$;

create or replace function public._no_escopo(x public.acoes, u public.usuarios, tipo text) returns boolean language sql stable security definer set search_path = public as $$
  select case public._escopo(u.perfil)
    when 'eng' then true
    when 'area' then case when tipo = 'editar'
        then (u.area <> '' and public._area_of(x.area) = u.area) or public._eh_proprio(x, u)
        else (u.area <> '' and public._area_of(x.area) = u.area) end
    when 'proprio' then public._eh_proprio(x, u)
    else false end $$;

create or replace function public._area_permitida(label text, u public.usuarios) returns boolean language sql stable security definer set search_path = public as $$
  select public._escopo(u.perfil) = 'eng' or (u.area <> '' and public._area_of(label) = u.area) $$;

create or replace function public._publico(u public.usuarios) returns jsonb language sql stable as $$
  select jsonb_build_object('id', u.id, 'nome', u.nome, 'email', u.email, 'perfil', u.perfil, 'area', u.area, 'depto', u.depto,
    'status', u.status, 'mods', case when u.perfil = 'Consulta' then to_jsonb(u.mods) else '[]'::jsonb end,
    'areasVis', case when u.perfil = 'Consulta' then to_jsonb(u.areas_vis) else '[]'::jsonb end,
    'senhaProvisoria', u.senha_provisoria, 'ultimoAcesso', u.ultimo_acesso, 'criadoEm', u.criado_em) $$;

create or replace function public._legivel(u jsonb) returns jsonb language sql stable security definer set search_path = public as $$
  select case when u is null then null else u || jsonb_build_object(
    'area', public._area_nome(u->>'area'),
    'mods', coalesce((select string_agg(x, ', ') from jsonb_array_elements_text(coalesce(u->'mods','[]')) x), ''),
    'areasVis', coalesce((select string_agg(public._area_nome(x), ', ') from jsonb_array_elements_text(coalesce(u->'areasVis','[]')) x), '')) end $$;

create or replace function public._admins_ativos(exceto uuid) returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from public.usuarios where perfil = 'Admin' and status = 'Ativo' and id is distinct from exceto $$;

create or replace function public._encerrar_sessoes(uid uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  begin delete from auth.sessions where user_id = uid; exception when others then null; end;
end $$;

-- validação de cadastro: devolve o cadastro limpo ou dá erro com mensagem legível
create or replace function public._validar_cadastro(b jsonb, existente uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_nome text := left(btrim(coalesce(b->>'nome','')), 120);
        v_email text := lower(left(btrim(coalesce(b->>'email','')), 160));
        v_perfil text := b->>'perfil';
        v_status text := coalesce(nullif(b->>'status',''), 'Ativo');
        v_area text := coalesce(b->>'area','');
        v_depto text := coalesce(b->>'depto','');
        v_deps text[]; v_mods text[]; v_av text[];
begin
  if v_nome = '' then raise exception 'Informe o nome.'; end if;
  if v_email !~ '^[^\s@]+@lightwallbrasil\.com$' then raise exception 'Use um e-mail válido do domínio lightwallbrasil.com.'; end if;
  if v_perfil is null or v_perfil not in ('Admin','Diretor','Gestor','Analista','Consulta') then raise exception 'Escolha o perfil.'; end if;
  if v_status not in ('Ativo','Inativo') then v_status := 'Ativo'; end if;
  select o.deps into v_deps from public.org o where o.k = v_area;
  if v_deps is null then v_area := ''; v_depto := ''; elsif not (v_depto = any(v_deps)) then v_depto := ''; end if;
  if v_area = '' and v_perfil not in ('Admin','Diretor') then raise exception 'Escolha a área: ela define o alcance deste perfil.'; end if;
  if exists (select 1 from public.usuarios x where x.email = v_email and x.id is distinct from existente) then
    raise exception 'Já existe um usuário com este e-mail.'; end if;
  select coalesce(array_agg(x), '{}') into v_mods from jsonb_array_elements_text(coalesce(b->'mods', '["gpd.ver","wbr.ver"]')) x where x = any(public._consulta_max());
  select coalesce(array_agg(x), '{}') into v_av from jsonb_array_elements_text(coalesce(b->'areasVis', '[]')) x where exists (select 1 from public.org o where o.k = x);
  if v_perfil <> 'Consulta' then v_mods := '{}'; v_av := '{}'; end if;
  return jsonb_build_object('nome', v_nome, 'email', v_email, 'perfil', v_perfil, 'status', v_status, 'area', v_area, 'depto', v_depto,
    'mods', to_jsonb(v_mods), 'areasVis', to_jsonb(v_av));
end $$;

-- ---------- funções chamadas pela tela ----------

-- quem sou eu + permissões (também registra o último acesso)
create or replace function public.eu() returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.usuarios := public._eu();
begin
  update public.usuarios set ultimo_acesso = now() where id = u.id;
  return jsonb_build_object('me', public._publico(u), 'perms', to_jsonb(public._perms(u)), 'escopo', public._escopo(u.perfil));
end $$;

-- números do painel, já cortados conforme a permissão
create or replace function public.painel() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare u public.usuarios := public._eu(); p text[] := public._perms(u); d jsonb; ver_pessoas boolean; i int := 0; e jsonb; arr jsonb := '[]';
begin
  select dados into d from public.painel_dados where id = 1;
  if d is null then raise exception 'Os dados do painel ainda não foram carregados. Fale com um Admin.'; end if;
  if not ('custos.ver' = any(p)) then
    d := jsonb_set(d, '{sap}', coalesce((select jsonb_object_agg(k, (select jsonb_agg(null::jsonb) from jsonb_array_elements(v))) from jsonb_each(d->'sap') s(k, v)), '{}'));
    d := jsonb_set(d, '{expertCusto}', coalesce((select jsonb_agg(null::jsonb) from jsonb_array_elements(d->'expertCusto')), '[]'));
    d := d || '{"custosOcultos": true}';
  end if;
  ver_pessoas := 'ocupacao.pessoas' = any(p) and (public._escopo(u.perfil) = 'eng' or u.area = 'PDSC');
  if not ver_pessoas and jsonb_typeof(d #> '{proj,porProjetista}') = 'array' then
    for e in select * from jsonb_array_elements(d #> '{proj,porProjetista}') loop
      if public._mesmo_nome(e->>0, u.nome) then arr := arr || jsonb_build_array(e);
      else i := i + 1; arr := arr || jsonb_build_array(jsonb_set(e, '{0}', to_jsonb('Projetista ' || i))); end if;
    end loop;
    d := jsonb_set(d, '{proj,porProjetista}', arr);
  end if;
  if not ('acoes.ver' = any(p)) then d := jsonb_set(d, '{acoes}', '[]'); end if;
  return d;
end $$;

-- código das telas (só para quem está logado e ativo; nada disso fica público no GitHub)
create or replace function public.app() returns text language plpgsql stable security definer set search_path = public as $$
declare u public.usuarios := public._eu(); c text;
begin
  select js into c from public.app_codigo where id = 1;
  if c is null then raise exception 'O código do painel ainda não foi carregado. Fale com um Admin.'; end if;
  return c;
end $$;

-- plano de ação
create or replace function public.acoes_listar() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare u public.usuarios := public._eu();
begin
  perform public._exige(u, 'acoes.ver', 'Sem permissão para ver o plano de ação.');
  return jsonb_build_object(
    'itens', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'titulo', a.titulo, 'tipo', a.tipo, 'origem', a.origem, 'area', a.area,
        'prioridade', a.prioridade, 'responsavel', a.responsavel, 'prazo', coalesce(to_char(a.prazo, 'YYYY-MM-DD'), ''), 'status', a.status,
        'meta', a.meta, 'obs', a.obs, 'links', a.links, 'criadoEm', a.criado_em, 'criadoPor', a.criado_por,
        'atualizadoEm', a.atualizado_em, 'atualizadoPor', a.atualizado_por)) from public.acoes a), '[]'),
    'pautas', coalesce((select jsonb_object_agg(p.usuario, jsonb_build_object('itens', to_jsonb(p.itens), 'atualizadoEm', p.atualizado_em)) from public.pauta p), '{}'),
    'nomes', coalesce((select jsonb_object_agg(x.id, x.nome) from public.usuarios x), '{}'));
end $$;

create or replace function public._limpa_acao(b jsonb) returns jsonb language plpgsql immutable as $$
declare links jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('rotulo', left(btrim(coalesce(l->>'rotulo','')), 80), 'url', left(btrim(l->>'url'), 1000))), '[]') into links
  from (select l from jsonb_array_elements(case when jsonb_typeof(b->'links') = 'array' then b->'links' else '[]' end) l limit 20) s
  where btrim(coalesce(l->>'url','')) ~* '^https?://';
  return jsonb_build_object(
    'titulo', left(btrim(coalesce(b->>'titulo','')), 400),
    'tipo', case when b->>'tipo' in ('Tarefa','Plano de ação','Projeto de melhoria') then b->>'tipo' else 'Tarefa' end,
    'origem', case when b->>'origem' in ('Desvio de meta','Melhoria','Demanda não prevista') then b->>'origem' else '' end,
    'area', left(btrim(coalesce(b->>'area','')), 80),
    'prioridade', case when b->>'prioridade' in ('Urgente','Prioritário','Normal','Backlog') then b->>'prioridade' else '' end,
    'responsavel', left(btrim(coalesce(b->>'responsavel','')), 160),
    'prazo', case when coalesce(b->>'prazo','') ~ '^\d{4}-\d{2}-\d{2}$' then b->>'prazo' else '' end,
    'status', case when b->>'status' in ('Aberta','Em andamento','Concluída') then b->>'status' else 'Aberta' end,
    'meta', left(btrim(coalesce(b->>'meta','')), 200),
    'obs', left(btrim(coalesce(b->>'obs','')), 2000),
    'links', links);
end $$;

create or replace function public._acao_json(a public.acoes) returns jsonb language sql immutable as $$
  select jsonb_build_object('titulo', a.titulo, 'tipo', a.tipo, 'origem', a.origem, 'area', a.area, 'prioridade', a.prioridade,
    'responsavel', a.responsavel, 'prazo', coalesce(to_char(a.prazo, 'YYYY-MM-DD'), ''), 'status', a.status, 'meta', a.meta, 'obs', a.obs, 'links', a.links) $$;

create or replace function public.acao_criar(b jsonb) returns text language plpgsql security definer set search_path = public as $$
declare u public.usuarios := public._eu(); c jsonb := public._limpa_acao(b); novo text;
begin
  perform public._exige(u, 'acoes.criar', 'Seu perfil não cria itens no plano de ação.');
  if c->>'titulo' = '' then raise exception 'Escreva o título do item.'; end if;
  if not public._area_permitida(c->>'area', u) then raise exception 'Você só cria itens da sua área.' using errcode = '42501'; end if;
  if not ('acoes.gerenciar' = any(public._perms(u))) then c := c || '{"prioridade": ""}'; end if;
  insert into public.acoes (titulo, tipo, origem, area, prioridade, responsavel, prazo, status, meta, obs, links, criado_por, atualizado_por)
  values (c->>'titulo', c->>'tipo', c->>'origem', c->>'area', c->>'prioridade', c->>'responsavel', nullif(c->>'prazo','')::date,
          c->>'status', c->>'meta', c->>'obs', c->'links', u.id, u.id) returning id into novo;
  perform public._reg(u, 'criou', 'Plano de ação', c->>'titulo', public._area_of(c->>'area'),
    public._diff('{}', c, array['titulo','tipo','origem','area','prioridade','responsavel','prazo','status','meta','obs','links']));
  return novo;
end $$;

create or replace function public.acao_atualizar(p_id text, b jsonb) returns void language plpgsql security definer set search_path = public as $$
declare u public.usuarios := public._eu(); x public.acoes; c jsonb := public._limpa_acao(b); antes jsonb; mud jsonb;
begin
  select * into x from public.acoes where id = p_id for update;
  if x.id is null then raise exception 'Item não encontrado.'; end if;
  if not ('acoes.editar' = any(public._perms(u))) or not public._no_escopo(x, u, 'editar') then
    raise exception 'Você não pode editar este item.' using errcode = '42501'; end if;
  if c->>'titulo' = '' then raise exception 'Escreva o título do item.'; end if;
  if c->>'area' <> x.area and not public._area_permitida(c->>'area', u) then raise exception 'Você só move itens para a sua área.' using errcode = '42501'; end if;
  antes := public._acao_json(x);
  if not ('acoes.gerenciar' = any(public._perms(u)) and public._no_escopo(x, u, 'gerenciar')) then
    c := c || jsonb_build_object('responsavel', antes->>'responsavel', 'prazo', antes->>'prazo', 'prioridade', antes->>'prioridade');
  end if;
  update public.acoes set titulo = c->>'titulo', tipo = c->>'tipo', origem = c->>'origem', area = c->>'area', prioridade = c->>'prioridade',
    responsavel = c->>'responsavel', prazo = nullif(c->>'prazo','')::date, status = c->>'status', meta = c->>'meta', obs = c->>'obs',
    links = c->'links', atualizado_em = now(), atualizado_por = u.id where id = p_id;
  mud := public._diff(antes, c, array['titulo','tipo','origem','area','prioridade','responsavel','prazo','status','meta','obs','links']);
  if jsonb_array_length(mud) > 0 then perform public._reg(u, 'alterou', 'Plano de ação', c->>'titulo', public._area_of(c->>'area'), mud); end if;
end $$;

create or replace function public.acao_excluir(p_id text) returns void language plpgsql security definer set search_path = public as $$
declare u public.usuarios := public._eu(); x public.acoes;
begin
  select * into x from public.acoes where id = p_id;
  if x.id is null then raise exception 'Item não encontrado.'; end if;
  if not ('acoes.gerenciar' = any(public._perms(u))) or not public._no_escopo(x, u, 'gerenciar') then
    raise exception 'Você não pode excluir este item.' using errcode = '42501'; end if;
  delete from public.acoes where id = p_id;
  update public.pauta set itens = array_remove(itens, p_id) where p_id = any(itens);
  perform public._reg(u, 'excluiu', 'Plano de ação', x.titulo, public._area_of(x.area), jsonb_build_array(jsonb_build_object('campo','item','anterior',x.titulo,'novo','')));
end $$;

create or replace function public.pauta_salvar(p_itens text[]) returns void language plpgsql security definer set search_path = public as $$
declare u public.usuarios := public._eu(); limpos text[];
begin
  perform public._exige(u, 'pauta.marcar', 'Seu perfil não marca a pauta.');
  select coalesce(array_agg(distinct i), '{}') into limpos from unnest(coalesce(p_itens, '{}')) i where exists (select 1 from public.acoes a where a.id = i);
  insert into public.pauta (usuario, itens, atualizado_em) values (u.id, limpos[1:300], now())
  on conflict (usuario) do update set itens = excluded.itens, atualizado_em = now();
end $$;

-- usuários
create or replace function public.usuarios_listar() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare u public.usuarios := public._eu(); esc text := public._escopo(u.perfil);
begin
  perform public._exige(u, 'usuarios.ver', 'Sem permissão para ver usuários.');
  return jsonb_build_object('usuarios', coalesce((select jsonb_agg(public._publico(x) order by x.nome) from public.usuarios x
    where esc = 'eng' or x.id = u.id or (esc = 'area' and x.area = u.area)), '[]'));
end $$;

create or replace function public.admin_atualizar_usuario(p_id uuid, b jsonb) returns void language plpgsql security definer set search_path = public as $$
declare u public.usuarios := public._eu(); alvo public.usuarios; v jsonb; antes jsonb; depois jsonb; mud jsonb;
begin
  perform public._exige(u, 'usuarios.gerenciar', 'Só o Admin altera usuários.');
  select * into alvo from public.usuarios where id = p_id for update;
  if alvo.id is null then raise exception 'Usuário não encontrado.'; end if;
  if p_id = u.id then b := b || jsonb_build_object('perfil', alvo.perfil, 'status', alvo.status); end if;
  v := public._validar_cadastro(b, p_id);
  if alvo.perfil = 'Admin' and alvo.status = 'Ativo' and (v->>'perfil' <> 'Admin' or v->>'status' <> 'Ativo') and public._admins_ativos(p_id) < 1 then
    raise exception 'É preciso manter pelo menos um outro Admin ativo antes de mudar este.'; end if;
  antes := public._publico(alvo);
  update public.usuarios set nome = v->>'nome', email = v->>'email', perfil = v->>'perfil', status = v->>'status', area = v->>'area', depto = v->>'depto',
    mods = array(select jsonb_array_elements_text(v->'mods')), areas_vis = array(select jsonb_array_elements_text(v->'areasVis')),
    atualizado_em = now(), atualizado_por = u.id where id = p_id returning * into alvo;
  if alvo.email <> antes->>'email' then
    begin update auth.users set email = alvo.email where id = p_id; exception when others then null; end;
  end if;
  if alvo.status <> 'Ativo' then perform public._encerrar_sessoes(p_id); end if;
  depois := public._publico(alvo);
  mud := public._diff(public._legivel(antes), public._legivel(depois), array['nome','email','area','depto','perfil','status','mods','areasVis']);
  if jsonb_array_length(mud) > 0 then perform public._reg(u, 'alterou', 'Usuários', alvo.nome, alvo.area, mud); end if;
end $$;

-- permissões
create or replace function public.permissoes_ler() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare u public.usuarios := public._eu();
begin
  perform public._exige(u, 'usuarios.ver', 'Sem permissão.');
  return jsonb_build_object(
    'catalogo', '[{"mod":"Painel","acoes":[["gpd.ver","Ver GPD N1 (mensal)"],["wbr.ver","Ver WBR (indicadores das áreas)"],["ocupacao.ver","Ver ocupação agregada"],["ocupacao.pessoas","Ver ocupação por pessoa"],["custos.ver","Ver custos e despesas"]]},{"mod":"Plano de ação","acoes":[["acoes.ver","Ver itens"],["acoes.criar","Criar itens"],["acoes.editar","Editar título, status, links e observações"],["acoes.gerenciar","Definir responsável, prazo e prioridade; excluir itens"],["pauta.marcar","Marcar itens para a reunião"]]},{"mod":"Usuários","acoes":[["usuarios.ver","Ver a tela de usuários"],["historico.baixar","Baixar o histórico (CSV)"],["usuarios.gerenciar","Cadastrar, editar, redefinir senha e excluir usuários"],["permissoes.editar","Editar esta matriz"]]}]'::jsonb,
    'matriz', (select jsonb_object_agg(p, coalesce((select jsonb_agg(m.permissao) from public.matriz m where m.perfil = p), '[]'))
               from unnest(array['Diretor','Gestor','Analista','Consulta']) p),
    'soAdmin', to_jsonb(public._so_admin()), 'consultaMax', to_jsonb(public._consulta_max()));
end $$;

create or replace function public.permissoes_salvar(m jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.usuarios := public._eu(); p text; novo text[]; velho text[]; mud jsonb := '[]'; x text;
begin
  perform public._exige(u, 'permissoes.editar', 'Só o Admin edita a matriz.');
  foreach p in array array['Diretor','Gestor','Analista','Consulta'] loop
    select coalesce(array_agg(distinct a), '{}') into novo from jsonb_array_elements_text(case when jsonb_typeof(m->p) = 'array' then m->p else '[]' end) a
      where a = any(public._todas()) and not (a = any(public._so_admin())) and (p <> 'Consulta' or a = any(public._consulta_max()));
    select coalesce(array_agg(permissao), '{}') into velho from public.matriz where perfil = p;
    foreach x in array novo loop if not (x = any(velho)) then mud := mud || jsonb_build_object('campo', p || ' · ' || x, 'anterior', 'não', 'novo', 'sim'); end if; end loop;
    foreach x in array velho loop if not (x = any(novo)) then mud := mud || jsonb_build_object('campo', p || ' · ' || x, 'anterior', 'sim', 'novo', 'não'); end if; end loop;
    delete from public.matriz where perfil = p;
    insert into public.matriz (perfil, permissao) select p, a from unnest(novo) a;
  end loop;
  if jsonb_array_length(mud) > 0 then perform public._reg(u, 'alterou', 'Permissões', 'Matriz de permissões', null, mud); end if;
  return (public.permissoes_ler())->'matriz';
end $$;

-- histórico (para o CSV), no alcance de quem pede
create or replace function public.historico_listar() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare u public.usuarios := public._eu(); esc text := public._escopo(u.perfil);
begin
  perform public._exige(u, 'historico.baixar', 'Sem permissão para baixar o histórico.');
  return coalesce((select jsonb_agg(jsonb_build_object('quando', h.quando, 'quemNome', h.quem_nome, 'quemEmail', h.quem_email, 'perfil', h.perfil,
      'acao', h.acao, 'modulo', h.modulo, 'registro', h.registro, 'area', public._area_nome(h.area), 'mudancas', h.mudancas) order by h.id desc)
    from public.historico h where esc = 'eng' or h.quem = u.id or (esc = 'area' and h.area = u.area)), '[]');
end $$;

-- depois que a própria pessoa troca a senha pelo login
create or replace function public.minha_senha_trocada() returns void language plpgsql security definer set search_path = public as $$
declare u public.usuarios := public._eu();
begin
  update public.usuarios set senha_provisoria = false where id = u.id;
  perform public._reg(u, 'trocou a própria senha', 'Usuários', u.nome, u.area, '[{"campo":"senha","anterior":"","novo":"alterada"}]');
end $$;

-- ---------- funções usadas só pela função de servidor admin-usuarios ----------
create or replace function public.svc_pode(p_uid uuid, p_perm text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select p_perm = any(public._perms(x)) from public.usuarios x where x.id = p_uid), false) $$;

create or replace function public.svc_validar(b jsonb) returns jsonb language sql stable security definer set search_path = public as $$
  select public._validar_cadastro(b, null) $$;

create or replace function public.svc_criar_perfil(p_autor uuid, p_id uuid, b jsonb) returns void language plpgsql security definer set search_path = public as $$
declare a public.usuarios; v jsonb := public._validar_cadastro(b, null);
begin
  select * into a from public.usuarios where id = p_autor;
  insert into public.usuarios (id, nome, email, perfil, status, area, depto, mods, areas_vis, senha_provisoria, criado_por)
  values (p_id, v->>'nome', v->>'email', v->>'perfil', v->>'status', v->>'area', v->>'depto',
          array(select jsonb_array_elements_text(v->'mods')), array(select jsonb_array_elements_text(v->'areasVis')), true, p_autor);
  perform public._reg(a, 'cadastrou', 'Usuários', v->>'nome', v->>'area',
    public._diff('{}', public._legivel(v), array['nome','email','area','depto','perfil','status','mods','areasVis']));
end $$;

create or replace function public.svc_senha_redefinida(p_autor uuid, p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare a public.usuarios; x public.usuarios;
begin
  select * into a from public.usuarios where id = p_autor;
  update public.usuarios set senha_provisoria = true where id = p_id returning * into x;
  perform public._encerrar_sessoes(p_id);
  perform public._reg(a, 'redefiniu senha', 'Usuários', x.nome, x.area, '[{"campo":"senha","anterior":"","novo":"redefinida pelo Admin"}]');
end $$;

create or replace function public.svc_antes_de_excluir(p_autor uuid, p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare a public.usuarios; x public.usuarios;
begin
  select * into a from public.usuarios where id = p_autor;
  select * into x from public.usuarios where id = p_id;
  if x.id is null then raise exception 'Usuário não encontrado.'; end if;
  if p_id = p_autor then raise exception 'Você não pode excluir o próprio usuário.'; end if;
  if x.perfil = 'Admin' and x.status = 'Ativo' and public._admins_ativos(p_id) < 1 then raise exception 'Não é possível excluir o último Admin ativo.'; end if;
  perform public._encerrar_sessoes(p_id);
  perform public._reg(a, 'excluiu', 'Usuários', x.nome, x.area,
    jsonb_build_array(jsonb_build_object('campo','usuário','anterior', x.nome || ' <' || x.email || '> · ' || x.perfil, 'novo','')));
end $$;

-- ---------- quem pode chamar o quê ----------
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.eu(), public.painel(), public.app(), public.acoes_listar(), public.acao_criar(jsonb), public.acao_atualizar(text, jsonb),
  public.acao_excluir(text), public.pauta_salvar(text[]), public.usuarios_listar(), public.admin_atualizar_usuario(uuid, jsonb),
  public.permissoes_ler(), public.permissoes_salvar(jsonb), public.historico_listar(), public.minha_senha_trocada() to authenticated;
grant execute on function public.svc_pode(uuid, text), public.svc_validar(jsonb), public.svc_criar_perfil(uuid, uuid, jsonb),
  public.svc_senha_redefinida(uuid, uuid), public.svc_antes_de_excluir(uuid, uuid) to service_role;
