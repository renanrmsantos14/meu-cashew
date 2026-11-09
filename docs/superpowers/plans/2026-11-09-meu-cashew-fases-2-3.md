# Meu Cashew: Fases 2 e 3 (Android e web desktop dentro do fork). Plano de implementação

> **Para agentes:** use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans, tarefa por tarefa. Passos com checkbox (`- [ ]`). Cada tarefa cabe numa revisão.

**Goal:** levar o Meu Cashew (fork Flutter do Cashew) a ser o app do Meu Banco no Android e no desktop (build web servido pelo Worker em `/app/`). O app deve ter:
- sync bidirecional com `/api/sync` e fila offline;
- pareamento por QR;
- Atualizar e Pluggy Connect;
- notificações em segundo plano sem Firebase e widget;
- o visual "Editorial tinta".

**Architecture:**
- **Worker:** continua sendo a fonte da verdade (D1) e ganha categoria efetiva no core, ciclo no pull, alertas novos e a rota de aparelho `GET /api/notificacoes`.
- **App:** guarda um espelho dos `registros` em tabelas SQL próprias dentro do SQLite do Cashew. A cada rodada:
  1. projeta os objetos do Cashew (categorias, orçamentos, metas, dívidas, lançamentos, assinaturas e regras) em `dados`;
  2. detecta as diferenças contra o espelho e as enfileira;
  3. faz push e depois pull, e aplica no Drift o que vence pelo last-write-wins.
- **Núcleo testável:** o núcleo (LWW, detecção, mapeamento e categoria efetiva) é Dart puro, testado com `flutter test`.
- **Desktop:** é o mesmo app em `flutter build web`, com layout próprio a partir de 1100px.

**Tech Stack:**
- **Worker:** Cloudflare Workers, D1, JS ESM, `packages/core` em TypeScript apagável, `node --test` (Node 22), wrangler 4, pnpm.
- **App:** Flutter 3.24.5, Drift (nativo e web com sql.js), http, flutter_secure_storage, app_links, flutter_local_notifications 17, home_widget 0.6, e os pacotes novos workmanager 0.5.2, mobile_scanner ^5.2.3 e flutter_pluggy_connect 3.0.1.
- **Prints:** Playwright.

**Spec:**
- original: `/home/renan/dev/meu-banco/docs/superpowers/specs/2026-11-09-app-completo-design.md` (seções 2, 4 a 9 e 12);
- addendum (vale onde diverge): `/home/renan/dev/meu-cashew/.worktrees/fase23/docs/superpowers/specs/2026-11-09-meu-cashew-fases-2-3.md`.

**Worktrees:**
- Worker: `/home/renan/dev/meu-banco/.worktrees/fase23` (branch `feat/fase2-3-worker`). Abaixo, **[W]**.
- App: `/home/renan/dev/meu-cashew/.worktrees/fase23` (branch `feat/fase2-3-cashew`), código em `budget/`. Abaixo, **[C]**.

**Ambiente do app (todo comando Flutter):**
```bash
export PATH=~/dev/flutter/bin:$PATH JAVA_HOME=~/dev/jdk17 ANDROID_HOME=~/Android/Sdk
cd /home/renan/dev/meu-cashew/.worktrees/fase23/budget
```

## Global Constraints

- **Idioma:** UI, mensagens, comentários e commits em pt-BR, com acentos e UTF-8. O locale padrão do app passa a ser `pt`.
- **Tokens:** exatos da seção 8 do spec original. Nenhuma cor fora da paleta. O vermelho (`warn`) só aparece em alerta; um único azul (`acc`) é o acento.
  - claro: bg `#F7F6F3`, surf `#FBFBFA`, tx `#17181C`, mu `#77767A`, line `rgba(20,20,30,.08)`, acc `#2340D8`, warn `#B42318`, warnbg `#FDEBEC`, warntx `#9F2F2D`, pos `#2F6B3A`, chip `#E8ECFB`;
  - escuro: bg `#0F1114`, surf `#15181C`, tx `#ECEDEF`, mu `#8D9097`, line `rgba(255,255,255,.08)`, acc `#8EA4FF`, warn `#F0726B`, warnbg `rgba(240,114,107,.12)`, warntx `#F59A94`, pos `#7FCB92`, chip `rgba(142,164,255,.12)`.
- **Versão:** `vX.Y.Z · dd/mm/aaaa HH:mm` (America/Sao_Paulo), visível em todas as telas, dentro de `IgnorePointer` (nunca captura clique).
- **Firebase:** nada de Firebase em tempo de execução (nem `initializeApp`, nem script do gstatic). Notificação no Android só por polling e notificação local.
- **Secrets:** nunca no código, em teste, em log ou em commit. Token de aparelho só em `flutter_secure_storage`, nunca em `appStateSettings` (que vai para os backups do Cashew). Keystore, `key.properties` e `.dev.vars` fora do git.
- **Produção:** sem comandos remotos de produção (`wrangler deploy`, `pnpm push`, `--remote`, `git push`, criação de tag). Quando um passo precisa de produção, o plano escreve o comando para o **usuário** rodar.
- **HTTP:** o app só fala https com token. A exceção é a web, que usa a mesma origem por cookie, sem token.
- **Worker:** POST, PUT e DELETE com cookie conferem `mesmaOrigem` (as rotas de aparelho já fazem isso).
- **Commits:** em português, detalhados, terminando com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Antes do commit de cada tarefa, rode a skill `qualidade-antes-do-pr`; antes do último commit de cada fase, `verificacao-manter`.
- **Testes:** os do Worker são `node --test`. `pnpm test` na raiz roda core e worker.

---

## Tarefa 1 [W]: categoria efetiva no core, `closing_date` e ciclo no pull

**Arquivos**
- Criar:
  - `packages/core/src/categorias.ts`
  - `packages/core/test/categorias.test.ts`
  - `packages/core/test/categoria-casos.json`
  - `apps/worker/scripts/migrar-fase2.sql`
- Modificar:
  - `packages/core/src/index.ts`
  - `apps/worker/schema.sql`
  - `apps/worker/src/mapa.js` (`mapearConta`)
  - `apps/worker/src/ciclo.js`
  - `apps/worker/src/sync.js` (`puxar`)
  - `apps/worker/src/index.js` (rota `GET /api/sync`)
  - `apps/worker/mock/api-mock.mjs` (`balanceCloseDate`)
  - `apps/worker/test/sync.test.mjs`, `apps/worker/test/mapa.test.mjs`, `apps/worker/test/ciclo.test.mjs`

**Interfaces**
- **Produz (core):**
```ts
export interface TxCategoria { id: string; account_id: string; description: string | null; category: string | null }
export interface RegraCtx { id: string; padrao: string; categoria_id: string; conta_id?: string | null; prioridade?: number | null }
export interface ContextoCategoria {
  ajustes: ReadonlyMap<string, { categoria_id?: string | null; category?: string | null }>;
  regras: readonly RegraCtx[];
  pluggy: ReadonlyMap<string, string>;      // categoria do Pluggy -> id da categoria
  porNome: ReadonlyMap<string, string>;     // "despesa:farmácia" -> id (nome em minúsculas)
}
export type Efetiva = { fonte: "ajuste" | "regra" | "pluggy" | "nome" | "banco"; categoria_id: string | null; category: string | null };
export function padraoCasa(padrao: string, texto: string): boolean;
export function ordenarRegras<T extends RegraCtx>(regras: readonly T[]): T[];
export function categoriaEfetiva(t: TxCategoria, ctx: ContextoCategoria, traduzir: (c: string | null) => string, receita: boolean): Efetiva;
export function contextoDeRegistros(regs: Iterable<{ tabela: string; id: string; dados: Record<string, unknown> | null; deleted_at: string | null }>): ContextoCategoria;
```
- **Produz (Worker):**
  - `gastoPorDia(transacoes, contas, inicio, fim): {data: string, valor: number}[]` em `ciclo.js`;
  - `puxar(db, desde, agoraIso, extras = {})`, que mescla `extras` (`ciclo`) na resposta e acrescenta `sincronizado_em`.
- **Consome:** `valorGasto` e `traduzir` de `public/regras.js`; `resumoCiclo` de `ciclo.js`.

**Passos**
- [ ] **Escrever `categorias.ts`:**
```ts
const escapar = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
export function padraoCasa(padrao: string, texto: string): boolean {
  const p = padrao.trim();
  if (!p) return false;
  return new RegExp("^" + p.split("*").map(escapar).join(".*") + "$", "i").test((texto || "").trim());
}
export function ordenarRegras<T extends RegraCtx>(regras: readonly T[]): T[] {
  return [...regras].sort((a, b) => (b.prioridade ?? 0) - (a.prioridade ?? 0) || b.padrao.length - a.padrao.length || (a.id < b.id ? -1 : 1));
}
export function categoriaEfetiva(t: TxCategoria, ctx: ContextoCategoria, traduzir: (c: string | null) => string, receita: boolean): Efetiva {
  const a = ctx.ajustes.get(t.id);
  if (a?.categoria_id) return { fonte: "ajuste", categoria_id: a.categoria_id, category: null };
  if (a?.category) return { fonte: "ajuste", categoria_id: ctx.pluggy.get(a.category) ?? porNome(ctx, traduzir(a.category), receita), category: a.category };
  const r = ordenarRegras(ctx.regras).find((r) => (!r.conta_id || r.conta_id === t.account_id) && padraoCasa(r.padrao, t.description ?? ""));
  if (r) return { fonte: "regra", categoria_id: r.categoria_id, category: null };
  const m = t.category ? ctx.pluggy.get(t.category) : undefined;
  if (m) return { fonte: "pluggy", categoria_id: m, category: null };
  const n = porNome(ctx, traduzir(t.category), receita);
  return n ? { fonte: "nome", categoria_id: n, category: null } : { fonte: "banco", categoria_id: null, category: t.category };
}
const porNome = (ctx: ContextoCategoria, nome: string, receita: boolean) => ctx.porNome.get(`${receita ? "receita" : "despesa"}:${nome.toLowerCase()}`) ?? null;
```
  `contextoDeRegistros` monta os mapas a partir dos registros não excluídos (`deleted_at == null`):
  - `ajustes`: id → dados;
  - `regras`;
  - `pluggy`: cada item de `categorias.dados.pluggy` → id;
  - `porNome`: `tipo:nome` em minúsculas.
- [ ] **Escrever `categoria-casos.json`:** 12 casos no formato `{nome, tx, receita, registros, esperado: {fonte, categoria_id}}`. Cobrir:
  - ajuste com `categoria_id`;
  - ajuste só com `category`;
  - regra que vence o pluggy;
  - duas regras (prioridade e depois tamanho);
  - regra com `conta_id` de outra conta;
  - curinga no meio (`DRO*SIL`);
  - maiúsculas e minúsculas;
  - mapeamento `pluggy`;
  - por nome traduzido (`Pharmacy` → "farmácia");
  - receita versus despesa no nome;
  - registro excluído ignorado;
  - nada casa (`banco`).
  
  Esse arquivo é copiado sem mudança para o app na Tarefa 4.
- [ ] **Escrever `categorias.test.ts`:** lê o JSON e, para cada caso, roda `categoriaEfetiva(caso.tx, contextoDeRegistros(caso.registros), traduzirTeste, caso.receita)`. `traduzirTeste` é um mapa mínimo `{Pharmacy: "Farmácia", Groceries: "Supermercado"}`.
- [ ] **Adicionar `closing_date`:**
  - `schema.sql`: `closing_date TEXT` em `accounts`, depois de `due_date`;
  - `scripts/migrar-fase2.sql`: `ALTER TABLE accounts ADD COLUMN closing_date TEXT;`;
  - `mapearConta`: `closing_date: dia(c.creditData?.balanceCloseDate)`;
  - mock: `balanceCloseDate: dia(3)` no cartão.
- [ ] **Escrever `gastoPorDia`:** um item por dia de `inicio` a `fim`, inclusive. `valor` = soma de `valorGasto(t, cartao)` + `valorParcela(t, cartao)` das transações do dia, arredondada em centavos. Dias sem gasto têm valor 0.
- [ ] **Mudar `puxar`:** acrescentar `db.prepare("SELECT MAX(finished_at) AS f FROM sync_log WHERE ok = 1")` ao batch; a resposta ganha `sincronizado_em` e `...extras`. Na query de contas, incluir `closing_date`.
- [ ] **Mudar a rota `GET /api/sync` em `index.js`:**
```js
const b = await baseCiclo(env);
return json(await puxar(env.DB, desde, ts, { ciclo: { ...b.resumo, salario: b.config.salario ?? null, por_dia: gastoPorDia(b.transacoes, b.contas, b.resumo.inicio, b.resumo.fim) } }));
```
- [ ] **Testes:**
  - `sync.test.mjs`: o pull tem `ciclo.inicio`, `ciclo.por_dia` (comprimento = dias do ciclo) e `sincronizado_em`;
  - `mapa.test.mjs`: `closing_date` vem do `balanceCloseDate`;
  - `ciclo.test.mjs`: `gastoPorDia` soma por dia e preenche os zeros.

**Comandos**
```bash
cd /home/renan/dev/meu-banco/.worktrees/fase23 && pnpm test
```
**Esperado:** todos passam (core, com os 12 casos novos, e worker).

**Produção (o usuário roda depois do merge, antes do deploy):**
```bash
pnpm --filter @meu-banco/worker exec wrangler d1 execute meu-banco --remote --file=scripts/migrar-fase2.sql
```

**Commit:** `Core: categoria efetiva compartilhada; Worker: fechamento do cartão e ciclo no /api/sync`

---

## Tarefa 2 [W]: alertas novos, `item_id` nos avisos e `GET /api/notificacoes` para aparelhos

**Arquivos**
- Modificar:
  - `apps/worker/src/alertas.js`
  - `apps/worker/src/mapa.js` (`avisoItem`)
  - `apps/worker/src/index.js` (`baseCiclo`, `avaliarAlertas`, `ROTAS_APARELHO`, `rotaAparelho`)
  - `apps/worker/test/alertas.test.mjs`
  - `apps/worker/test/sync.test.mjs`
  - `apps/worker/test/mapa.test.mjs`
  - `README.md` (seção de rotas)
- Criar: `apps/worker/test/notificacoes.test.mjs`

**Interfaces**
- **Produz (`alertas.js`, puras; cada uma devolve `{chave, titulo, corpo}[]`):**
```js
export function alertasOrcamentos({ orcamentos, ctx, transacoes, contas, resumo, hoje })
export function alertasFechamento({ contas, hoje })
export function alertasReceita({ transacoes, contas, hoje })
export function alertasAssinaturas({ assinaturas, hoje })
```
- **`gerarAlertas`:** passa a receber `registros` (lista de linhas não excluídas) e concatena as quatro listas acima.
- **Rota:** `GET /api/notificacoes?desde=<ISO>` (Bearer ou cookie). Responde:
```json
{"cursor":"<ISO>","notificacoes":[{"chave":"","titulo":"","corpo":"","criada":""}],
 "resumo":{"disponivel":0,"consumido":0,"limite":null,"percentual":null,"inicio":"","fim":"","sincronizado_em":null}}
```
- **Avisos:** `avisoItem` passa a incluir `item_id: item.id`.

**Passos**
- [ ] **Escrever `alertasOrcamentos`:**
  - período: `ciclo` → `resumo.inicio..resumo.fim`; `mensal` → primeiro dia do mês de `hoje` até o último dia;
  - gasto = soma de `valorGasto(t, cartao)` das transações do período em que `categoriaEfetiva(...).categoria_id` está em `categoria_ids` (lista vazia = todas);
  - aos 80%: chave `orc80:<id>:<inicio>`, título `"80% do orçamento <nome>"`;
  - acima de 100%: chave `orc100:<id>:<inicio>`, título `"Orçamento <nome> estourado"`;
  - corpo com `brl` e as datas `dm()` que já existem.
- [ ] **Escrever `alertasFechamento`:**
  - para cada `type === "CREDIT"` com `closing_date` e `0 <= dias(hoje, closing_date) <= 3`;
  - chave `fechamento:<id>:<closing_date>`;
  - título `"Fatura do <name> fecha em N dias"` ("fecha hoje" quando N = 0);
  - corpo `"Fatura atual: R$ … · vence dd/mm"`.
- [ ] **Escrever `alertasReceita`:**
  - conta BANK, `amount > 0`, `!scheduled`, `!naoEhGasto(t)` e `date >= somarDias(hoje, -2)`;
  - chave `receita:<id>`;
  - título `"Entrou dinheiro"`, corpo `"R$ … de <description> em <conta>"`.
- [ ] **Escrever `alertasAssinaturas`:**
  - status `confirmada`;
  - próxima data = dia `dia` (limitado ao fim do mês) do mês corrente, ou do seguinte se já passou;
  - quando `dias(hoje, proxima)` for 0 ou 1: chave `assinatura:<id>:<proxima>`, título `"<nome> cobra amanhã"` ou `"<nome> cobra hoje"`, corpo `"R$ <valor>"`.
- [ ] **Mudar `baseCiclo`:**
  - contas passam a ler `id, type, name, balance, closing_date`;
  - ler `SELECT tabela, id, dados FROM registros WHERE deleted_at IS NULL AND tabela IN ('categorias','regras','orcamentos','ajustes','assinaturas')`, com o JSON já decodificado;
  - montar `ctx = contextoDeRegistros(...)` e devolver `registros` e `ctx`.
  
  `avaliarAlertas` repassa tudo para `gerarAlertas`.
- [ ] **Rota de aparelho:** `ROTAS_APARELHO` ganha `"/api/notificacoes"`. Em `rotaAparelho`:
```js
if (rota === "GET /api/notificacoes") {
  const desde = normalizarDesde(url.searchParams.get("desde"));
  if (desde === undefined) return json({ erro: "Parâmetro desde inválido (use data ISO)" }, 400);
  return json(await notificacoesAparelho(env, desde, ts));
}
```
```js
async function notificacoesAparelho(env, desde, ts) {
  const b = await baseCiclo(env);
  const sinc = await env.DB.prepare("SELECT MAX(finished_at) AS f FROM sync_log WHERE ok = 1").first("f");
  const disponivel = Math.round(b.contas.filter((c) => c.type === "BANK").reduce((s, c) => s + (c.balance || 0), 0) * 100) / 100;
  const { consumido, limite, percentual, inicio, fim } = b.resumo;
  const resumo = { disponivel, consumido, limite, percentual, inicio, fim, sincronizado_em: sinc ?? null };
  if (desde === null) return { cursor: ts, notificacoes: [], resumo };           // 1º uso: não despeja o histórico
  if (emSilencio(new Date(ts))) return { cursor: desde, notificacoes: [], resumo }; // 22h–7h: segura
  const piso = desde > validadeAlerta() ? desde : validadeAlerta();
  const { results } = await env.DB.prepare("SELECT chave, titulo, corpo, criada FROM notificacoes WHERE criada > ?1 ORDER BY criada LIMIT 20").bind(piso).all();
  return { cursor: results.at(-1)?.criada ?? desde, notificacoes: results, resumo };
}
```
  A rota não mexe em `enviada_em` nem em `entregue_em`, porque eles são do Web Push.
- [ ] **Testes:**
  - `alertas.test.mjs`, um teste por função nova, incluindo:
    - orçamento `ciclo` versus `mensal`;
    - chave não repete;
    - fechamento com 4 dias não avisa e com 3 dias avisa;
    - assinatura com dia 31 em novembro cai em 30/11;
  - `notificacoes.test.mjs`:
    - sem token: 401;
    - `desde` ausente: lista vazia e cursor;
    - com `desde` antigo: traz até 20 em ordem e o cursor anda;
    - segunda chamada com o cursor: vazio;
    - em silêncio (`Date` fixada às 23h BRT com `mock.timers`): vazio e o cursor não anda;
    - `resumo.disponivel` = soma das BANK;
  - `mapa.test.mjs`: `item_id` no aviso.

**Comandos**
```bash
cd /home/renan/dev/meu-banco/.worktrees/fase23 && pnpm test
```
**Esperado:** tudo verde.

**Verificação local:** com `pnpm mock` (porta 8788) e `pnpm dev` (porta 8787), seguindo o README, criar um token no painel local e rodar `curl -s -H "Authorization: Bearer $TOKEN" "http://localhost:8787/api/notificacoes?desde=2026-01-01T00:00:00Z"`. Deve devolver JSON com `resumo`.

**Commit:** `Worker: alertas de orçamento, fechamento, receita e assinatura; rota de notificações para aparelhos`

---

## Tarefa 3 [C]: núcleo do sync em Dart puro (registro, LWW, detecção de mudanças locais)

**Arquivos**
- Criar:
  - `budget/lib/struct/mbSync/registro.dart`
  - `budget/lib/struct/mbSync/detectar.dart`
  - `budget/test/mb_sync_nucleo_test.dart`

**Interfaces (produz)**
```dart
const List<String> mbTabelas = ['categorias','regras','orcamentos','metas','dividas','assinaturas','ajustes','lancamentos'];
const String mbNuncaEditado = '2000-01-01T00:00:00.000Z';
String isoMs(DateTime d);                       // UTC, milissegundos, igual ao toISOString do JS
String normalizarIso(String s);
String jsonCanonico(Object? v);                 // chaves ordenadas, recursivo
class Registro { final String tabela, id; final Map<String, dynamic>? dados; final String updatedAt; final String? deletedAt; String get chave; factory Registro.fromJson(Map<String, dynamic> j); Map<String, dynamic> toJson(); }
bool vence(Registro novo, String? atualUpdatedAt);
class Espelho { final Registro registro; final Map<String, dynamic>? projecao; final bool pendente; final String? motivo; }
class Projetado { final String tabela, id; final Map<String, dynamic> dados; final String? editadoEm; String get chave; }
class MudancaLocal { final Registro registro; final Map<String, dynamic>? projecao; }
List<MudancaLocal> detectarMudancasLocais({required Map<String, Espelho> espelho, required Map<String, Projetado> atuais, required String agora, Set<String> semExclusaoLocal = const {'ajustes'}});
Map<String, dynamic> completarNovo(String tabela, Map<String, dynamic> dados);
List<Registro> remotosVencedores(Map<String, Espelho> espelho, Iterable<Registro> remotos);
```

**Passos**
- [ ] **Escrever `registro.dart`:**
```dart
String isoMs(DateTime d) =>
    DateTime.fromMillisecondsSinceEpoch(d.millisecondsSinceEpoch, isUtc: true).toIso8601String();
String normalizarIso(String s) => isoMs(DateTime.parse(s));

Object? _ordenar(Object? v) => v is Map
    ? Map.fromEntries((v.keys.map((k) => k.toString()).toList()..sort()).map((k) => MapEntry(k, _ordenar(v[k]))))
    : v is List ? v.map(_ordenar).toList() : v;
String jsonCanonico(Object? v) => jsonEncode(_ordenar(v));

bool vence(Registro novo, String? atual) => atual == null || novo.updatedAt.compareTo(atual) > 0;

List<Registro> remotosVencedores(Map<String, Espelho> espelho, Iterable<Registro> remotos) =>
    remotos.where((r) => vence(r, espelho[r.chave]?.registro.updatedAt)).toList();
```
  `Registro.fromJson` normaliza `updated_at` e `deleted_at` com `normalizarIso`. `toJson` manda `dados: null` quando `deletedAt != null`.
- [ ] **Escrever `detectar.dart`:**
```dart
const Map<String, Map<String, dynamic>> _padroes = {
  'orcamentos': {'periodo': 'mensal', 'categoria_ids': <String>[]},
  'dividas': {'tipo': 'emprestimo'},
  'assinaturas': {'status': 'confirmada'},
};
Map<String, dynamic> completarNovo(String tabela, Map<String, dynamic> d) {
  final r = {...?_padroes[tabela], ...d};
  if (tabela == 'assinaturas' && r['padrao'] == null) r['padrao'] = '${(d['nome'] as String).toUpperCase()}*';
  return r;
}

List<MudancaLocal> detectarMudancasLocais({required Map<String, Espelho> espelho, required Map<String, Projetado> atuais,
    required String agora, Set<String> semExclusaoLocal = const {'ajustes'}}) {
  final out = <MudancaLocal>[];
  for (final p in atuais.values) {
    final e = espelho[p.chave];
    if (e != null && e.registro.deletedAt == null && e.projecao != null &&
        jsonCanonico(e.projecao) == jsonCanonico(p.dados)) continue;          // nada mudou
    if (e != null && e.registro.deletedAt != null &&
        !(p.editadoEm != null && p.editadoEm!.compareTo(e.registro.deletedAt!) > 0)) continue; // apagado em outro aparelho
    final base = e?.registro.deletedAt == null ? (e?.registro.dados ?? const {}) : const <String, dynamic>{};
    final dados = completarNovo(p.tabela, {...base, ...p.dados})..removeWhere((_, v) => v == null);
    var quando = p.editadoEm ?? mbNuncaEditado;
    if (e != null && quando.compareTo(e.registro.updatedAt) <= 0) quando = agora; // edição real precisa vencer o espelho
    out.add(MudancaLocal(Registro(p.tabela, p.id, dados, quando, null),
        semExclusaoLocal.contains(p.tabela) ? null : p.dados));
  }
  for (final e in espelho.values) {
    final r = e.registro;
    if (e.projecao == null || r.deletedAt != null || semExclusaoLocal.contains(r.tabela) || atuais.containsKey(r.chave)) continue;
    out.add(MudancaLocal(Registro(r.tabela, r.id, null, agora, agora), null));   // excluído aqui
  }
  return out;
}
```
- [ ] **Escrever os testes** (`mb_sync_nucleo_test.dart`, Dart puro, sem Drift):
  1. `isoMs` com microssegundos dá exatamente `"...:00.123Z"`.
  2. `jsonCanonico` independe da ordem das chaves.
  3. `vence`: maior vence; igual não; null vence.
  4. Objeto novo sem espelho: vai com `editadoEm`. Sem `editadoEm`: vai com `mbNuncaEditado`.
  5. Projeção igual ao espelho: nada.
  6. Projeção diferente: mescla preserva a chave extra `pluggy` do espelho e remove o campo que virou null.
  7. `editadoEm` mais antigo que o espelho vira `agora`.
  8. Espelho com projeção e sem objeto local: tombstone com `dados` null.
  9. `ajustes` sem objeto: nunca tombstone; a mudança volta com `projecao` null.
  10. Espelho apagado e local editado antes: ignorado. Editado depois: reenviado.
  11. Orçamento novo recebe `periodo: 'mensal'`.
  12. Assinatura nova recebe `padrao` `NOME*`.
  13. `remotosVencedores` com pendente local mais novo: o remoto mais velho perde.

**Comandos**
```bash
flutter test test/mb_sync_nucleo_test.dart
```
**Esperado:** 13 testes passam.

**Commit:** `Sync Meu Banco: núcleo puro com last-write-wins e detecção de mudanças locais`

---

## Tarefa 4 [C]: mapeamento das entidades e categoria efetiva (Dart puro)

**Arquivos**
- Criar:
  - `budget/lib/struct/mbSync/mapeamento.dart`
  - `budget/lib/struct/mbSync/categoriaEfetiva.dart`
  - `budget/test/mb_mapeamento_test.dart`
  - `budget/test/fixtures/categoria-casos.json` (cópia exata de `packages/core/test/categoria-casos.json` da Tarefa 1)
- Modificar:
  - `budget/lib/struct/meuBancoMapping.dart`: `mbMapearResposta` vira `mbMapearPull`, que lê o formato do `/api/sync` e respeita ajustes (`gasto`) e categoria efetiva;
  - `budget/test/meu_banco_mapping_test.dart`: adaptar ao formato novo.

**Interfaces (produz)**
```dart
const String prefixoCashew = 'cashew:';
String idDoPk(String pk) => prefixoCashew + pk;
String pkDoId(String id) => id.startsWith(prefixoCashew) ? id.substring(prefixoCashew.length) : id;
String dataLocal(DateTime d);                    // yyyy-mm-dd do calendário local
DateTime dataDeTexto(String yyyymmdd);           // meio-dia local

class CatLocal { String pk, nome; bool receita; String? cor, icone, paiPk; int ordem; DateTime? modificadoEm; }
class OrcLocal { String pk, nome; double valor; List<String>? categoriaPks; DateTime? modificadoEm; }
class ObjLocal { String pk, nome; bool divida; bool receita; double valor; DateTime? prazo; DateTime? modificadoEm; }
class LancLocal { String pk, nome, nota; double valor; String categoriaPk, carteiraNome; DateTime data; String? metaPk, dividaPk; DateTime? modificadoEm; }
class AssinLocal { String pk, nome; double valor; int dia; String categoriaPk; DateTime? modificadoEm; }
class RegraLocal { String pk, titulo, categoriaPk; bool exato; DateTime? modificadoEm; }

Map<String, dynamic> projetarCategoria(CatLocal c);
Map<String, dynamic> projetarOrcamento(OrcLocal o);
Map<String, dynamic> projetarObjetivo(ObjLocal o);   // meta ou dívida, conforme o.divida
Map<String, dynamic> projetarLancamento(LancLocal l);
Map<String, dynamic> projetarAssinatura(AssinLocal a);
Map<String, dynamic>? projetarRegra(RegraLocal r, Map<String, dynamic>? base);
CatLocal categoriaDeDados(String id, Map<String, dynamic> d);
OrcLocal orcamentoDeDados(String id, Map<String, dynamic> d);
ObjLocal objetivoDeDados(String id, Map<String, dynamic> d, {required bool divida});
LancLocal lancamentoDeDados(String id, Map<String, dynamic> d, {required String categoriaPadrao});
AssinLocal? assinaturaDeDados(String id, Map<String, dynamic> d, {required String categoriaPadrao}); // null se 'ignorada'
RegraLocal? regraDeDados(String id, Map<String, dynamic> d);   // null se o padrão não cabe em AssociatedTitle
Projetado? projetarAjuste({required String txPk, required String? categoriaPkAtual, required String? categoriaPkAplicada, required bool existeLocal, required String nomeCategoria, required String? editadoEm});

// categoriaEfetiva.dart: porte literal de packages/core/src/categorias.ts
bool mbPadraoCasa(String padrao, String texto);
class MbEfetiva { final String fonte; final String? categoriaId; final String? category; }
class MbContextoCategoria { /* ajustes, regras, pluggy, porNome */ factory MbContextoCategoria.deRegistros(Iterable<Registro> regs); }
MbEfetiva mbCategoriaEfetiva({required String txId, required String contaId, required String? descricao, required String? categoriaPluggy, required bool receita, required MbContextoCategoria ctx});
```

**Passos**
- [ ] **Escrever as projeções.** As chaves batem com `TABELAS` do core:
  - categoria: `{'nome', 'tipo': receita ? 'receita' : 'despesa', 'cor', 'icone', 'pai_id': paiPk == null ? null : idDoPk(paiPk), 'ordem'}`;
  - orçamento: `{'nome', 'valor', 'categoria_ids': (categoriaPks ?? []).map(idDoPk).toList()..sort()}`. Sem `periodo`, que é preservado do espelho;
  - meta: `{'nome', 'valor_alvo': valor, 'prazo': prazo == null ? null : dataLocal(prazo)}`;
  - dívida: `{'tipo': 'emprestimo', 'nome', 'sentido': receita ? 'me_devem' : 'devo', 'valor_total': valor}`;
  - lançamento: `{'data': dataLocal(data), 'descricao': nome.trim().isEmpty ? 'Sem descrição' : nome.trim(), 'valor', 'categoria_id': idDoPk(categoriaPk), 'carteira': carteiraNome, 'nota': nota.trim().isEmpty ? null : nota.trim(), 'meta_id': metaPk == null ? null : idDoPk(metaPk), 'divida_id': ...}`. Textos cortados em 200 caracteres;
  - assinatura: `{'nome', 'valor': valor.abs(), 'dia', 'categoria_id': idDoPk(categoriaPk)}`;
  - regra: `padrao = exato ? titulo : '*$titulo*'`. Se `base?['padrao']` sem os `*` das pontas for igual a `titulo` e a exatidão bater, usa o `base['padrao']` (preserva `DROGASIL*`). Retorno: `{'padrao', 'categoria_id': idDoPk(categoriaPk)}`.
- [ ] **Escrever as inversas.** Cada `xDeDados(projetarX(l))` reprojeta igual: é o teste de ida e volta. `regraDeDados` aceita só `^\*?[^*]+\*?$`.
- [ ] **Escrever `projetarAjuste`.** O id do ajuste é `txPk` sem `mb:`.
  - `existeLocal == false` e `categoriaPkAplicada != null`: `{'gasto': 0}`;
  - `categoriaPkAtual != categoriaPkAplicada`: `{'categoria_id': idDoPk(categoriaPkAtual), 'category': nomeCategoria}`;
  - senão: null.
- [ ] **Portar `categoriaEfetiva`** em `categoriaEfetiva.dart`, linha a linha com o TS. Usar `RegExp.escape` por pedaço.
- [ ] **Escrever `mbMapearPull`** em `meuBancoMapping.dart`:
```dart
MbResultado mbMapearPull(Map<String, dynamic> json, MbContextoCategoria ctx, {required String Function(String? catId, String nomeTraduzido, bool receita) pkCategoria})
```
  Lê `contas` (formato D1: `id, type, name, balance, credit_limit, available_limit, due_date, closing_date, item_id`), `transacoes` (formato D1) e `pendentes`. Por transação:
  - pula `scheduled == 1`;
  - ajuste com `gasto == 0`: pula;
  - ajuste com `gasto == 1`: importa mesmo que `mbNaoEhGasto`;
  - senão, a regra atual (`mbNaoEhGasto`);
  - sinal: o mesmo de hoje (cartão inverte);
  - `categoriaPk = pkCategoria(efetiva.categoriaId, mbTraduzirCategoria(efetiva.category ?? categoriaPluggy), receita)`.
  
  `MbResultado` mantém os campos atuais e ganha `contasBrutas`, `faturas`, `ciclo`, `avisos`, `config` e `sincronizadoEm`, que são repassados como `Map`.
- [ ] **Testes** (`mb_mapeamento_test.dart`):
  - ida e volta de cada entidade (6 testes);
  - regra `DROGASIL*` preservada;
  - regra `DRO*SIL` → `regraDeDados` null;
  - `projetarAjuste` nos 3 casos;
  - assinatura ignorada → null;
  - todos os casos de `test/fixtures/categoria-casos.json` (mesmo resultado que o core);
  - `mbMapearPull` com `gasto: 0` e `gasto: 1` e com regra mudando a categoria;
  - `meu_banco_mapping_test.dart` adaptado ao formato D1 (cartão inverte o sinal, pendente, futura ignorada).

**Comandos**
```bash
flutter test test/mb_mapeamento_test.dart test/meu_banco_mapping_test.dart test/mb_sync_nucleo_test.dart
```
**Esperado:** todos passam.

**Commit:** `Sync Meu Banco: mapeamento Cashew ↔ registros e categoria efetiva igual à do core`

---

## Tarefa 5 [C]: sync bidirecional ligado ao Drift (espelho, fila, push e pull)

**Arquivos**
- Criar:
  - `budget/lib/struct/mbSync/armazem.dart`: tabelas SQL próprias via `customStatement` e `customSelect`;
  - `budget/lib/struct/mbSync/projetarLocal.dart`: lê o Drift e monta `Map<String, Projetado>`;
  - `budget/lib/struct/mbSync/aplicarLocal.dart`: grava os registros remotos no Drift;
  - `budget/lib/struct/mbSync/cliente.dart`: HTTP com Bearer, ou cookie na web.
- Modificar:
  - `budget/lib/struct/meuBancoSync.dart`: `sincronizarMeuBanco()` passa a orquestrar o fluxo novo, com o mesmo nome (os gatilhos de `navigationFramework.dart:305` e `pullDownToRefreshSync.dart:135` não mudam);
  - `budget/lib/pages/meuBancoPage.dart`: mostra a fila (`N alterações aguardando envio`), os rejeitados com motivo e "Sincronizado há N min".

**Interfaces**
```dart
// armazem.dart
Future<void> mbCriarTabelas();   // CREATE TABLE IF NOT EXISTS:
//  mb_registros(tabela TEXT, id TEXT, dados TEXT, updated_at TEXT NOT NULL, deleted_at TEXT, projecao TEXT, pendente INTEGER NOT NULL DEFAULT 0, motivo TEXT, PRIMARY KEY(tabela,id))
//  mb_estado(chave TEXT PRIMARY KEY, valor TEXT NOT NULL)      -- cursor, contas, faturas, ciclo, avisos, config, sincronizado_em
//  mb_aplicado(tx_pk TEXT PRIMARY KEY, categoria_pk TEXT NOT NULL)
Future<Map<String, Espelho>> mbLerEspelho();
Future<void> mbGravarEspelho(Iterable<Espelho> itens);
Future<List<Espelho>> mbPendentes({int limite = 500});
Future<void> mbMarcarEnviados(List<Espelho> lote, Map<int, String> rejeitados);
Future<String?> mbLerEstado(String chave);
Future<void> mbGravarEstado(Map<String, String> valores);
Future<Map<String, String>> mbLerAplicado();
Future<void> mbGravarAplicado(Map<String, String> novos, Iterable<String> removidos);

// cliente.dart
class MbCliente {
  MbCliente({required this.base, this.token});          // web: base = Uri.base.origin, token = null
  Future<Map<String, dynamic>> puxar(String? desde);     // GET /api/sync
  Future<({int aceitos, List<({int indice, String motivo})> rejeitados})> enviar(List<Registro> lote); // POST /api/sync
  Future<Map<String, dynamic>> atualizar();             // POST /api/sync/atualizar (429 -> MbErroLimite(mensagem, liberadoEm))
  Future<String> connectToken({String? itemId});
  Future<void> registrarItem(String itemId);
  Future<Map<String, dynamic>> notificacoes(String? desde);
}
class MbErroHttp implements Exception { final int status; final String mensagem; }
class MbErroLimite extends MbErroHttp { final DateTime? liberadoEm; }
Future<MbCliente?> mbClienteConfigurado();   // null quando não pareado (Android sem token)
```

**Passos**
- [ ] **`armazem.dart`:** usar `database.customStatement` e `database.customSelect(..., variables: [Variable.withString(...)])`. `mbCriarTabelas()` roda no início de cada `sincronizarMeuBanco`, porque é idempotente. Motivo de não usar tabela Drift: ver D1 do addendum (sem codegen, sem schema 47).
- [ ] **`projetarLocal.dart`:** monta as projeções a partir do Drift.
  - categorias: `database.getAllCategories()`;
  - orçamentos não arquivados: `select(budgets)..where(archived = false)`;
  - objetivos: `select(objectives)`, separando por `type`;
  - lançamentos: transações com `!transactionPk.startsWith('mb:')`, `type` em (null, credit, debt);
  - assinaturas: `type == subscription`;
  - regras: `select(associatedTitles)`.
  
  O nome da carteira vem de `getAllWallets()`. `editadoEm = dtm == null || dtm.year < 2001 ? null : isoMs(dtm)`. O id é `idDoPk(pk)`. Ajustes: para cada transação `mb:` atual e para cada `tx_pk` de `mb_aplicado`, chamar `projetarAjuste` e acrescentar quando não for null.
- [ ] **`aplicarLocal.dart`:** grava o remoto direto pelo Drift, com `dateTimeModified = DateTime.parse(r.updatedAt).toLocal()`, sem passar por `createOrUpdate*` (assim não gera efeitos colaterais de orçamento compartilhado).
  - **Ordem:** categorias, regras, orçamentos, metas e dívidas, lançamentos, assinaturas.
  - **Categoria:** `into(categories).insertOnConflictUpdate(TransactionCategory(... methodAdded: null).toCompanion(true))`. `order` vem do remoto ou de `getAmountOfCategories()`.
  - **Orçamento:** `startDate` = início do mês atual, `endDate` = fim do mês, `periodLength: 1`, `reoccurrence: BudgetReoccurence.monthly`, `colour: null`, `order`, `walletFk: "0"`, `categoryFks` = `pkDoId` das ids, ou null se a lista for vazia.
  - **Lançamento:** `income = valor > 0`, `paid: true`, `walletFk` = carteira com o mesmo nome ou `"0"`, `objectiveFk` e `objectiveLoanFk` a partir de `meta_id` e `divida_id`. Se a categoria não existe localmente, usa a primeira categoria da mesma natureza.
  - **Assinatura confirmada:** `type: TransactionSpecialType.subscription`, `reoccurrence: monthly`, `periodLength: 1`, `paid: false`, `amount: -valor`, `dateCreated` = próxima data com o `dia`.
  - **Regra:** `into(associatedTitles).insertOnConflictUpdate(...)` com `isExactMatch`.
  - **Tombstone:**
    - categoria só é apagada se não tiver transações (`getAllTransactionsFromCategory` vazio); senão fica, com espelho apagado e `projecao` null (D3 do addendum);
    - demais entidades: `delete(...)..where(pk)`;
    - objetivos: antes, zerar `objectiveFk` e `objectiveLoanFk` das transações.
  - **Espelho:** depois de aplicar, grava `Espelho(registro: r, projecao: <projeção recalculada do objeto gravado, ou null se não há objeto>, pendente: false)`.
- [ ] **`sincronizarMeuBanco()`:**
  1. Abortar se já está sincronizando.
  2. `cliente = await mbClienteConfigurado()`; se null, retorna false.
  3. `mbCriarTabelas()`.
  4. Detecção: `detectarMudancasLocais(espelho, atuais, agora: isoMs(DateTime.now()))` → gravar o espelho com `pendente: true`.
  5. Push: loop em `mbPendentes()` (500 por vez) → `cliente.enviar` → `mbMarcarEnviados`. Em falha de rede, para o push e segue para o pull.
  6. Pull: `json = await cliente.puxar(cursor)`.
  7. `vencedores = remotosVencedores(espelho, registros)` → `aplicarLocal`.
  8. Contexto: `ctx = MbContextoCategoria.deRegistros(<espelho atualizado não excluído>)`; `r = mbMapearPull(json, ctx, pkCategoria: ...)`. `pkCategoria`: id conhecido com categoria local → `pkDoId(id)`; senão `mbPkCategoria(nome, receita)`, criando a categoria como hoje.
  9. Gravar carteiras, categorias e transações `mb:` como hoje, mas com `dateTimeModified` fixo `DateTime.utc(2000)` (não conta como edição). Atualizar `mb_aplicado[pk] = categoriaPk`. Remover pendentes que sumiram e tirar esses pks de `mb_aplicado`.
  10. `mbGravarEstado({'cursor': json['agora'], 'contas': jsonEncode(json['contas']), 'faturas': ..., 'ciclo': ..., 'avisos': ..., 'config': ..., 'sincronizado_em': json['sincronizado_em'] ?? ''})`.
  11. Atualizar o widget (Tarefa 10; aqui fica a chamada `mbAtualizarWidget()` como função vazia em `lib/struct/mbSync/widget.dart`).
  12. `meuBancoUltimaSync.value = DateTime.now()`.
  
  O cursor passa de `appStateSettings["meuBancoDesde"]` para `mb_estado`; ao ler, migrar o valor antigo uma vez e apagar a chave dos settings.
- [ ] **Web:** em `mbClienteConfigurado()`, `kIsWeb` → `MbCliente(base: Uri.base.origin)`, sem token. No http da web, o cookie vai automaticamente na mesma origem.
- [ ] **Testes:**
  - `budget/test/mb_sync_drift_test.dart` com `FinanceDatabase(NativeDatabase.memory())`. Exige `sqlite3` no host; se faltar, `sudo apt install libsqlite3-dev` (o usuário roda).
  - `database` global apontando para o banco em memória, e `MbCliente` falso (subclasse que sobrescreve `puxar` e `enviar`).
  - Cenários:
    1. categoria criada no Cashew vai no push com id `cashew:<pk>`;
    2. categoria remota mais nova é aplicada e a rodada seguinte não a reenvia;
    3. edição offline (push falha) continua pendente e sai na rodada seguinte;
    4. tombstone remoto apaga o orçamento local;
    5. mudar a categoria de uma transação `mb:` gera ajuste com `categoria_id` e, depois do pull, não gera tombstone;
    6. apagar uma transação `mb:` gera `gasto: 0` e ela não volta no pull seguinte.

**Comandos**
```bash
flutter test test/mb_sync_drift_test.dart test/mb_sync_nucleo_test.dart test/mb_mapeamento_test.dart
flutter build apk --debug
```
**Esperado:** testes verdes; APK gerado em `build/app/outputs/flutter-apk/app-debug.apk`.

**Verificação manual (emulador ou aparelho, Worker local via `adb reverse tcp:8787 tcp:8787`):** a URL precisa ser https, então para teste local permitir `http://localhost` só em `kDebugMode`.
1. Exportar o backup do Cashew (Configurações → Backup) antes do primeiro sync.
2. Sincronizar.
3. `curl` no `/api/sync`: os registros `cashew:*` aparecem.
4. Editar uma categoria no app e sincronizar: `updated_at` muda no D1.

**Commit:** `Sync Meu Banco bidirecional: espelho local, fila offline, push e pull com last-write-wins`

---

## Tarefa 6 [C]: pareamento por QR e deep link, e botão Atualizar

**Arquivos**
- Criar: `budget/lib/pages/meuBancoParear.dart` (tela do leitor) e `budget/test/mb_pareamento_test.dart`.
- Modificar:
  - `budget/pubspec.yaml`: `mobile_scanner: ^5.2.3`;
  - `budget/android/app/src/main/AndroidManifest.xml`: intent-filter `meubanco://parear` e permissão `CAMERA`;
  - `budget/lib/widgets/util/appLinks.dart`: tratar `meubanco` antes de `hasOnboarded`;
  - `budget/lib/pages/meuBancoPage.dart`: botões "Parear com QR", "Atualizar agora" e "Desconectar";
  - `budget/lib/struct/meuBancoSync.dart`: `meuBancoAtualizar()`.

**Interfaces**
```dart
class MbPareamento { final String base; final String token; }
MbPareamento? mbLerLinkPareamento(Uri uri);     // null se inválido
Future<void> mbParear(MbPareamento p);            // salva no secure storage, zera cursor/espelho de pull e sincroniza
Future<String> meuBancoAtualizar();               // mensagem para o snackbar
```

**Passos**
- [ ] **Escrever `mbLerLinkPareamento`:**
  - exige `uri.scheme == 'meubanco' && uri.host == 'parear'`;
  - `u` = origem https sem caminho, ou `http://localhost` / `http://10.0.2.2` só em `kDebugMode`;
  - `t` casa `^mb_[A-Za-z0-9_-]{43}$`;
  - retorna `MbPareamento(u sem barra final, t)`.
- [ ] **`appLinks.dart`:** no início de `executeAppLink`, antes de `hasOnboarded`:
```dart
if (uri.scheme == 'meubanco') { final p = mbLerLinkPareamento(uri); if (p != null) await mbParear(p); else openSnackbar(SnackbarMessage(title: "Link de pareamento inválido")); return; }
```
- [ ] **Manifest:** na activity principal, `<intent-filter><action android:name="android.intent.action.VIEW"/><category android:name="android.intent.category.DEFAULT"/><category android:name="android.intent.category.BROWSABLE"/><data android:scheme="meubanco" android:host="parear"/></intent-filter>` e `<uses-permission android:name="android.permission.CAMERA"/>`.
- [ ] **`meuBancoParear.dart`:**
  - `MobileScanner(onDetect:)`; o primeiro código que passa em `mbLerLinkPareamento` fecha a tela e chama `mbParear`;
  - texto: "Abra o painel do Meu Banco, crie um token de aparelho e aponte a câmera para o QR";
  - fallback "Colar link" com campo de texto;
  - escondido na web (`kIsWeb`).
- [ ] **`mbParear`:** grava token e URL (`meuBancoSalvarConfig`), apaga `cursor` de `mb_estado` (pull completo) e chama `sincronizarMeuBanco()`. Snackbar: "Pareado com <host>".
- [ ] **`meuBancoAtualizar()`:**
  - `cliente.atualizar()`;
  - 200 com `ok: true` → `sincronizarMeuBanco()` e "Atualizado";
  - `ok: false` com `mensagem` → mostra a mensagem;
  - `MbErroLimite` → `"Atualizado há pouco. Tente de novo às HH:mm."` (formatar `liberadoEm` em pt-BR local);
  - 401 → "Token inválido ou revogado. Pareie de novo."
- [ ] **Testes** (`mb_pareamento_test.dart`): link válido; esquema errado; host errado; token curto; `u` http em release recusado (`kDebugMode` é falso nos testes de release; testar a função `mbOrigemPermitida(String u, {required bool debug})` separada); barra final removida.

**Comandos**
```bash
flutter test test/mb_pareamento_test.dart
flutter build apk --debug
adb shell am start -a android.intent.action.VIEW -d "meubanco://parear?u=https%3A%2F%2Fexemplo.test&t=mb_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
```
**Esperado:** o teste passa. O `am start` abre o app e mostra o snackbar de pareamento; o sync falha com mensagem de rede, porque o host é falso.

**Commit:** `Meu Cashew: pareamento por QR e deep link meubanco://, botão Atualizar com limite de 30 min`

---

## Tarefa 7 [C]: Pluggy Connect (conectar e reconectar) no Android

**Arquivos**
- Criar:
  - `budget/lib/pages/meuBancoConectar.dart`
  - `budget/lib/struct/mbSync/pluggy.dart`
  - `budget/test/mb_pluggy_test.dart`
- Modificar:
  - `budget/pubspec.yaml`: `flutter_pluggy_connect: 3.0.1`;
  - `budget/lib/pages/meuBancoPage.dart`: botão "Conectar banco" e lista de avisos com "Reconectar".

**Interfaces**
```dart
String? mbItemIdDoSucesso(dynamic data);   // aceita {item:{id}}, {itemId}, {data:{item:{id}}}
Future<void> mbAbrirConnect(BuildContext context, {String? itemId});
```

**Passos**
- [ ] **Dependência:** `flutter pub get`. Se conflitar com `app_links` (o pacote pede ^6.3.1), subir `app_links` no pubspec para `^6.3.1` e rodar `flutter build apk --debug`.
- [ ] **`mbItemIdDoSucesso`:** procura nessa ordem `data['item']['id']`, `data['itemId']`, `data['data']['item']['id']`. Só aceita string que casa `^[0-9a-f-]{36}$`, a mesma regra de `REGEX_ITEM` do Worker (conferir em `apps/worker/src/pluggy.js` e copiar a expressão exata).
- [ ] **`mbAbrirConnect`:**
  1. `token = await cliente.connectToken(itemId: itemId)`;
  2. `Navigator.push` de uma tela cheia com `PluggyConnect(connectToken: token, updateItem: itemId, onSuccess: ..., onError: ..., onClose: () => Navigator.pop(context))`;
  3. `onSuccess`: `id = mbItemIdDoSucesso(data) ?? itemId`. Se existir, `await cliente.registrarItem(id)`, snackbar "Banco conectado. Sincronizando…" e `sincronizarMeuBanco()` depois de 20 s. Se não, snackbar "Conectado, mas o app não recebeu o código da conexão. Ela entra na próxima sincronização pelo webhook.";
  4. `onError`: snackbar com `error.toString()` cortado em 200 caracteres.
  
  Na web: `kIsWeb` → snackbar "Conecte bancos pelo app no celular" (D7).
- [ ] **Avisos:** `meuBancoPage` lê `mb_estado['avisos']` e lista cada aviso com o banco e a mensagem. O botão "Reconectar" chama `mbAbrirConnect(itemId: aviso['item_id'])`; sem `item_id`, abre `reconnect_url` com `url_launcher`.
- [ ] **Testes:** `mbItemIdDoSucesso` com os 3 formatos, com valor inválido e com null.

**Comandos**
```bash
flutter test test/mb_pluggy_test.dart
flutter build apk --debug
```
**Esperado:** verde e APK gerado.

**Teste manual obrigatório (risco D7 e risco 13 do spec original):**
1. Com o Worker de produção pareado, tocar em "Conectar banco".
2. Escolher o conector **Pluggy Bank (sandbox)**, usuário `user-ok`, senha `password-ok`.
3. Conferir: snackbar de sucesso, linha nova em `pluggy_items` (o usuário confere no painel em "Ferramentas") e contas sandbox no app depois do sync.
4. Se `onSuccess` não trouxer o id, registrar o formato recebido (log em `kDebugMode`) e ajustar `mbItemIdDoSucesso`.
5. Repetir com "Reconectar" num item real.

**Commit:** `Meu Cashew: Pluggy Connect para conectar e reconectar bancos`

---

## Tarefa 8 [C]: tema "Editorial tinta", fontes e primitivas de movimento

**Arquivos**
- Criar:
  - `budget/lib/struct/editorial.dart`: tokens, `ThemeExtension`, estilos de texto e `temaEditorial(Brightness)`;
  - `budget/lib/widgets/editorial/movimento.dart`;
  - `budget/assets/fonts/Geist-Light.ttf`, `Geist-Regular.ttf`, `Geist-Medium.ttf`, `GeistMono-Regular.ttf`, `SourceSerif4-It.ttf`, `OFL-Geist.txt`, `OFL-SourceSerif.txt`;
  - `budget/test/editorial_test.dart`.
- Modificar:
  - `budget/pubspec.yaml`: famílias `Geist` (300/400/500), `GeistMono` e `SerifEditorial` (italic 400);
  - `budget/lib/colors.dart`: `getLightTheme` e `getDarkTheme` passam a delegar a `temaEditorial`;
  - `budget/lib/struct/defaultPreferences.dart`: `"font": "Geist"`, `"materialYou": false`, `"accentColor": "#2340D8"` (no formato `toHexString(Color(0xFF2340D8))`), `"locale": "pt"`;
  - onde a lista de fontes é oferecida: `grep -rn '"Avenir"' lib/`, para incluir `"Geist"`.

**Fontes (rede só agora, no desenvolvimento; nunca em tempo de execução)**
- **Geist estático:** baixar o release oficial em https://github.com/vercel/geist-font/releases (zip, pasta `ttf` estática) e copiar Light, Regular e Medium mais o `OFL.txt`.
  - Se não houver rede, usar `~/.local/share/fonts/Geist-VariableFont_wght.ttf` como família `Geist` e aplicar o peso por `fontVariations: [FontVariation('wght', peso)]` nos estilos.
- **Geist Mono:** `~/.codex/skills/ui-styling/canvas-fonts/GeistMono-Regular.ttf`.
- **Source Serif 4 Italic:** https://github.com/adobe-fonts/source-serif/releases (`TTF/SourceSerif4-It.ttf`) mais a licença.

**Interfaces**
```dart
class EditorialCores extends ThemeExtension<EditorialCores> {
  final Color bg, surf, tx, mu, line, acc, warn, warnbg, warntx, pos, chip;
  static const claro = EditorialCores(bg: Color(0xFFF7F6F3), surf: Color(0xFFFBFBFA), tx: Color(0xFF17181C), mu: Color(0xFF77767A),
      line: Color.fromRGBO(20, 20, 30, .08), acc: Color(0xFF2340D8), warn: Color(0xFFB42318), warnbg: Color(0xFFFDEBEC),
      warntx: Color(0xFF9F2F2D), pos: Color(0xFF2F6B3A), chip: Color(0xFFE8ECFB));
  static const escuro = EditorialCores(bg: Color(0xFF0F1114), surf: Color(0xFF15181C), tx: Color(0xFFECEDEF), mu: Color(0xFF8D9097),
      line: Color.fromRGBO(255, 255, 255, .08), acc: Color(0xFF8EA4FF), warn: Color(0xFFF0726B), warnbg: Color.fromRGBO(240, 114, 107, .12),
      warntx: Color(0xFFF59A94), pos: Color(0xFF7FCB92), chip: Color.fromRGBO(142, 164, 255, .12));
  // copyWith/lerp padrão
}
EditorialCores cores(BuildContext c);
class EdTexto {
  static TextStyle h1(BuildContext c);            // SerifEditorial italic 400 26, height 1.1, letterSpacing -0.52, cor tx
  static TextStyle h2(BuildContext c);            // Geist 500 12, uppercase no widget, letterSpacing 0.96, cor mu
  static TextStyle rotulo(BuildContext c);        // Geist 500 11.5, height 1.2, cor mu
  static TextStyle numeroGrande(BuildContext c, {bool desktop = false}); // Geist 300 50/64, height 1, letterSpacing -.045*tamanho, tabularFigures
  static TextStyle corpo(BuildContext c);         // Geist 400 14, tabularFigures
  static TextStyle mono(BuildContext c);          // GeistMono 10.5, cor mu
}
ThemeData temaEditorial(Brightness b);
// movimento.dart
const Curve curvaEditorial = Cubic(.23, 1, .32, 1);
bool semMovimento(BuildContext c) => MediaQuery.of(c).disableAnimations;
class EntradaEditorial extends StatelessWidget { const EntradaEditorial({required this.indice, required this.child}); } // 420ms, delay 55ms*indice, dy 8->0, opacity 0->1
class ContagemValor extends StatefulWidget { const ContagemValor({required this.valor, required this.formatar, this.estilo}); } // 900ms a partir do valor anterior (1ª vez de 0)
class MedidorEditorial extends StatelessWidget { const MedidorEditorial({required this.fracao, this.alerta = false}); } // altura 2, sem raio, trilho line, scaleX 900ms, warn se alerta
class BarrasDias extends StatelessWidget { const BarrasDias({required this.valores, required this.indiceHoje, this.altura = 40}); } // sem raio, scaleY escalonado 28ms; hoje = acc, demais = line mais forte (tx a 12%), futuras = vazias
class ToqueEscala extends StatefulWidget { const ToqueEscala({required this.child, this.onTap}); } // scale .97 em 150ms no pointer down
```

**Passos**
- [ ] **`temaEditorial(b)`:**
  - `ThemeData(useMaterial3: true, fontFamily: 'Geist', fontFamilyFallback: ['Inter'], scaffoldBackgroundColor: bg, colorScheme: ColorScheme(brightness: b, primary: acc, onPrimary: b == light ? Colors.white : bg, secondary: acc, onSecondary: ..., error: warn, onError: Colors.white, surface: bg, onSurface: tx, surfaceContainerLowest: surf, outline: line, outlineVariant: line), dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1), cardTheme: CardTheme(elevation: 0, color: Colors.transparent, margin: EdgeInsets.zero, shape: RoundedRectangleBorder()), filledButtonTheme e outlinedButtonTheme com raio 8, splashFactory: NoSplash.splashFactory, typography: Typography.material2021())`;
  - depois `generateThemeDataWithExtension(themeData: ..., brightness: b, accentColor: acc)`, para manter o `AppColors` que os widgets do Cashew usam;
  - e `copyWith(extensions: [...anteriores, b == light ? EditorialCores.claro : EditorialCores.escuro])`.
- [ ] **`colors.dart`:** `getLightTheme() => temaEditorial(Brightness.light)` e `getDarkTheme() => temaEditorial(Brightness.dark)`. O código antigo fica atrás de `appStateSettings["temaEditorial"] == false`; o padrão é `true`, em `defaultPreferences`.
- [ ] **Movimento:**
  - cada primitiva checa `semMovimento(context)` e, nesse caso, mostra o estado final sem animar;
  - `ContagemValor` guarda o último valor no `State` e anima com `TweenAnimationBuilder<double>`, `curvaEditorial` e 900ms;
  - nenhuma primitiva é usada em resposta a teclado.
- [ ] **Testes** (`editorial_test.dart`):
  - os 22 valores de cor iguais aos do spec;
  - `temaEditorial(dark).extension<EditorialCores>()!.acc == Color(0xFF8EA4FF)`;
  - `EntradaEditorial` com `MediaQueryData(disableAnimations: true)` já mostra o filho sem `Opacity` < 1 no primeiro frame;
  - `ContagemValor` chega ao texto final após `pump(900ms)`;
  - `MedidorEditorial(fracao: 1.4)` limita em 1.

**Comandos**
```bash
flutter test test/editorial_test.dart
flutter build apk --debug
```
**Esperado:** testes verdes; o app abre com fundo `#F7F6F3` no claro e `#0F1114` no escuro.

**Commit:** `Meu Cashew: tema Editorial tinta (tokens, Geist e serifa empacotadas) e primitivas de movimento`

---

## Tarefa 9 [C]: Início redesenhada (celular) e barra inferior

**Arquivos**
- Criar:
  - `budget/lib/pages/homePage/inicioEditorial.dart`
  - `budget/lib/struct/mbSync/estadoInicio.dart`: lê `mb_estado` e as transações e monta o modelo da tela (puro na parte de cálculo)
  - `budget/test/mb_inicio_test.dart`
- Modificar:
  - `budget/lib/pages/homePage/homePage.dart`: quando pareado (ou `kIsWeb`), o corpo é `InicioEditorial()`; senão, a Início do Cashew;
  - `budget/lib/struct/defaultPreferences.dart`: atalhos da barra `home`, `transactions`, `budgets`;
  - `budget/lib/widgets/bottomNavBar.dart` (confirmar o nome com `grep -rln "customNavBarShortcut2" lib/widgets`): no modo Meu Banco, o 4º item é `goals` ("Metas") e "Mais" sai da barra (Configurações ficam no botão de menu do topo da Início).

**Interfaces**
```dart
class ModeloInicio {
  final String ciclo;            // "Ciclo 26 out – 25 nov"
  final String saudacao;         // "Olá, Renan" (appStateSettings["username"]; vazio -> "Olá")
  final double disponivel;       // soma das contas BANK
  final String origemDisponivel; // "Inter, Santander e poupanças · há 12 min"
  final double consumido; final double? limite; final double? percentual; final int diasRestantes;
  final List<double> porDia; final int indiceHoje;
  final List<({String sigla, String nome, String tipo, double saldo})> contas;  // agrupadas por banco; poupanças somadas ("2 contas")
  final List<({String nome, String final4, int? diasFecha, String? vence, double fatura, double? limite, double? pct})> cartoes;
  final List<({String nome, String categoria, String quando, double valor, bool receita})> ultimas; // 5 mais recentes
}
ModeloInicio montarModeloInicio({required Map<String, dynamic> ciclo, required List<Map<String, dynamic>> contas, required Map<String, dynamic> faturas,
    required String? sincronizadoEm, required List<({String nome, String categoria, DateTime data, double valor, bool receita})> ultimas,
    required String nome, required DateTime agora});
String brl(double v);            // "R$ 2.417,16", NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$ ')
String quandoRelativo(DateTime d, DateTime agora); // "hoje", "ontem", "05 nov"
String haQuanto(DateTime d, DateTime agora);       // "há 12 min", "há 2 h"
```

**Especificação visual** (referência: `/home/renan/.t3/userdata/attachments/meu-banco-celular-editorial.png`). Rolagem única, padding lateral 20, seções separadas por `Divider` (filete 1px `line`), sem cartões e sem sombra. Cada seção entra com `EntradaEditorial(indice: i)`.
1. **Topo:**
   - `rotulo` "Ciclo 26 out – 25 nov" (datas de `ciclo.inicio` e `ciclo.fim`, mês abreviado em pt);
   - abaixo, `h1` "Olá, Renan";
   - à direita, botão 40×40 com raio 8, borda `line` e fundo `surf`, ícone de atualizar (`Icons.refresh`, 20). Toque → `meuBancoAtualizar()` com `ToqueEscala`; enquanto atualiza, o ícone gira com o movimento desligado se `semMovimento`;
   - ícone de menu (Configurações).
2. **"Disponível agora":**
   - `rotulo`;
   - `ContagemValor` com `numeroGrande` (50px);
   - linha `rotulo` cor `mu`: origem e "há N min".
3. **"Gasto no ciclo":**
   - linha com `rotulo` à esquerda e valor em Geist 600 15 tabular à direita;
   - `MedidorEditorial(fracao: consumido/limite, alerta: pct >= 100)`;
   - linha `rotulo` "27% do previsto" à esquerda e "17 dias restantes" à direita;
   - `BarrasDias(porDia, indiceHoje)` com 40px de altura. Sem limite: medidor oculto e o texto "Defina o limite no painel".
4. **"CONTAS"** (`h2` em maiúsculas):
   - linhas de 56px: marca 32×32 com raio 6, fundo `chip`, sigla de 2 letras em `acc` 11 500; nome em `corpo` 500 e tipo em `rotulo`; saldo à direita em 500 tabular;
   - filete entre linhas.
5. **Cartão** (um bloco por conta CREDIT):
   - `h2` "CARTÃO GOLD ·1950";
   - `rotulo` "Fecha em 3 dias · vence 05 dez";
   - selo à direita "101%" (fundo `warnbg`, texto `warntx`, raio 8, 11 500) só quando pct >= 80; abaixo de 80, o selo usa `chip` e `acc`;
   - `MedidorEditorial(fracao: fatura/limite, alerta: pct >= 100)`;
   - linha "Fatura R$ 607,65" e "Limite R$ 600,00" em `rotulo`.
6. **"ÚLTIMAS":**
   - 5 linhas: nome 500 e "Categoria · hoje" em `rotulo`; valor à direita com `−R$` em `tx` ou `+R$` em `pos`;
   - toque abre a transação no editor do Cashew (`pushRoute` para `AddTransactionPage`, como `TransactionEntry` faz).
7. **Barra inferior:** Início, Transações, Orçamentos e Metas; ativo em `acc` com sublinhado de 2px, inativo em `mu`, rótulo 11.5 500, fundo `bg` e filete `line` em cima.

**Testes** (`mb_inicio_test.dart`): `montarModeloInicio` com JSON de exemplo.
- disponível soma só as BANK;
- poupanças agrupadas com "2 contas";
- `diasFecha` a partir de `closing_date`;
- pct do cartão = saldo/limite;
- `indiceHoje` correto;
- `brl(2417.16) == 'R\$ 2.417,16'`;
- `quandoRelativo` hoje, ontem e data;
- widget test: `InicioEditorial` com um modelo injetado (construtor `InicioEditorial.comModelo`) mostra "Disponível agora" e "CONTAS".

**Comandos**
```bash
flutter test test/mb_inicio_test.dart
flutter build apk --debug
```
**Esperado:** verde; a Início no aparelho bate com a referência nos dois temas.

**Commit:** `Meu Cashew: Início no estilo Editorial (ciclo, disponível, gasto no ciclo, contas, cartão, últimas)`

---

## Tarefa 10 [C]: notificações em segundo plano e widget Android

**Arquivos**
- Criar:
  - `budget/lib/struct/mbSync/segundoPlano.dart`
  - `budget/android/app/src/main/kotlin/com/example/budget/MeuBancoWidgetProvider.kt`
  - `budget/android/app/src/main/res/layout/meu_banco_widget_layout.xml`
  - `budget/android/app/src/main/res/xml/meu_banco_widget.xml`
  - `budget/android/app/src/main/res/values/mb_widget_cores.xml` e `values-night/mb_widget_cores.xml`
  - `budget/android/app/src/main/res/drawable/mb_medidor.xml`
  - `budget/test/mb_segundo_plano_test.dart`
- Modificar:
  - `budget/pubspec.yaml`: `workmanager: 0.5.2`;
  - `budget/lib/main.dart`: registra a tarefa quando não é web;
  - `budget/lib/struct/mbSync/widget.dart`: implementa `mbAtualizarWidget`;
  - `AndroidManifest.xml`: `<receiver android:name="MeuBancoWidgetProvider" android:exported="false">` com o intent-filter `APPWIDGET_UPDATE` e o meta-data `@xml/meu_banco_widget`, no padrão dos receivers que já existem.

**Interfaces**
```dart
const String mbTarefaAlertas = 'meu-banco-alertas';
@pragma('vm:entry-point') void mbDespachante();   // Workmanager().executeTask
Future<void> mbRegistrarSegundoPlano();          // registerPeriodicTask(mbTarefaAlertas, ..., frequency: 15 min, constraints: NetworkType.connected, existingWorkPolicy: keep)
Future<int> mbConferirAlertas({required MbCliente cliente, required Future<void> Function(int id, String titulo, String corpo) mostrar,
    required Future<String?> Function() lerCursor, required Future<void> Function(String) gravarCursor,
    required Future<void> Function(Map<String, dynamic> resumo) salvarWidget});   // devolve quantas mostrou
int mbIdNotificacao(String chave);   // FNV-1a 31 bits (estável entre execuções; String.hashCode não é)
Future<void> mbAtualizarWidget({Map<String, dynamic>? resumo});
```

**Passos**
- [ ] **`mbConferirAlertas`:**
  1. `r = await cliente.notificacoes(await lerCursor())`;
  2. para cada notificação, `mostrar(mbIdNotificacao(chave), titulo, corpo)`;
  3. `gravarCursor(r['cursor'])`;
  4. `salvarWidget(r['resumo'])`.
  
  Erro de rede: retorna 0 sem mexer no cursor.
- [ ] **`mbDespachante`:** dentro de `Workmanager().executeTask`:
  1. `WidgetsFlutterBinding.ensureInitialized()` e `DartPluginRegistrant.ensureInitialized()`;
  2. `SharedPreferences.getInstance()`, que guarda o cursor em `mbNotifCursor` (fora de `appStateSettings`);
  3. cliente a partir do secure storage;
  4. `FlutterLocalNotificationsPlugin().initialize(InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')))`;
  5. canal `meu_banco_alertas` ("Alertas do Meu Banco", importância alta);
  6. `mbConferirAlertas(...)`;
  7. retorna `true`.
  
  Não abre o Drift no isolate de fundo.
- [ ] **`main.dart`:** depois de `initializeSettings()`, `if (!kIsWeb && Platform.isAndroid) { await Workmanager().initialize(mbDespachante); await mbRegistrarSegundoPlano(); }`. O app já pede a permissão de notificação (Android 13+) em `initializeNotifications`; conferir e, se não pedir, chamar `requestNotificationsPermission()` na tela Meu Banco depois de parear.
- [ ] **`mbAtualizarWidget`:** com `HomeWidget.saveWidgetData<String>`, gravar:
  - `mb_disponivel` (`brl`);
  - `mb_gasto` ("R$ 3.403,01 de R$ 12.600,00", ou só o consumido);
  - `mb_pct` (inteiro de 0 a 100, limitado);
  - `mb_alerta` ("1" se pct >= 100);
  - `mb_sinc` ("Sinc. 14:32", hora local do `sincronizado_em`).
  
  Depois, `HomeWidget.updateWidget(androidName: 'MeuBancoWidgetProvider')`. É chamado no fim de `sincronizarMeuBanco` (com o resumo montado de `mb_estado`) e no segundo plano.
- [ ] **Widget Kotlin:** `MeuBancoWidgetProvider : HomeWidgetProvider()`. `onUpdate` lê `widgetData.getString(...)` e preenche `RemoteViews(R.layout.meu_banco_widget_layout)`:
  - TextView "Disponível agora" (11.5sp, cor `mb_mu`);
  - valor (28sp, fonte `sans-serif-light`, cor `mb_tx`);
  - "Gasto no ciclo" + texto;
  - `ProgressBar` horizontal de 2dp com `progressDrawable` `@drawable/mb_medidor` (trilho `mb_line`, progresso `mb_acc`; se `mb_alerta == "1"`, troca para um layout com o progresso `mb_warn` via `setInt(..., "setProgressTintList")` ou um segundo ProgressBar visível);
  - rodapé `mb_sinc` (10.5sp, `mb_mu`).
  
  Fundo `mb_bg`, cantos de 8dp. Cores em `values` e `values-night` com os tokens exatos (`#F7F6F3`, `#17181C`, `#77767A`, `#2340D8`, `#B42318` e equivalentes escuros; `line` como `#14141E14` e `#FFFFFF14`). Toque abre o app (`HomeWidgetLaunchIntent.getActivity`). `xml/meu_banco_widget.xml`: `minWidth 250dp`, `minHeight 110dp`, `updatePeriodMillis 0`.
- [ ] **Testes** (`mb_segundo_plano_test.dart`):
  - `mbIdNotificacao` é estável e positivo;
  - `mbConferirAlertas` com cliente falso: mostra 2, grava o cursor novo e chama `salvarWidget`;
  - em erro, não grava o cursor.

**Comandos**
```bash
flutter test test/mb_segundo_plano_test.dart
flutter build apk --debug
adb shell cmd jobscheduler run -f br.renan.meucashew 999   # opcional; ou esperar 15 min
```
**Esperado:** verde.

**Teste manual:**
1. Adicionar o widget "Meu Banco" à tela inicial: ele mostra o saldo.
2. No Worker local, usar `POST /api/push/teste` (painel) para gerar um alerta.
3. Até 15 min depois (ou forçando pelo App Inspector do Android Studio), a notificação local aparece.

**Commit:** `Meu Cashew: alertas em segundo plano (workmanager + notificação local) e widget Meu Banco`

---

## Tarefa 11 [C]: versão visível, Firebase desligado e scripts de build

**Arquivos**
- Criar:
  - `budget/lib/widgets/editorial/versaoCanto.dart`
  - `scripts/compilar.sh`
  - `budget/test/versao_test.dart`
- Modificar:
  - `budget/lib/main.dart`: remove `Firebase.initializeApp` e põe `VersaoCanto` no `builder` do `MaterialApp`;
  - `scripts/nova-versao.sh`: sem argumento, incrementa o PATCH e o build;
  - `.github/workflows/release-android.yml`: `--dart-define=MB_COMPILADO`;
  - `README.md` do fork.

**Interfaces**
```dart
const String mbCompilado = String.fromEnvironment('MB_COMPILADO', defaultValue: 'dev');
String textoVersao(String versionName, String compilado) => 'v$versionName · $compilado';
class VersaoCanto extends StatelessWidget { const VersaoCanto({super.key, required this.child}); }
```

**Passos**
- [ ] **`VersaoCanto`:** `Stack(children: [child, Positioned(top: MediaQuery.paddingOf(context).top + 4, right: 10, child: IgnorePointer(child: Text(textoVersao(packageInfoGlobal?.version ?? '?', mbCompilado), style: EdTexto.mono(context).copyWith(color: cores(context).mu.withOpacity(.7)))))])`.
  - No desktop (largura >= 1100), não desenha no canto, porque a lateral mostra a versão (Tarefa 13).
  - `ExcludeSemantics` para não poluir o leitor de tela.
  - `main.dart`: `MaterialApp(builder: (context, child) => VersaoCanto(child: child!))`. Se já existir um `builder`, encadear.
- [ ] **Firebase:** apagar o bloco `try { await Firebase.initializeApp(...) }` e o import de `firebase_options.dart`. Conferir com `grep -rn "Firebase.initializeApp" lib/`, que deve dar vazio. As chamadas do Cashew a Firestore e Auth existem só em fluxos de compartilhamento e login Google, que ficam fora (D11); se algum fluxo de inicialização chamar `FirebaseAuth.instance`, protegê-lo com `if (false)` comentado ou removê-lo.
- [ ] **`scripts/compilar.sh`:**
```bash
#!/usr/bin/env bash
# Uso: scripts/compilar.sh apk|apk-debug|web <destino-web>
set -euo pipefail
cd "$(git rev-parse --show-toplevel)/budget"
quando="$(TZ=America/Sao_Paulo date '+%d/%m/%Y %H:%M')"
case "${1:-}" in
  apk) flutter build apk --release --dart-define=MB_COMPILADO="$quando" ;;
  apk-debug) flutter build apk --debug --dart-define=MB_COMPILADO="$quando" ;;
  web) dest="${2:?informe a pasta de destino}"
       flutter build web --release --base-href /app/ --no-web-resources-cdn --web-renderer canvaskit --pwa-strategy none --dart-define=MB_COMPILADO="$quando"
       mkdir -p "$dest" && rsync -a --delete build/web/ "$dest/" ;;
  *) echo "Uso: $0 apk|apk-debug|web <destino>" >&2; exit 1 ;;
esac
```
- [ ] **Workflow:** no passo de build, `flutter build apk --release --dart-define=MB_COMPILADO="$(TZ=America/Sao_Paulo date '+%d/%m/%Y %H:%M')"`.
- [ ] **`nova-versao.sh`:** sem argumento, lê `X.Y.Z+B` do pubspec e usa `X.Y.(Z+1)+(B+1)`. Continua só criando commit e tag locais; o push é do usuário.
- [ ] **Testes** (`versao_test.dart`): `textoVersao('5.4.4', '09/11/2026 14:20') == 'v5.4.4 · 09/11/2026 14:20'`. Widget test: o texto existe e um `GestureDetector` embaixo dele recebe o toque (`tester.tap` na posição do texto dispara o callback).

**Comandos**
```bash
flutter test test/versao_test.dart
../scripts/compilar.sh apk-debug
flutter test
```
**Esperado:** verde. A versão aparece no canto de todas as telas e não bloqueia toques. A suíte toda passa.

**Commit:** `Meu Cashew: versão visível em todas as telas, Firebase desligado e script de build com data de compilação`

---

## Tarefa 12 [C + W]: build web servido pelo Worker em `/app/` com cookie

**Arquivos**
- **[C]** Modificar:
  - `budget/web/index.html`: remover o `<script type="module">` do Firebase (linhas 69–90); título "Meu Banco";
  - `budget/web/manifest.json`: nome, cores `#F7F6F3` e `#2340D8`, `start_url: "./"`;
  - `budget/lib/struct/mbSync/cliente.dart`: 401 na web → `html.window.location.href = '/login?volta=/app/'`, via `universal_html`, que já é dependência;
  - `budget/lib/main.dart` ou `onBoardingPage.dart`: na web, `hasOnboarded = true` automático (o usuário entra direto) e `sincronizarMeuBanco()` no início;
  - guardas `kIsWeb` em workmanager, home_widget, mobile_scanner, Connect e atualizador de APK (`grep -rn "atualizadorProcurar" lib/` → não chamar na web).
- **[W]** Modificar:
  - `apps/worker/src/index.js`: bloco `/app`, `seguranca(resp, csp)`;
  - `apps/worker/public/login.html`: `volta`;
  - `apps/worker/public/sw.js`: ignora `/app/`;
  - `apps/worker/package.json`: `push` confere o build;
  - `.gitignore`: `apps/worker/public/app/`;
  - `README.md`.
- **[W]** Criar: `apps/worker/scripts/conferir-app.mjs` e `apps/worker/test/app-web.test.mjs`.

**Interfaces [W]**
```js
const CSP_PAINEL = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; manifest-src 'self'; worker-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'";
const CSP_APP = "default-src 'self'; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; manifest-src 'self'; worker-src 'self' blob:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'";
function seguranca(resp, csp = CSP_PAINEL)
```

**Passos**
- [ ] **[C] Compilar primeiro, antes de qualquer outra mudança:**
  ```bash
  ../scripts/compilar.sh web /home/renan/dev/meu-banco/.worktrees/fase23/apps/worker/public/app
  ```
  Corrigir os erros de compilação web que aparecerem: imports `dart:io` sem guarda (`grep -rln "dart:io" lib/` contra os arquivos novos das Tarefas 5 a 11). Os arquivos novos usam `kIsWeb` e não importam `dart:io` no topo, exceto `atualizador.dart`, que já é só Android: importar de forma condicional ou mover o uso de `Platform` para trás de `!kIsWeb`.
  - **Plano B**, se o CanvasKit falhar no runtime (tela branca, erro de wasm no console): `--web-renderer html`. Registrar no README qual ficou.
- [ ] **[W] Roteamento em `index.js`,** antes do `PUBLICO.test`:
```js
if (caminho === "/app" ) return seguranca(new Response(null, { status: 301, headers: { location: "/app/" } }));
if (caminho.startsWith("/app/")) {
  if (!(await sessaoValida(request, env))) return seguranca(new Response(null, { status: 302, headers: { location: "/login?volta=/app/" } }));
  const r = await env.ASSETS.fetch(request);
  const resp = seguranca(r, CSP_APP);
  resp.headers.set("cache-control", "private, no-cache");
  return resp;
}
```
  Isso fica dentro do `try`, mantendo o padrão das outras rotas. `seguranca` passa a receber `csp` e o `cache-control` atual continua só para o painel.
- [ ] **[W] `login.html`:** no sucesso, `const volta = new URLSearchParams(location.search).get("volta"); location.replace(volta === "/app/" ? "/app/" : "/");`. É uma lista fechada, para não virar redirecionamento aberto.
- [ ] **[W] `sw.js`:** no `fetch`, `if (url.pathname.startsWith("/app/")) return;` antes das demais regras.
- [ ] **[W] `scripts/conferir-app.mjs`:** sai com erro e a mensagem "Gere o app web: no meu-cashew, scripts/compilar.sh web <...>/apps/worker/public/app" quando `public/app/index.html` não existe. O script `push` vira `node scripts/conferir-app.mjs && node scripts/versao.mjs && wrangler deploy`.
- [ ] **[W] Testes** (`app-web.test.mjs`, com `criarAmbiente`):
  - `/app` → 301 para `/app/`;
  - `/app/` sem cookie → 302 para `/login?volta=/app/`;
  - com cookie → 200, CSP contém `'wasm-unsafe-eval'` e `base-uri 'self'`;
  - `/` continua com `base-uri 'none'`;
  - `GET /api/sync` com cookie e sem Origin → 200;
  - `POST /api/sync` com cookie e Origin de fora → 403.

**Comandos**
```bash
cd /home/renan/dev/meu-banco/.worktrees/fase23 && pnpm test
cd apps/worker && pnpm db:local && (pnpm mock &) && pnpm dev
```
**Esperado:** testes verdes. Com o dev local, abrir `http://localhost:8787/app/`:
1. sem login, vai para o login;
2. depois do login, o app carrega, sincroniza pelo cookie e mostra a Início com os dados do mock;
3. o console não tem erro de CSP.

**Commits (um por repositório):**
- [C] `Meu Cashew web: build para /app/ sem Firebase, sync por cookie de sessão`
- [W] `Worker: serve o app web em /app/ com CSP própria, volta do login e conferência do build no push`

---

## Tarefa 13 [C]: layout desktop (3 colunas), Ctrl+K, detalhe fixo e atalhos

**Arquivos**
- Criar:
  - `budget/lib/widgets/editorial/layoutDesktop.dart`
  - `budget/lib/widgets/editorial/lateralEditorial.dart`
  - `budget/lib/widgets/editorial/detalheTransacao.dart`
  - `budget/lib/widgets/editorial/buscaRapida.dart`
  - `budget/lib/pages/homePage/painelDesktop.dart`
  - `budget/test/desktop_test.dart`
- Modificar:
  - `budget/lib/main.dart`: com largura >= 1100, troca a `Row(NavigationSidebar, ...)` por `LayoutDesktop`;
  - `budget/lib/struct/keyboardIntents.dart`: intents novas;
  - `budget/lib/widgets/transactionEntry/transactionEntry.dart`: no desktop, o toque seleciona em vez de abrir o editor.

**Interfaces**
```dart
const double mbLarguraDesktop = 1100;
bool ehDesktop(BuildContext c) => MediaQuery.sizeOf(c).width >= mbLarguraDesktop;
final ValueNotifier<String?> mbTransacaoSelecionada = ValueNotifier(null);   // transactionPk
class LayoutDesktop extends StatelessWidget { const LayoutDesktop({required this.conteudo}); } // Row: 232 | Expanded | 360 (detalhe só se selecionada)
class AbrirBuscaIntent extends Intent {} class MudarCategoriaIntent extends Intent {} class VerTransacoesIntent extends Intent {}
class FecharDetalheIntent extends Intent {} class ProximaTransacaoIntent extends Intent {} class AnteriorTransacaoIntent extends Intent {} class AtualizarIntent extends Intent {}
```

**Especificação** (referências: `meu-banco-desktop-claro.png` e `meu-banco-desktop-escuro.png`)
- **Grade:**
  - coluna 1 com 232px, fundo `bg` e filete à direita;
  - coluna 2 `1fr`, padding 36 nas laterais;
  - coluna 3 com 360px, fundo `surf` e filete à esquerda.
  
  Sem detalhe selecionado, a coluna 3 some e a 2 ocupa o espaço (sem animação de largura).
- **Lateral:**
  - marca "Meu Banco" em `h1` 24px no topo;
  - navegação: Início, Transações, Orçamentos, Metas, Dívidas, Assinaturas (as páginas do Cashew: `navBarIconsData` `home`, `transactions`, `budgets`, `goals`, `loans`, `subscriptions`); item com ícone de 18 e texto 14 500; ativo com fundo `surf`, raio 8 e borda `line`;
  - depois `h2` "CONTAS" e uma linha por conta do `mb_estado` (toque abre `WalletDetailsPage` da carteira `mb:<id>`);
  - rodapé: `rotulo` "Sincronizado há N min" (de `sincronizado_em`, atualizado a cada minuto com `TimerBuilder`, que já é dependência) e, abaixo, `textoVersao` em `mono`.
- **Topo da coluna 2:**
  - `rotulo` "Ciclo 26 out – 25 nov · 17 dias restantes";
  - `h1` "Olá, Renan";
  - à direita, campo de busca falso de 260×38 com raio 8, borda `line`, "Buscar ou ir para…" e chip `Ctrl K` em `mono` (clique → busca);
  - botão "Atualizar" com contorno e raio 8.
- **Painel (Início desktop), duas colunas com filete vertical:**
  - **Esquerda:** "Disponível agora", número de 64px, origem, `BarrasDias` de 50px com as datas do ciclo nas pontas e "Gasto por dia" no centro (`rotulo`).
  - **Direita:** "GASTO NO CICLO", com medidor, "27% do previsto" e "Previsto R$ …"; depois o bloco do cartão com o selo "101% DO LIMITE".
  - **Abaixo, à esquerda:** "ÚLTIMAS TRANSAÇÕES" em tabela (DESCRIÇÃO, CATEGORIA como chip em maiúsculas 10.5 500 com fundo `chip`; receita em `pos` sobre `pos` a 12%; alerta em `warnbg` com `warntx`; VALOR à direita). A linha selecionada tem borda esquerda de 2px em `acc` e fundo `surf`; "Ver todas" com chip `T`.
  - **Abaixo, à direita:** "ORÇAMENTOS", uma linha por orçamento com o nome, "R$ 812 de R$ 1.400" e um medidor (alerta quando >= 100%). Os valores vêm de `database.watchTotalSpentInTimeRangeFromCategories` ou da função que `budgetsListPage` já usa (reaproveitar o cálculo, não reescrever).
- **Detalhe fixo** (`detalheTransacao.dart`):
  - "Transação" em `rotulo` e botão X (32, raio 8, borda);
  - nome em `h1`; data e hora em `rotulo`; valor em `numeroGrande` 44;
  - filete; tabela chave/valor: Conta, Categoria (chip), Pluggy (categoria original traduzida → original; só em `mb:`), Fatura ("Fecha dd mmm", se cartão);
  - bloco "Regra automática" (borda `line`, raio 8, fundo `bg`): a regra que casou (`mbCategoriaEfetiva` com fonte "regra") e "Aplicada a N transações". Se não houver regra, botão "Criar regra `<DESCRIÇÃO>*` → <categoria>", que grava um `AssociatedTitle` (vira registro `regras` no sync);
  - "HISTÓRICO AQUI": as 3 últimas com a mesma descrição normalizada e a linha "Média R$ … por compra · N no ciclo";
  - rodapé com o botão "Mudar categoria" (preenchido em `tx`, chip `C`), que abre o seletor de categorias do Cashew e salva com `createOrUpdateTransaction`.
  
  "Dividir" não aparece (fora, D3 e seção 3 do addendum).
- **Ctrl+K** (`buscaRapida.dart`):
  - diálogo central de 560px, `transitionDuration: Duration.zero` (sem animação em ação de teclado);
  - campo com foco; resultados agrupados: "Ir para" (páginas da lateral) e "Transações" (busca do Cashew por título: reaproveitar a consulta de `transactionsSearchPage.dart`, limite 20);
  - ↑↓ navegam, Enter abre, Esc fecha.
- **Atalhos** (`shortcuts`, só no desktop e fora de campos de texto):

  | Tecla | Ação |
  |---|---|
  | `Ctrl+K` | busca |
  | `C` | mudar categoria (com detalhe aberto) |
  | `T` | Transações |
  | `Esc` | fecha a busca, senão o detalhe |
  | `J` / `K` | próxima ou anterior na lista visível |
  | `Ctrl+Shift+R` | Atualizar |

  Os atalhos `Ctrl+1` a `Ctrl+4` do Cashew continuam. Nenhum atalho dispara animação: a troca de seleção e de página é instantânea quando vem de teclado (passar `animar: false`).

**Testes** (`desktop_test.dart`, `tester.view.physicalSize = Size(1280, 800)`):
- aparece a lateral com "Meu Banco" e a versão;
- selecionar uma transação mostra o detalhe com 360px;
- `Ctrl+K` abre a busca no mesmo frame (sem `pumpAndSettle`) e `Esc` fecha;
- `C` com detalhe aberto abre o seletor;
- com 390×844, não há lateral e a barra inferior aparece.

**Comandos**
```bash
flutter test test/desktop_test.dart
../scripts/compilar.sh web /home/renan/dev/meu-banco/.worktrees/fase23/apps/worker/public/app
```
**Esperado:** verde; `/app/` em 1280px igual à referência na estrutura.

**Commit:** `Meu Cashew desktop: grade 232/1fr/360, lateral, detalhe fixo, Ctrl+K e atalhos sem animação`

---

## Tarefa 14 [W + C]: verificação visual com Playwright (1280 e 390, claro e escuro)

**Arquivos**
- **[W]** Criar:
  - `apps/worker/scripts/prints-app.mjs`
  - `.claude/skills/verificar-app-web/SKILL.md` (como subir mock, dev e build e tirar os prints)
- **[W]** Modificar:
  - `apps/worker/package.json`: devDependency `"playwright": "1.49.1"` e script `"prints": "node scripts/prints-app.mjs"`;
  - `.gitignore`: `apps/worker/.prints/`.

**Passos**
- [ ] **`prints-app.mjs`:**
  1. `chromium.launch()`;
  2. login por `POST http://localhost:8787/api/login` com a senha de `.dev.vars` (lida do arquivo, nunca impressa) e o cookie posto no contexto;
  3. para cada `{w: 1280, h: 800}` e `{w: 390, h: 844}` × `colorScheme: 'light' | 'dark'`: `page.goto('/app/')`, esperar `flt-glass-pane` e mais 2500 ms (animações de 900 ms e sync), e `page.screenshot({ path: .prints/app-<w>-<tema>.png })`;
  4. na de 1280: clicar na primeira linha de "Últimas transações" (coordenada da primeira linha da tabela; com CanvasKit, clicar por posição) e tirar `app-1280-<tema>-detalhe.png`;
  5. `Ctrl+K` → `app-1280-<tema>-busca.png`.
  
  Também gerar com `reducedMotion: 'reduce'` um print logo após o carregamento (sem os 2500 ms), que já deve mostrar o estado final.
- [ ] **Rodar:** `pnpm db:local`, `pnpm mock`, `pnpm dev`, gerar o build web (Tarefa 12), `pnpm exec playwright install chromium` e `pnpm --filter @meu-banco/worker prints`.
- [ ] **Comparar** com `/home/renan/.t3/userdata/attachments/meu-banco-desktop-claro.png`, `meu-banco-desktop-escuro.png` e `meu-banco-celular-editorial.png`. Abrir os prints com a ferramenta de leitura de imagem e conferir:
  - as 3 colunas com 232 e 360px;
  - serifa itálica nos títulos;
  - versalete nos `h2`;
  - número grande fino e tabular;
  - um só azul;
  - vermelho só no cartão estourado;
  - filetes em vez de cartões;
  - a versão `vX.Y.Z · dd/mm/aaaa HH:mm` visível em todos os prints.
  
  Corrigir no app e repetir até bater.
- [ ] **Android:** `../scripts/compilar.sh apk-debug`, instalar e tirar `adb exec-out screencap -p > apps/worker/.prints/android-<tema>.png` nos dois temas (trocar com `adb shell cmd uimode night yes|no`).
- [ ] **Skills de verificação:** rodar `verificacao-manter` nos dois repositórios.

**Comandos**
```bash
cd /home/renan/dev/meu-banco/.worktrees/fase23 && pnpm test
cd /home/renan/dev/meu-cashew/.worktrees/fase23/budget && flutter test
```
**Esperado:** as suítes verdes; 10 prints web e 2 do Android em `apps/worker/.prints/`, aprovados pela comparação acima. Mostrar os prints ao usuário.

**Commits:**
- [W] `Verificação visual do app web: prints Playwright em 1280 e 390, claro e escuro`
- [C] (se houve ajustes) `Meu Cashew: ajustes visuais da verificação com prints`

**Para o usuário (produção, não executar):**
1. Rodar a migração da Tarefa 1.
2. No meu-banco: `scripts/compilar.sh web .../apps/worker/public/app` (no meu-cashew) e `pnpm push`.
3. No meu-cashew: `scripts/nova-versao.sh` e `git push origin HEAD <tag>`.
4. Instalar o APK pelo atualizador e parear pelo QR do painel.
5. Validar `/app/` contra `/` antes de decidir pela saída do painel.

---

### Critical Files for Implementation
- /home/renan/dev/meu-cashew/.worktrees/fase23/budget/lib/struct/meuBancoSync.dart
- /home/renan/dev/meu-cashew/.worktrees/fase23/budget/lib/database/tables.dart
- /home/renan/dev/meu-cashew/.worktrees/fase23/budget/lib/colors.dart
- /home/renan/dev/meu-banco/.worktrees/fase23/apps/worker/src/index.js
- /home/renan/dev/meu-banco/.worktrees/fase23/packages/core/src/sync.ts
