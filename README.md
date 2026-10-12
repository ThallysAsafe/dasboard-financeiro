# Dashboard Financeiro

Dashboard de finanças pessoais: carteira, receitas, despesas e lançamentos
recorrentes (salário, aluguel…), com saldo consolidado.

**Stack:** Rails 8.1 · Ruby 3.4.11 · PostgreSQL 15 · GraphQL (graphql-ruby) · JWT.

## Rodando

Precisa de Docker e Docker Compose.

```bash
cp .env.example .env        # preencha POSTGRES_USER e POSTGRES_PASSWORD
docker compose up           # app em http://localhost:3000 + Postgres
docker compose exec app bin/rails db:prepare
```

Abra `http://localhost:3000/signup` e crie sua conta (senha com 10+ caracteres): a
carteira é criada junto e você já entra no dashboard. Depois é só usar
`http://localhost:3000/login`.

Também dá para criar pelo console:

```bash
docker compose exec app bin/rails console
> User.create!(email: "voce@exemplo.com", password: "uma-senha-longa")
```

Em desenvolvimento o GraphiQL fica em `http://localhost:3000/graphiql`.

## Testes e qualidade

Tudo dentro do container (`docker compose exec app ...`):

```bash
bin/rails test              # suíte rápida (Minitest: modelos, GraphQL, integração)
bin/rails test:system       # testes de navegador (Chrome headless): login, cadastro, dashboard
bin/rubocop                 # lint (rubocop-rails-omakase)
bin/brakeman --no-pager     # análise estática de segurança
bin/importmap audit         # dependências JS
```

Os testes de sistema precisam do Chromium, que o `Dockerfile.dev` instala (variáveis
`CHROME_BIN` e `CHROMEDRIVER_PATH`); depois de atualizar o repositório, rode
`docker compose build app`. O CI (`.github/workflows/ci.yml`) roda a suíte, os testes de
sistema, o rubocop, o brakeman e a auditoria de JS a cada PR.

## Como funciona

- **GraphQL** (`POST /graphql`): usuários, a carteira, receitas, despesas,
  recorrências e resumos financeiros. Tudo é escopado ao usuário autenticado.
- **REST** (`/api/v1/auth/*`): só autenticação (`signup`, `login`, `me`, `logout`, recuperar senha e confirmar e-mail).
- **Páginas** (`/signup`, `/login`, `/dashboard`, `/password/forgot`, `/password/reset`, `/email/confirm`): HTML servido pelo Rails que consome as duas
  APIs pelo navegador.

A arquitetura em detalhe (modelo de domínio, regras da recorrência, armadilhas de
fuso horário) está em [`CLAUDE.md`](CLAUDE.md).

### Autenticação

O navegador usa um cookie `HttpOnly` (o JavaScript da página nunca vê o token), e a
API só o aceita em requisições com `X-Requested-With: XMLHttpRequest` (defesa contra
CSRF). Clientes que não são navegador usam um token Bearer:

```bash
# 1. obter o token
curl -s localhost:3000/graphql -H 'Content-Type: application/json' \
  -d '{"query":"mutation { userLogin(email: \"voce@exemplo.com\", password: \"...\") { token errors } }"}'

# 2. usar
curl -s localhost:3000/graphql -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"query":"{ balance totalIncome totalExpense wallet { name balance } }"}'
```

O logout e a troca de senha invalidam todos os tokens do usuário. Login e cadastro
têm limite de tentativas (Rack::Attack). As mensagens de erro saem em pt-BR.

### E-mail: recuperar senha e confirmar e-mail

- **Esqueci minha senha** (link na tela de login): pede o e-mail, recebe um link que vale
  30 minutos e **uma vez só**, escolhe a nova senha. A resposta é a mesma exista ou não a
  conta, e trocar a senha derruba as sessões abertas.
- **Confirmar e-mail:** o cadastro envia um link (vale 3 dias). Enquanto não confirma, o
  painel mostra um aviso com "Reenviar e-mail"; ele não bloqueia o uso.
- Os links usam tokens assinados pelo Rails, sem guardar nada no banco, e a confirmação e
  a troca de senha só acontecem por POST (abrir o link não muda nada).

**Em desenvolvimento nada é enviado de verdade:** o `docker compose up` sobe o **Mailpit**,
uma caixa de entrada local. Abra http://localhost:8025 para ler os e-mails que o app mandou.

Em produção qualquer provedor SMTP serve, só com variáveis de ambiente (veja o
`.env.example`: `SMTP_ADDRESS`, `SMTP_USER`, `SMTP_PASSWORD`, `MAIL_FROM`, `APP_HOST`),
sem mudar o código.

### Carteira

Cada usuário tem uma carteira, criada junto com a conta. No cartão do dashboard, **"Editar
carteira"** altera o nome e o **saldo inicial** (pode ser negativo). O saldo atual é o saldo
inicial mais as receitas e menos as despesas. Valores vão até R$ 99.999.999,99.

### Lançamentos recorrentes

Ao criar uma receita ou despesa, marque **"Repetir todo mês"** e escolha o dia: isso
cria um template que gera o lançamento de verdade todo mês. A geração é idempotente
e nunca cria datas futuras (um template do dia 10 só gera o lançamento do mês a
partir do dia 10).

**Quem dispara é um scheduler embutido** (GoodJob, com a fila no próprio Postgres):
todo dia às **00:05 (horário de Brasília)** roda o `SyncRecurringEntriesJob` para
todos os usuários. Não precisa de cron externo, Redis nem de um processo separado: o
agendador roda dentro do próprio servidor web (`execution_mode = :async`).

Se o app estiver fora do ar às 00:05, nada se perde: o job seguinte, ou a próxima
abertura do dashboard, gera o que ficou devido.

Para rodar na mão: `bin/rails recurring:sync`. A configuração do horário está em
`config/application.rb` (`config.good_job.cron`).

## Produção

Veja o `Dockerfile` e defina `RAILS_MASTER_KEY` e `APP_DATABASE_PASSWORD`
(ver `.env.example`). O fuso da aplicação é `Brasilia`.
