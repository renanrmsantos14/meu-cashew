---
name: verificar-meu-banco
description: "Verifica o sync Meu Banco do app (LWW, pareamento por QR e deep link meubanco://, Pluggy, alertas em segundo plano, widget). Use após mudar budget/lib/struct/mbSync, budget/lib/struct/meuBanco*.dart, budget/lib/pages/meuBanco*.dart, appLinks.dart ou budget/android, ou quando pedirem para testar o sync."
---
# Verificar Meu Banco

## Cobre
- Código: `budget/lib/struct/mbSync/**`, `budget/lib/struct/meuBancoSync.dart`, `meuBancoMapping.dart`, `budget/lib/struct/mbSync/revisao.dart` (fila "Para revisar"), `budget/lib/struct/mbSync/emprestimos.dart`, `budget/lib/struct/mbSync/reembolso.dart`, `budget/lib/pages/homePage/homePageParaRevisar.dart`, `budget/lib/pages/homePage/homePageEmprestimos.dart`, `budget/lib/struct/mbSync/orcamentos.dart` (orçamentos, ciclo, alerta 80/100), `estadoInicio.dart`, `inicioOrdem.dart`, `budget/lib/pages/homePage/homePageOrcamentoPadrao.dart`, `homePageFaturaPatrimonio.dart`, `budget/lib/pages/meuBancoPage.dart`, `meuBancoParear.dart`, `meuBancoConectar.dart`, `budget/lib/widgets/util/appLinks.dart`, manifest e widget Android.
- Schema do Drift continua em 46: as tabelas `mb_registros`, `mb_estado`, `mb_aplicado` e `mb_orcamento_tx` nascem por `mbCriarTabelas()`, fora do Drift.

## Preparar ambiente
- `export PATH=$HOME/dev/flutter/bin:$PATH JAVA_HOME=$HOME/dev/jdk17 ANDROID_HOME=$HOME/Android/Sdk` e `cd budget`.
- Sem rede nem token real: os testes usam cliente falso e Drift em memória.

## Roteiro
1. `flutter test test/mb_sync_nucleo_test.dart test/mb_sync_drift_test.dart test/mb_pareamento_test.dart test/mb_pluggy_test.dart test/mb_segundo_plano_test.dart test/mb_mapeamento_test.dart test/meu_banco_mapping_test.dart test/mb_revisao_test.dart test/mb_emprestimos_test.dart test/mb_orcamentos_test.dart test/mb_conexao_caida_test.dart` → todos passam.
2. `flutter analyze lib/struct/mbSync lib/struct/meuBancoSync.dart lib/pages` → sem erros novos.
3. Se tocou em Android: `flutter build apk --debug` → "Built build/app/outputs/flutter-apk/app-debug.apk".
4. Segurança (leitura do diff): token só em `flutter_secure_storage`, nunca em `appStateSettings`; `meubanco://parear` só grava depois de `mbConfirmarEParear`; origem só https (http só em debug para localhost/10.0.2.2); toda entrada manual de token/endereço passa pelo mesmo caminho do QR.

## Casos de borda
- Troca de conta apaga espelho, fila, estado, `mb:` importado, carteiras e categorias `mb:` sem uso, e preserva o que nasceu no Cashew.
- Registro remoto mais velho não sobrescreve o espelho; exclusão local vira tombstone.
- Token inválido (401) e limite de 30 min (429) mostram mensagem fixa em pt-BR.

- Fila "Para revisar": a decisão vai em `revisoes` (id `tx:<id>` e `dest:<NOME>`), remapeia por re-pull completo e nunca gera `ajustes`; Santander só é gasto com resposta `ajuda`; Pix recebido decidido nunca vira salário nem estorno automático. Print da Início (390x844 e 1440x900) com o cartão: build web, `python3 -m http.server`, Playwright; dados simulados só temporários.
- Empréstimos ao pai: derivados das decisões `emprestimo`/`devolucao` (sem transação nem ajuste); devolução abate FIFO cronológico, excedente é descartado; o bloco "Empréstimos em aberto" some sem nenhum aberto. Reembolso: a folha de sugestão (gastos de 15 dias, igual/próximo primeiro, mais recentes antes) grava `reembolso_de` na decisão; sem escolha, abate em "Outros". Print da Início com o bloco e da folha de sugestão (390x844).

- Orçamentos: modelo "todas as transações" + `mb_orcamento_tx` (sem linhas = Geral; com linhas = só os escolhidos; `''` = nenhum); período = ciclo do Worker (`mbCicloCache`, só orçamento mensal de 1 período não compartilhado); o app envia `periodo: 'ciclo'`; escolha sobe como `orcamento_ids` em `lancamentos` e `ajustes` e nunca gera ajuste/gasto 0 sozinha; apagar orçamento ou transação limpa as linhas. Não contam: transferência, empréstimo, investimento (ajuste de saldo), fatura, renda; estorno e reembolso abatem. Alerta: `mbAlertaOrcamento` (arquivo `orcamentos.dart`) devolve `oitenta`/`cem` só ao cruzar o limiar.
- Início: ordem padrão Orçamento padrão, Para revisar, Fatura do cartão, Patrimônio, Metas, Empréstimos, Transações (`mbOrdemInicio`); `mbMigrarOrdemInicio` só troca a ordem padrão antiga e não mexe em ordem personalizada. Print da Início (390x844 fullPage e 1440x900) e da escolha de orçamentos numa transação; no web o sync apaga investimentos simulados, então insira-os depois do sync no seed temporário.

- Notificações (PR 7): `mbConferirAlertas` entrega cada alerta com `chave`, `titulo`, `corpo` e `item`; `mbAcoesDoAlerta` cria os botões das respostas do item (reembolso abre o app); `mbResponderPelaNotificacao` responde a fila e ignora item que já saiu dela; o toque simples abre a Início. A faixa `HomePageConexaoCaida` (topo da Início) lê `avisos` e tem "Reconectar" (`mbAbrirConnect(itemId:)`). Print da faixa (390x844): web build, `python3 -m http.server`, Playwright, `avisos` simulados só no print. Botões, 7h e Reconectar real só em aparelho.

## Evidência obrigatória
- Tail da saída de `flutter test` (todos passando) e de `flutter analyze`.

## Limites
- Pareamento com câmera, Pluggy Connect, workmanager e widget só em aparelho; nada de produção (`wrangler`, `pnpm push`).
