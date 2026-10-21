-- Engenharia 360 · liga o seu usuário (criado em Authentication › Users) ao perfil Admin.
-- Troque o nome e o e-mail se for outra pessoa. Rode uma vez, depois de criar o usuário.
insert into public.usuarios (id, nome, email, perfil, area, status, senha_provisoria)
select id, 'Udini Donelis', lower(email), 'Admin', 'DIR', 'Ativo', false
from auth.users where lower(email) = 'udinidonelis@lightwallbrasil.com'
on conflict (id) do update set perfil = 'Admin', status = 'Ativo';

select nome, email, perfil, status from public.usuarios;
