# Engenharia 360

Modelo de gestão da Diretoria de Engenharia da Lightwall: GPD N1, WBR, plano de ação, pauta da reunião e gestão de acessos.

## Como funciona
- **GitHub Pages** publica só a tela de login e um carregador (`index.html`, `login.html`). Não há dados nem regras de negócio aqui.
- **Supabase** guarda tudo o que é da empresa: usuários, permissões, plano de ação, histórico, números do painel e o próprio código das telas. Só quem faz login e está ativo recebe esse conteúdo.
- As tabelas ficam fechadas; todo acesso passa por funções do banco que conferem perfil, permissão e alcance de quem chamou (`supabase/01_estrutura.sql`).
- Cadastro, redefinição de senha e exclusão de usuários passam pela função de servidor `supabase/functions/admin-usuarios`, que usa a chave de serviço sem expô-la.

## Arquivos
| Arquivo | Para quê |
|---|---|
| `config.js` | Endereço do projeto Supabase e chave **pública** (anon/publishable). Nunca a chave secreta. |
| `supabase/01_estrutura.sql` | Tabelas, regras de acesso e funções. Rodar no SQL Editor. |
| `supabase/03_primeiro_admin.sql` | Liga o primeiro usuário ao perfil Admin. |
| `supabase/functions/admin-usuarios/index.ts` | Função de servidor de gestão de usuários. |
| `vendor/supabase.js` | Biblioteca oficial supabase-js 2.117.2 (licença MIT). |

A carga com o código das telas e os dados (`Engenharia360_dados_*.sql`) é **privada** e não fica neste repositório: roda direto no SQL Editor do Supabase. Atualizar números ou telas = rodar uma nova carga; o GitHub não muda.
