# Cliente Supabase vendorizado

Bundle ESM do `@supabase/supabase-js` **servido pela própria aplicação** (sem CDN de terceiros no
caminho crítico de runtime).

| Arquivo | Pacote | Versão |
|---|---|---|
| `supabase-supabase-js-2.45.0.esm.js` | `@supabase/supabase-js` | 2.45.0 |
| `supabase-auth-js-2.64.4.esm.js` | `@supabase/auth-js` | 2.64.4 |
| `supabase-functions-js-2.4.1.esm.js` | `@supabase/functions-js` | 2.4.1 |
| `supabase-postgrest-js-1.15.8.esm.js` | `@supabase/postgrest-js` | 1.15.8 |
| `supabase-realtime-js-2.10.2.esm.js` | `@supabase/realtime-js` | 2.10.2 |
| `supabase-storage-js-2.6.0.esm.js` | `@supabase/storage-js` | 2.6.0 |
| `supabase-node-fetch-2.6.15.esm.js` | `@supabase/node-fetch` | 2.6.15 |
| `ws-8.17.1.esm.js` | `ws` | 8.17.1 (usado só em Node, pelo realtime) |

**Versão única:** `package.json` fixa `@supabase/supabase-js` em `2.45.0` (sem `^`), igual à
versão vendorizada. O front importa em `public/js/supabase.js`.

**Procedimento de atualização** (quando subir a versão do pacote):

1. `npm install @supabase/supabase-js@<nova>`
2. Baixar os bundles `+esm` do jsDelivr e reescrever os import specifiers `/npm/<pkg>@<ver>/+esm`
   para `./<arquivo-local>.esm.js` (é o que o script de vendoring faz).
3. Atualizar o caminho do import em `public/js/supabase.js` e o nome dos arquivos aqui.
4. Testar: `node --check` não serve para ESM — importar o bundle em Node (`{"type":"module"}`)
   e chamar `createClient()`.

Licença: MIT (Supabase). Os bundles redistributed aqui são minificados e não alterados, exceto
pelo caminho dos imports.
