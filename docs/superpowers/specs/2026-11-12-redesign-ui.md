# Redesign da UI do Meu Cashew — brief

## Objetivo
Refazer a UI do app inteiro (47 telas) na direção **C · Saldo em destaque**: minimalista premium, fundo branco/preto neutro, um cartão escuro de saldo como único bloco pesado, listas limpas com divisória de 1 px, números tabulares em Geist, acento único. Celular primeiro; web/computador usa o mesmo sistema em duas colunas.

## Decisões já tomadas
- Direção visual: C (cartão de saldo em destaque). Referência: mock aprovado em 12/11/2026.
- Temas: os 18 temas prontos saem. Ficam claro, escuro e "seguir o sistema", com 4 acentos fixos e contraste testado nos dois modos: verde (padrão), azul, grafite e terracota.
- Animação sutil e funcional: feedback de toque (escala 0,97), transições de tela de 150 a 250 ms com ease-out, números que contam ao mudar e respeito a "reduzir movimento".
- Fontes: Geist (interface e números) e Geist Mono (siglas e porcentagens). A escolha de fonte nas Configurações sai.

## Tokens (claro / escuro)
| token | claro | escuro |
|---|---|---|
| bg | #FFFFFF | #0B0B0C |
| surf | #F6F6F5 | #151516 |
| tx | #111111 | #F2F2F2 |
| mu | #76767A | #8A8A8F |
| line | #EDEDED | rgba(255,255,255,.07) |
| chip | #F2F2F1 | #1C1C1E |
| card (saldo) | #111111 | #1A1A1C |
| acento verde | #2F8F55 | #5CC783 |
| positivo | #2F7A4A | #6FD394 |
| negativo | #B42318 | #F0726B |

Raios: 10 (avatar/chip), 14 (botão/FAB), 20 (cartões). Espaços: 4/8/12/16/20/24/32.

## Contexto técnico
- O tema é centralizado em `lib/struct/temas.dart`: `temaFlutter(TemaPronto)` gera o `ThemeData` e `coresCashew()` gera o `AppColors`, que alimenta cerca de 110 arquivos via `getColor(context, ...)`. A tela Início editorial usa `EditorialCores` (`lib/struct/editorial.dart`).
- Estratégia: trocar a fonte dos tokens nesses dois pontos primeiro. Assim o app inteiro muda por herança. Depois, redesenhar as telas por lotes.

## Fases (uma PR cada)
1. **Design system**: tokens novos e 4 acentos em `temas.dart` e `editorial.dart`; tela Aparência simplificada (modo + acento); componentes base (cartão, linha de lista, botão, FAB, barra inferior, chip, campo, sheet) e curvas/durações de animação.
2. **Início**: cartão de saldo, contas, cartões, últimas e o layout de duas colunas no computador.
3. **Transações e Adicionar transação**.
4. **Orçamentos, Metas e Contas/Carteiras**.
5. **Restante em lotes**: Meu Banco, Investimentos, Configurações, Assinaturas, Busca, Onboarding e as demais telas.

## Verificação
- `flutter analyze` sem erros novos; testes existentes passam.
- Cada fase: capturas de tela no web (`verificar-editorial-web`) em claro e escuro, larguras de 390 e 1280 px.
- Contraste ≥ 4,5:1 em texto e ≥ 3:1 em ícones e barras, nos 4 acentos e nos dois modos.
- Casos de borda: valores grandes (R$ 1.234.567,89) sem quebrar; nome de conta longo com reticências; lista vazia; sem conexão com o Meu Banco (faixa de conexão caída); "reduzir movimento" ligado; usuário que tinha um dos 18 temas salvo cai no claro/escuro com acento verde, sem crash.
- Versão do build visível no canto continua aparecendo.
- `ux-audit` modo Fluxo na Início e no Adicionar transação.
