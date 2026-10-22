# Instalação no Supabase (SQL Editor)

`INSTALAR.sql` é a **fonte única** do banco. Este diretório tem o mesmo script dividido em
**11 blocos** para colar no Supabase SQL Editor, na ordem.

> Todos os blocos foram validados um a um, em transação única, em **base nova** e em **base legada**
> (PostgreSQL 16 local). Resultado final idêntico nos dois casos:
> **9 tabelas · 6 views · 37 políticas · 12 funções · 5 triggers**.

---

## Antes de começar

1. **Faça backup** (o script altera o schema de produção):
   ```powershell
   $env:DATABASE_URL = "postgresql://postgres:SUA_SENHA@db.XXXX.supabase.co:5432/postgres"
   .\scripts\backup.ps1
   ```
2. Abra o projeto no Supabase > **SQL Editor** > **New query**.

---

## Opção A — colar tudo de uma vez (mais simples)

1. Abra [`../INSTALAR.sql`](../INSTALAR.sql) num editor de texto.
2. **Ctrl+A → Ctrl+C**.
3. Cole no SQL Editor e clique em **Run**.

Rode em **uma execução só**: o SQL Editor executa o conteúdo numa transação única, e o script foi
testado exatamente assim (base nova e base legada).

**Se aparecer `ERROR: unsafe use of new value ... of enum type`**, use a Opção B — o bloco de enums
precisa de uma execução isolada.

---

## Opção B — bloco a bloco (mais seguro, permite ver onde falhou)

Cole e execute **na ordem**, um por vez. Ao final de cada um, o SQL Editor deve mostrar sucesso.

| # | Arquivo | O que faz | Como conferir |
|---|---|---|---|
| 1 | `00_enums.sql` | Cria os enums (e adiciona `'parcelado'`/`'matricula'` se ainda faltarem) | Sem erro |
| 2 | `01_tabelas.sql` | 9 tabelas + FKs | Sem erro |
| 3 | `02_colunas.sql` | Colunas adicionadas depois (`cpf`, `nascimento`, `endereco`, `bairro`, `cidade`, `cep`…) | Sem erro |
| 4 | `03_constraints.sql` | Constraints com nome determinístico + `public.cpf_valido()` | Sem erro |
| 5 | `04_indices.sql` | Índices (inclui `uq_matriculas_individual` e os de CPF) | Sem erro |
| 6 | `05_funcoes_rls.sql` | `usuario_atual`, `administrador_atual`, `professor_atual` (SECURITY DEFINER), `health_check` | Sem erro |
| 7 | `06_rls_politicas.sql` | RLS + 37 políticas | Sem erro |
| 8 | `07_regras_negocio.sql` | RPCs (`gerar_mensalidades`, `gerar_carne`) + triggers de financeiro + RN14 | Sem erro |
| 9 | `08_views.sql` | 6 views de relatório | Sem erro |
| 10 | `09_grants.sql` | Permissões para `anon`/`authenticated`/`service_role` + `REVOKE ... FROM PUBLIC` nas funções | Sem erro |
| 11 | `10_checagem_final.sql` | Consulta de conferência | Ver resultado esperado abaixo |

> ⚠️ Se o passo 1 rodar e o 2 der erro do tipo `unsafe use of new value`, **reinicie a execução
> do passo 1** (ou pule direto para o passo 2 — o enum já está criado).

---

## Resultado esperado (bloco 10)

```
 tabelas | views | politicas | funcoes | triggers
---------+-------+-----------+---------+----------
       9 |     6 |        37 |      12 |        5
```

Se os números baterem, o banco está no estado esperado.

---

## Avisos esperados (não são erros)

O script **avisa e continua** quando a base legada tem dados inconsistentes:

| Aviso | O que fazer |
|---|---|
| `CPF invalido em public.alunos.cpf (N registro(s) legado(s))` | Corrija os dados e rode de novo (query abaixo) |
| `CPF duplicado (...): uq_alunos_cpf e uq_professores_cpf NAO foram criados` | Resolva a duplicidade e rode de novo — os índices são criados |
| `tempo_estimado fora do intervalo (0 a 12h) em N registro(s) legado(s)` | Ajuste os itens da grade com tempo absurdo |

Queries de diagnóstico:

```sql
-- CPFs duplicados
SELECT 'alunos' AS tabela, regexp_replace(cpf,'[^0-9]','','g') AS cpf, count(*)
  FROM public.alunos WHERE cpf IS NOT NULL GROUP BY 1,2 HAVING count(*) > 1;
SELECT 'professores', regexp_replace(cpf,'[^0-9]','','g'), count(*)
  FROM public.professores WHERE cpf IS NOT NULL GROUP BY 1,2 HAVING count(*) > 1;

-- CPFs com dígitos inválidos
SELECT * FROM public.alunos WHERE cpf IS NOT NULL AND NOT public.cpf_valido(cpf);
SELECT * FROM public.professores WHERE cpf IS NOT NULL AND NOT public.cpf_valido(cpf);
```

Depois de corrigir, **rode o `INSTALAR.sql` de novo** (é idempotente) — o que faltou é criado.

---

## Depois de instalar

**Atualização de 21/10/2026 (se você instalou antes deste dia):** o bloco 9 passou a **revogar o
`EXECUTE` padrão do Postgres** (o Postgres dá `EXECUTE` de toda função nova ao papel `PUBLIC`,
o que deixava as RPCs de financeiro chamáveis por visitante sem login). Basta rodar **só o
`09_grants.sql`** de novo — é idempotente e leva 1 segundo.

> ⚠️ **Atenção ao resultado da conferência:** revogar **de `PUBLIC` sozinho não resolve** no
> Supabase. O Supabase entrega o schema `public` com `GRANT ALL ON ALL FUNCTIONS ... TO anon` e
> `ALTER DEFAULT PRIVILEGES ... GRANT ALL ON FUNCTIONS TO anon` — ou seja, o papel `anon` tem um
> **privilégio explícito** que sobrevive ao `REVOKE ... FROM PUBLIC`. Por isso o bloco 9 revoga
> **dos dois** (`PUBLIC` **e** `anon`). Se a consulta abaixo devolver `12` em vez de `4`, o
> `09_grants.sql` antigo (só `FROM PUBLIC`) ainda está valendo: rode o arquivo atual.

Para conferir:

```sql
SELECT count(*) AS funcoes_executaveis_por_anon
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND has_function_privilege('anon', p.oid, 'EXECUTE');
-- esperado: 4  (health_check + usuario_atual + administrador_atual + professor_atual)
```

As 3 auxiliares de RLS **precisam** ficar executáveis pelo `anon`: são elas que as políticas de
RLS chamam ao avaliar cada linha (sem `EXECUTE`, a consulta falha com "permissão negada" em vez
de devolver lista vazia). São inofensivas para quem não está logado (`auth.uid()` é `NULL`).

> Função nova criada depois da instalação volta a receber `EXECUTE` do `anon` (default privilege
> do Supabase). Se criar RPCs no futuro, acrescente o `REVOKE ... FROM anon` correspondente.

**Opcional — dados de teste** (`../SEED_TESTE.sql`, idempotente): 10 professores, 10 turmas,
30 alunos, 30 matrículas e as parcelas do carnê. Não é necessário em produção.

**Opcional — dados de demonstração** (`../SEED_DEMO.sql`, idempotente): 5 professores, 8 turmas,
20 alunos, 20 matrículas (mensal / carnê 6x e 12x / aula avulsa / individual-VIP), 96 lançamentos
financeiros (pagos, atrasados, ajustes com desconto, taxa de matrícula), 29 aulas ministradas e
49 desempenhos — para ver o painel, os relatórios e os gráficos com conteúdo. No fim do arquivo
há o bloco `DELETE DE LIMPEZA` para remover tudo.

**Realinhamento de vencimentos** (opcional): as mensalidades já geradas antes da instalação #11
mantêm o vencimento antigo. Para alinhar ao `dia_vencimento`:

```sql
UPDATE public.financeiro f
   SET vencimento = date_trunc('month', f.competencia)::date
                     + (mt.dia_vencimento - 1) * interval '1 day'
  FROM public.matriculas mt
 WHERE f.matricula_id = mt.id
   AND f.tipo = 'mensalidade'
   AND f.status IN ('pendente','atrasada')
   AND f.vencimento <> date_trunc('month', f.competencia)::date
                     + (mt.dia_vencimento - 1) * interval '1 day';
```

**Teste rápido na interface** (após o deploy):

1. Login como admin → painel sem erro.
2. `Turmas` → 10 turmas listadas, professor ativo.
3. `Alunos` → cadastrar um aluno com CPF `111.444.777-35` (válido) e tentar repetir o CPF → deve
   ser bloqueado.
4. `Financeiro` → "Ajustar" um lançamento com **valor negativo** → deve aceitar (desconto).
5. `Matrículas` → carnê de um aluno parcelado → deve imprimir as parcelas (o bug #15 está corrigido).
6. `Professores` → tentar inativar um professor com turma ativa → deve ser bloqueado (RN14).

---

## Problemas comuns

| Sintoma | Causa | Solução |
|---|---|---|
| `relation "auth.users" does not exist` | rodando fora do Supabase | Em outro ambiente, crie o schema `auth` antes (veja `testes/sql/mock_auth.sql`) |
| `stack depth limit exceeded` ao logar | RLS recursivo | As funções `SECURITY DEFINER` do bloco 6 resolvem — confirme que `05_funcoes_rls.sql` rodou |
| `unsafe use of new value` | enum novo na mesma transação | Rode `00_enums.sql` isolado e siga a partir do bloco 2 |
| `permission denied for schema public` | falta o `09_grants.sql` | Rode o bloco 9 |
| Interface mostra "aplique INSTALAR.sql no Supabase" | views de progresso faltando | Rode o bloco 8 |
