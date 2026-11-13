---
name: verificar-editorial-web
description: "Verifica o tema Editorial (modos claro/escuro e 4 acentos), a tela Aparência, a Início, o layout desktop, a versão visível e o build web em /app/. Use após mudar budget/lib/struct/editorial.dart, budget/lib/struct/temas.dart, budget/lib/pages/aparenciaPage.dart, budget/lib/widgets/fab.dart, budget/lib/widgets/editorial, budget/lib/pages/homePage, bottomNavBar, navigationFramework, budget/web, pubspec ou scripts."
---
# Verificar Editorial e web

## Cobre
- Código: `budget/lib/struct/editorial.dart`, `budget/lib/widgets/editorial/**`, `budget/lib/pages/homePage/**`, `bottomNavBar.dart`, `navigationFramework.dart`, `budget/web/**`, `scripts/**`.

## Preparar ambiente
- Nuvem/Linux: `export PATH=$HOME/dev/flutter/bin:$PATH`. Windows local: `export PATH=/c/Users/mendo/development/flutter-3.24.5/bin:$PATH` (mesma versão do CI). Depois `cd budget`.
- No Git Bash, `--base-href /app/` vira caminho do Windows: use `MSYS_NO_PATHCONV=1 flutter build web --base-href /app/`.

## Roteiro
1. `flutter test test/temas_test.dart test/temas_app_test.dart test/aparencia_page_test.dart test/editorial_test.dart test/desktop_test.dart test/mb_inicio_test.dart test/versao_test.dart` → todos passam (temas_test cobre contraste ≥ 4,5:1 de cada modo × acento).
2. `flutter analyze` → 0 erros (o restante é aviso herdado do Cashew).
3. `flutter build web --base-href /app/` → "Built build/web".
4. `rg -c "gstatic|firebase" build/web/index.html` → 0 ocorrências (sem Firebase em tempo de execução).
5. UI alterada, sem app pareado: `PRINTS=1 flutter test test/prints_visual_test.dart --update-goldens` gera Início (claro/escuro × verde/terracota), painel desktop e Aparência com fontes reais em `.verificacao/prints/`. Abra os PNGs e confira cartão escuro de saldo, títulos em caixa normal, nada estourado.
6. Telas do app não pareado (Transações, Adicionar, Orçamentos) no navegador real: `node .claude/skills/verificar-editorial-web/shot.mjs budget/build/web .verificacao/<pasta> .claude/skills/verificar-editorial-web/roteiro-basico.json` (playwright-core global + Chromium do ms-playwright; serve `/app/`, ativa a semântica do Flutter e aceita ações `goto`, `clicar` por nome, `xy`, `texto`, `tecla`, `print`, `rotulos`, `contexto` escuro). Toques por coordenada ficam instáveis quando um painel demora; prefira `clicar` por nome e aumente `ms`. Cada `contexto` é um perfil limpo (sem dados).
7. Com app pareado ou fluxo completo: print do estado real (celular 390x844 e desktop 1440x900, claro e escuro) com `playwright-core` sobre `build/web` servido com `--base-href /app/`; a versão `vX.Y.Z · dd/mm/aaaa HH:mm` aparece sem cobrir conteúdo e sem capturar clique.

## Casos de borda
- Computador (≥ 1100 px): "Nova transação" no topo da lateral abre o formulário na coluna 3 (`painelTransacao.dart`); sem botão flutuante. Transações vira tabela (`transacoesDesktop.dart`): clique seleciona e abre o detalhe, 2º clique em até 500 ms ou "Editar" abre o formulário. Teste: `flutter test test/desktop_fluxos_test.dart`.
- Formulário: Enter salva (uma vez só), Esc fecha; com alteração pede "Descartar alterações?"; "1.500" = 1500; transferência/correção de saldo abre a página completa (atualiza o par); edição relê a transação antes de salvar.
- No `shot.mjs`, o Tab do Playwright sai do campo oculto do Flutter web: clique nos campos por posição; categoria se escolhe digitando + seta + Enter.
- Visual plano: `boxShadowGeneral`, `boxShadowSharp` e `boxShadowCategoryPercent` retornam vazio; cartões se separam por `surf` e borda.
- Placeholder de lista vazia (`AddButton` com altura > 80) é uma linha compacta de 56 px com "+ Adicionar …"; empréstimos mostram "add-loan".
- Orçamento sem dados não dá para criar pelo `shot.mjs` com estabilidade (o formulário depende de toques por coordenada); confira o cartão no app pareado ou com o modo demonstração do onboarding.
- Cabeçalho de toda tela é compacto (56 px, título na linha do voltar); telas com subtítulo usam 110. Nada de faixa vazia no topo (preferência explícita do Renan).
- Gasto em cor de texto com sinal −, renda em verde; orçamento estourado usa `overspentAmount` (vermelho).
- Textos pt-BR em caixa de frase ("Selecione a categoria"), não "Cada Palavra Maiúscula".
- Tema antigo salvo (um dos 18 removidos, ex.: `nord`) cai em Sistema sem crash; acento inválido cai em Verde.
- Peso 600 da Geist/GeistMono precisa de arquivo próprio no pubspec (sem `style: italic` perdido); sem ele o texto sai em 500.
- Início vazia e carregando; app não pareado mantém o fluxo original do Cashew; página empilhada no desktop mantém a versão visível.

## Evidência obrigatória
- Tail dos testes e do build web; prints em `.verificacao/<data>-<branch>/`.

## Limites
- `mb_sync_drift_test`, `mb_orcamentos_test`, `mb_revisao_test` e `perf_test` já falham na main nesta máquina (Windows, sincronização local); não são regressão de UI.
- Sem aparelho Android aqui; widget e notificações ficam na `verificar-meu-banco`.
