# Meu Cashew: Fases 2 e 3 dentro do fork (addendum ao design)

- **Data:** 09/11/2026
- **Status:** decisão do usuário já tomada; este documento registra o que muda
- **Spec base:** `meu-banco/docs/superpowers/specs/2026-11-09-app-completo-design.md` (chamado aqui de "spec original")
- **Repositórios:** `meu-cashew` (Flutter, código em `budget/`) e `meu-banco` (Worker, `apps/worker`, e `packages/core`)

## 1. O que muda

O spec original previa um app Android em Expo e um web em React, aposentando o fork do Cashew. **Isso não vale mais.** As Fases 2 (Android) e 3 (web desktop) acontecem dentro do fork **Meu Cashew** (Flutter 3.24.5):

| Spec original | Agora |
|---|---|
| `apps/mobile` (Expo, Reanimated, expo-background-task) | O próprio Meu Cashew no Android (`br.renan.meucashew`). Segundo plano com `workmanager` |
| `apps/web` (React, Vite, Motion, IndexedDB) | Build web do mesmo Flutter (`flutter build web`, Drift web com sql.js no IndexedDB), servido pelo Worker em `/app/` |
| Telas novas de orçamentos, metas, dívidas e assinaturas | As telas do Cashew que já existem (`budgetsListPage`, `objectivesListPage`, `creditDebtTransactionsPage`, `subscriptionsPage`), ligadas ao sync e ao visual Editorial |
| CI do APK com `expo prebuild` | O workflow que já existe (`.github/workflows/release-android.yml`) e o atualizador por GitHub Releases |
| Fase 4: "fork do Cashew arquivado" | O fork **é** o produto. A Fase 4 passa a ser: remover `/api/app/transacoes`, apagar o secret `PLUGGY_ITEM_IDS` e tirar o painel antigo de `/` |

Continua valendo, adaptado ao Cashew: as seções 2 (escopo), 4 (dados e sincronização: protocolo, `registros`, last-write-wins, fila offline), 5 (Pluggy), 6 (categorias e regras), 7 (alertas), 8 (visual "Editorial tinta", com os tokens exatos) e 9 (versão visível `vX.Y.Z · dd/mm/aaaa HH:mm`, America/Sao_Paulo).

## 2. Decisões

### D1. Sincronização por "projeção" e espelho local
- **O quê:** o app guarda, em tabelas SQL próprias dentro do mesmo SQLite do Cashew (`mb_registros`, `mb_estado` e `mb_aplicado`, criadas com `CREATE TABLE IF NOT EXISTS` via `customStatement`), o último estado conhecido de cada registro (`dados`, `updated_at`, `deleted_at`), a **projeção** do objeto local no momento da última sincronização e uma marca `pendente` (a fila offline).
- **Mudança local:** a projeção atual do objeto do Cashew difere da projeção guardada. Vai para a fila com `updated_at` = `dateTimeModified` do Cashew (ou a hora atual, se não for maior que a do espelho).
- **Exclusão local:** um registro com projeção no espelho e sem objeto no Cashew vira tombstone.
- **Pull:** aplica no Cashew só o registro remoto que vence o espelho (`updated_at` estritamente maior, a mesma regra do servidor). A gravação vai direto pelo Drift, com `dateTimeModified` = `updated_at` remoto, então não volta como mudança local.
- **Motivo:**
  - não exige ganchos em cada `createOrUpdate` do Cashew (código upstream grande);
  - não exige migração do schema Drift (schema 46 continua);
  - o núcleo (detecção, LWW, mapeamento) é Dart puro e testável.
- **Ordem de cada rodada:** detectar → push da fila (lotes de 500) → pull → aplicar → importar transações do banco → salvar o cursor.

### D2. Ids
- O registro de um objeto do Cashew tem id `cashew:<pk>`. Isso bate com a importação da Fase 1 (`scripts/cashew.mjs`), então o primeiro sync não duplica nada.
- Um id remoto sem o prefixo vira o pk local, sem mudança.
- Ajustes usam o id da transação do Pluggy. No Cashew, o pk da transação é `mb:<id>`.

### D3. Mapeamento Cashew ↔ protocolo

| Tabela | Objeto do Cashew | Observação |
|---|---|---|
| `categorias` | `Categories` | `pai_id` ↔ `mainCategoryPk`. O campo `pluggy` vive só no espelho e é preservado na mescla |
| `regras` | `AssociatedTitles` (título → categoria) | Só os padrões `X`, `X*`, `*X` e `*X*`. Os demais (curinga no meio) ficam só no espelho, e a categoria efetiva usa todos |
| `orcamentos` | `Budgets` não arquivados | O Cashew não tem "ciclo": o orçamento aparece como mensal e o `periodo` remoto é preservado. Arquivar no Cashew = excluir no sync |
| `metas` | `Objectives` com type goal | `valor_atual` não é enviado pelo app; ele é derivado dos lançamentos com `meta_id` |
| `dividas` | `Objectives` com type loan | `sentido` ↔ `income`. `pago` não é enviado; é derivado dos lançamentos com `divida_id` |
| `lancamentos` | Transações manuais (pk sem `mb:`, `type` nulo, credit ou debt) | Campos extras `meta_id` e `divida_id` (o core aceita chaves extras). `carteira` = nome da carteira |
| `assinaturas` | Transação do Cashew com `type = subscription` (status `confirmada`) | `ignorada` fica só no espelho. `padrao` é preservado; para assinatura nova: `NOME*` |
| `ajustes` | Mudança de categoria numa transação `mb:` (`categoria_id` e `category` para o painel) ou exclusão de uma transação `mb:` (`gasto: 0`) | Nunca gera tombstone local |

### D4. Categoria efetiva (seção 6 do spec original) igual no core e no app
- **Ordem:**
  1. ajuste (`categoria_id`; senão `category` antigo do painel, que troca a categoria do Pluggy);
  2. regra (maior `prioridade`, depois o padrão mais longo; respeita `conta_id`);
  3. mapeamento `pluggy[]` de uma categoria;
  4. categoria com o nome traduzido.
- **Passo 4 no Cashew:** cria `mb:cat:d:<nome>` se faltar, como faz hoje.
- **Desvio do spec, por motivo:** o passo 4 do spec era "Sem categoria". O nome traduzido mantém o comportamento que o usuário já usa.
- **Testes:** os casos ficam num JSON compartilhado (`categoria-casos.json`), copiado para os dois repositórios.

### D5. Worker entrega o que o app precisa calcular
- **`GET /api/sync`** ganha:
  - `ciclo`: resumo de `resumoCiclo` e `por_dia`;
  - `sincronizado_em`;
  - contas com `closing_date`;
  - avisos com `item_id`.
- **Motivo:** o ciclo do salário já é calculado no Worker; o app não duplica a regra.

### D6. Notificações no Android sem Firebase
- **Rota nova de aparelho:** `GET /api/notificacoes?desde=<ISO>` (Bearer ou cookie). Devolve `{cursor, notificacoes, resumo}`.
  - Cada aparelho tem o próprio cursor, então dois aparelhos recebem os mesmos alertas.
  - Durante o silêncio (22h–7h BRT), a lista vem vazia e o cursor não anda.
  - Sem `desde` (primeiro uso), devolve lista vazia e o cursor atual, para não despejar os alertas antigos.
- **No app:** `workmanager` (tarefa periódica de 15 min) mostra cada alerta com `flutter_local_notifications` e atualiza o widget com o `resumo`. O Web Push do painel continua como está.

### D7. Pluggy Connect
- **Android:** pacote oficial `flutter_pluggy_connect` (WebView com `connectToken`, `updateItem`, `onSuccess`, `onError` e `onClose`).
  - No sucesso, o app chama `POST /api/pluggy/items` com o id do item.
  - Para reconectar, usa `connect-token` com `itemId` e `updateItem`.
- **Web:** fora desta fase. O botão "Conectar banco" diz "Conecte pelo celular".
- **Motivo:** o webview_flutter não tem implementação web, e o widget JS do Pluggy exigiria abrir a CSP do Worker para cdn.pluggy.ai e connect.pluggy.ai.

### D8. Web em `/app/`, painel antigo fica em `/`
- **Como é servido:** o build web (`--base-href /app/ --no-web-resources-cdn --web-renderer canvaskit --pwa-strategy none`) é copiado para `apps/worker/public/app/`, que fica fora do git. Ele é servido pelo Worker atrás da mesma checagem de cookie de sessão.
- **Autenticação na web:** o app usa a mesma origem e o cookie; sem token. Um 401 manda para `/login?volta=/app/`.
- **Painel antigo:** continua em `/` até o usuário validar o `/app/`.
  - Motivo: ele tem o Web Push, a configuração do ciclo e do limite, e o pareamento por QR.
  - A troca é uma decisão posterior do usuário.
- **CSP só de `/app/`:**
  - acrescenta `'wasm-unsafe-eval'` (CanvasKit e sql.js), `blob:` em `worker-src` e `img-src`, e `font-src 'self' data:`;
  - usa `base-uri 'self'`, porque o Flutter depende de `<base href="/app/">`.
- **Service worker do painel:** passa a ignorar `/app/`.

### D9. Visual
- **Base:** os tokens da seção 8 do spec original, exatos, aplicados nos `ThemeData` claro e escuro do Cashew (`colors.dart`) e numa `ThemeExtension` própria.
- **Padrões novos:**
  - tema "sistema";
  - Material You desligado;
  - acento `#2340D8` no claro e `#8EA4FF` no escuro;
  - fonte Geist;
  - idioma `pt`.
- **Fontes empacotadas** (licença OFL, sem rede em tempo de execução):
  - Geist e Geist Mono;
  - **Source Serif 4 Italic** no lugar de Georgia. Motivos: o CanvasKit não usa fontes do sistema, o Android não tem Georgia, e a licença da Georgia não permite pôr o arquivo no repositório.
- **Movimento:** como na seção 8 do spec original.
  - Curva `Cubic(.23, 1, .32, 1)`.
  - Entrada: 8px com fade, 420ms, escalonada a cada 55ms.
  - Medidor em 900ms; barras escalonadas a cada 28ms; contagem do saldo em 900ms.
  - Toque em .97 por 150ms.
  - Ações de teclado não animam.
  - `MediaQuery.disableAnimations` desliga tudo.

### D10. Versão
- **Formato:** `v<versionName do pubspec> · <dd/mm/aaaa HH:mm>`. A hora vem de `--dart-define=MB_COMPILADO=...`, gerada em America/Sao_Paulo pelos scripts de build e pelo workflow.
- **Onde aparece:**
  - num canto de todas as telas (`IgnorePointer`);
  - no desktop, no rodapé da lateral.
- **Numeração:** o versionName segue a série 5.4.x, porque o atualizador compara o build da tag. `scripts/nova-versao.sh` sem argumento incrementa o PATCH e o build.

### D11. Firebase
- O app não chama mais `Firebase.initializeApp`, e o `web/index.html` não carrega o Firebase do gstatic.
- Os pacotes ficam no pubspec, porque o código de orçamentos compartilhados do upstream os importa. Removê-los é refatoração fora de escopo; eles ficam inertes.

## 3. Fica fora (com motivo)

- **Dividir transação:** o protocolo não tem como representar a divisão de forma que o ciclo e os alertas do Worker entendam. O botão não aparece. Volta numa fase própria, com mudança no core.
- **Pluggy Connect na web:** ver D7.
- **Web Push dentro de `/app/`:** o painel em `/` continua mandando. Em `/app/`, o sino lista os alertas via `GET /api/notificacoes`.
- **Período "ciclo" de orçamento dentro das telas do Cashew:** elas mostram o período mensal. Os alertas de orçamento do Worker usam o ciclo certo.
- **Parcelamentos como dívidas no Cashew:** as parcelas futuras (`scheduled`) não viram transações. O valor comprometido aparece no cartão da Início (`ciclo.parcelasDepois`).
- **Carteiras:** não sincronizam. As contas vêm do banco; uma carteira manual é local e o lançamento leva o nome dela.
- **Detecção automática de assinaturas:** o Cashew mostra as assinaturas confirmadas e as cadastradas. A sugestão a partir das cobranças recorrentes fica para uma fase seguinte.
- **Orçamentos compartilhados, login Google e backup no Drive do Cashew:** continuam fora, como no fork atual.
- **Configuração do ciclo e do limite, pareamento por QR e Web Push:** continuam no painel em `/` nesta fase.

## 4. Fases revisadas

| Fase | Entrega | Pronto quando |
|---|---|---|
| 2. Android (Meu Cashew) | Worker: categoria efetiva no core, `closing_date`, ciclo no pull, alertas novos, `GET /api/notificacoes`. App: sync bidirecional com fila, pareamento por QR, Atualizar, Pluggy Connect, Editorial tinta, Início nova, notificações em segundo plano, widget, versão visível | APK instalado, pareado por QR, edita offline e sincroniza nos dois sentidos, alertas chegando, widget atualizando |
| 3. Web desktop | Build web em `/app/` com cookie, layout de 3 colunas (232/1fr/360), Ctrl+K, detalhe fixo, atalhos, prints aprovados | O usuário valida `/app/` contra `/` |
| 4. Encerramento | Remover `/api/app/transacoes`; apagar o secret `PLUGGY_ITEM_IDS`; decidir se o painel sai de `/` | |

## 5. Riscos novos

- **`flutter_pluggy_connect`:**
  - **Risco:** o formato do `onSuccess` não está tipado (`dynamic`).
  - **O que fazer:** ler `item.id` de forma defensiva e testar com o sandbox do Pluggy antes de usar com um banco real.
  - **Risco:** a versão 3.0.1 pede app_links ^6.3.1.
  - **O que fazer:** conferir que o `flutter pub get` resolve com Flutter 3.24.5.
- **`workmanager` 0.5.2:** o Android pode atrasar a tarefa. Isso é aceito, como no spec original.
- **Build web do fork:** nunca foi gerado nesta branch. A Tarefa 12 começa compilando. Se o CanvasKit falhar, o plano B é `--web-renderer html`, que não precisa de wasm para desenhar.
- **Fonte de fallback do CanvasKit:** é baixada do gstatic, e a CSP bloqueia. Emoji e escrita não latina podem sair como quadrado. É aceito, porque o app usa só português.
- **Primeiro sync de um Cashew com dados antigos:**
  - **Risco:** os objetos locais vão como "novos" com o próprio `dateTimeModified`. Na mesma chave, o servidor fica com o mais novo.
  - **O que fazer:** fazer o backup do Cashew antes do primeiro sync com a versão nova (está nos passos de verificação).

Referências do Pluggy Connect: https://pub.dev/packages/flutter_pluggy_connect, https://docs.pluggy.ai/docs/pluggy-connect-introduction
