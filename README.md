# Dashboard Financeiro

Dashboard de finanças pessoais: carteiras, receitas, despesas e lançamentos
recorrentes (salário, aluguel…), com saldo consolidado.

**Stack:** Rails 7.2 · Ruby 3.2.2 · PostgreSQL 15 · GraphQL (graphql-ruby) · JWT.

## Rodando

Precisa de Docker e Docker Compose.

```bash
cp .env.example .env        # preencha POSTGRES_USER e POSTGRES_PASSWORD
docker compose up           # app em http://localhost:3000 + Postgres
docker compose exec app bin/rails db:prepare
```

Abra `http://localhost:3000/login`. Ainda não há tela de cadastro: crie o primeiro
usuário pelo console (a senha precisa ter 10+ caracteres):

```bash
docker compose exec app bin/rails console
> User.create!(email: "voce@exemplo.com", password: "uma-senha-longa")
```

Em desenvolvimento o GraphiQL fica em `http://localhost:3000/graphiql`.

## Testes e qualidade

Tudo dentro do container (`docker compose exec app ...`):

```bash
bin/rails test              # suíte (Minitest)
bin/rubocop                 # lint (rubocop-rails-omakase)
bin/brakeman --no-pager     # análise estática de segurança
bin/importmap audit         # dependências JS
```

O CI (`.github/workflows/ci.yml`) roda esses quatro a cada PR.

## Como funciona

- **GraphQL** (`POST /graphql`): usuários, carteiras, receitas, despesas,
  recorrências e resumos financeiros. Tudo é escopado ao usuário autenticado.
- **REST** (`/api/v1/auth/*`): só autenticação (`login`, `me`, `logout`).
- **Páginas** (`/login`, `/dashboard`): HTML servido pelo Rails que consome as duas
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
  -d '{"query":"{ balance totalIncome totalExpense wallets { name balance } }"}'
```

O logout e a troca de senha invalidam todos os tokens do usuário. Login e cadastro
têm limite de tentativas (Rack::Attack).

### Lançamentos recorrentes

Um template (descrição, valor, dia do mês, datas) gera lançamentos reais. A geração
é idempotente e nunca cria datas futuras. Ela roda quando o dashboard abre, mas o
ideal é **agendar uma vez por dia**, para os saldos não dependerem de uma visita:

```bash
bin/rails recurring:sync
```

Exemplo de cron (00:05): `5 0 * * * cd /caminho/do/app && bin/rails recurring:sync`.

## Produção

Veja o `Dockerfile` e defina `RAILS_MASTER_KEY` e `APP_DATABASE_PASSWORD`
(ver `.env.example`). O fuso da aplicação é `Brasilia`.
