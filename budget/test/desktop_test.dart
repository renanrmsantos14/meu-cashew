import 'dart:io';
import 'package:budget/database/tables.dart';
import 'package:budget/pages/homePage/painelDesktop.dart';
import 'package:budget/struct/editorial.dart';
import 'package:budget/struct/mbSync/estadoInicio.dart';
import 'package:budget/widgets/editorial/versaoCanto.dart';
import 'package:budget/struct/keyboardIntents.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/editorial/buscaRapida.dart';
import 'package:budget/widgets/editorial/detalheTransacao.dart';
import 'package:budget/widgets/editorial/lateralEditorial.dart';
import 'package:budget/widgets/editorial/layoutDesktop.dart';
import 'package:budget/widgets/navigationFramework.dart' show navigatorKey;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<DetalheModelo?> _detalhe(String pk) async => DetalheModelo(
      pk: pk,
      nome: 'IFOOD *PEDIDO',
      conta: 'Nubank',
      categoria: 'Alimentação',
      data: DateTime(2026, 11, 8),
      valor: 42.5,
      receita: false,
    );

Future<void> _montar(WidgetTester t, Size tamanho,
    {Future<void> Function(DetalheModelo)? aoMudar, Widget? conteudo}) async {
  t.view.physicalSize = tamanho;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    navigatorKey: navigatorKey,
    theme: temaEditorial(Brightness.light),
    shortcuts: shortcuts,
    actions: keyboardIntents,
    home: Builder(
      builder: (context) => ehDesktop(context)
          ? LayoutDesktop(
              lateral: const LateralEditorial.comDados(contas: []),
              conteudo: conteudo ??
                  const Focus(autofocus: true, child: SizedBox.expand()),
              carregarDetalhe: _detalhe,
              aoMudarCategoria: aoMudar,
            )
          : const Scaffold(
              body: SizedBox.expand(),
              bottomNavigationBar: SizedBox(key: Key('barra'), height: 56)),
    ),
  ));
  await t.pump();
}

Future<void> _fonte(String fam, List<String> arqs) async {
  final l = FontLoader(fam);
  for (final a in arqs) {
    l.addFont(Future.value(
        ByteData.sublistView(File('assets/fonts/$a').readAsBytesSync())));
  }
  await l.load();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _fonte('Geist', ['Geist-Regular.ttf', 'Geist-Medium.ttf']);
    await _fonte('GeistMono', ['GeistMono-Regular.ttf']);
  });

  setUp(() {
    mbTransacaoSelecionada.value = null;
    appStateSettings = {
      "materialYou": false,
      "accentSystemColor": false,
      "batterySaver": false,
      "outlinedIcons": false,
      "increaseTextContrast": false,
      "forceFullDarkBackground": false,
    };
  });

  testWidgets('lateral com marca e versão', (t) async {
    await _montar(t, const Size(1280, 800));
    expect(find.text('Meu Banco'), findsOneWidget);
    expect(find.textContaining('· dev'), findsOneWidget);
    expect(
        t
            .getSize(find
                .ancestor(
                    of: find.byType(LateralEditorial),
                    matching: find.byType(Container))
                .first)
            .width,
        mbLarguraLateral);
  });

  testWidgets('itens da lateral são botões acessíveis com nome', (t) async {
    final semantica = t.ensureSemantics();
    await _montar(t, const Size(1280, 800));
    for (final nome in ['Início', 'Transações', 'Orçamentos', 'Metas']) {
      final no = t.getSemantics(find.bySemanticsLabel(nome));
      expect(no.hasFlag(SemanticsFlag.isButton), isTrue, reason: nome);
      expect(no.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
          reason: nome);
    }
    semantica.dispose();
  });

  testWidgets('rota empilhada no conteúdo não esconde a lateral do leitor',
      (t) async {
    final semantica = t.ensureSemantics();
    final nav = GlobalKey<NavigatorState>();
    await _montar(t, const Size(1280, 800),
        conteudo: Navigator(
            key: nav,
            onGenerateRoute: (_) =>
                MaterialPageRoute(builder: (_) => const SizedBox.expand())));
    nav.currentState!
        .push(MaterialPageRoute(builder: (_) => const SizedBox.expand()));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('Transações'), findsOneWidget);
    semantica.dispose();
  });

  testWidgets('selecionar transação abre detalhe de 360', (t) async {
    await _montar(t, const Size(1280, 800));
    expect(find.byType(DetalheTransacao), findsNothing);
    mbTransacaoSelecionada.value = 'x';
    await t.pump();
    await t.pump();
    expect(find.byType(DetalheTransacao), findsOneWidget);
    expect(
        t
            .getSize(find
                .ancestor(
                    of: find.byType(DetalheTransacao),
                    matching: find.byType(Container))
                .first)
            .width,
        mbLarguraDetalhe);
    expect(find.text('IFOOD *PEDIDO'), findsWidgets);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(mbTransacaoSelecionada.value, isNull);
  });

  testWidgets('Ctrl+K abre a busca sem animação e Esc fecha', (t) async {
    await _montar(t, const Size(1280, 800));
    await t.sendKeyDownEvent(LogicalKeyboardKey.control);
    await t.sendKeyEvent(LogicalKeyboardKey.keyK);
    await t.sendKeyUpEvent(LogicalKeyboardKey.control);
    await t.pump();
    expect(find.byType(BuscaRapida), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(find.byType(BuscaRapida), findsNothing);
  });

  testWidgets('C com detalhe aberto aciona a troca de categoria', (t) async {
    var chamadas = 0;
    await _montar(t, const Size(1280, 800), aoMudar: (_) async => chamadas++);
    mbTransacaoSelecionada.value = 'x';
    await t.pump();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.keyC);
    await t.pump();
    expect(chamadas, 1);
  });

  testWidgets('390x844 sem lateral e com barra inferior', (t) async {
    await _montar(t, const Size(390, 844));
    expect(find.byType(LateralEditorial), findsNothing);
    expect(find.byKey(const Key('barra')), findsOneWidget);
  });

  TransacaoInicio linha(String pk, String nome) => (
        category: TransactionCategory(
            categoryPk: 'c',
            name: 'Mercado',
            dateCreated: DateTime(2026),
            dateTimeModified: null,
            order: 0,
            income: false,
            methodAdded: null),
        transaction: Transaction(
            transactionPk: pk,
            name: nome,
            amount: -10,
            note: '',
            categoryFk: 'c',
            walletFk: '0',
            dateCreated: DateTime(2026, 11, 8),
            income: false,
            paid: true,
            skipPaid: false,
            createdAnotherFutureTransaction: false,
            type: null,
            methodAdded: null,
            reoccurrence: null,
            endDate: null,
            periodLength: null,
            dateTimeModified: null,
            originalDateDue: null,
            sharedKey: null,
            sharedOldKey: null,
            sharedStatus: null,
            sharedDateUpdated: null,
            sharedReferenceBudgetPk: null,
            objectiveFk: null,
            objectiveLoanFk: null,
            upcomingTransactionNotification: null,
            subCategoryFk: null,
            transactionOwnerEmail: null,
            transactionOriginalOwnerEmail: null),
      );

  final modelo = ModeloInicio(
      ciclo: 'Ciclo 26 out – 25 nov',
      saudacao: 'Olá, Renan',
      disponivel: 18432.5,
      origemDisponivel: 'Nubank',
      consumido: 6120,
      limite: 9000,
      percentual: 68,
      diasRestantes: 16,
      porDia: [for (var i = 0; i < 31; i++) 100.0 + i],
      indiceHoje: 14,
      contas: const [],
      cartoes: const [
        (
          nome: 'Nubank',
          final4: '4321',
          diasFecha: 5,
          vence: '15 nov',
          fatura: 3120.0,
          limite: 8000.0,
          pct: 39.0
        )
      ],
      ultimas: const []);

  Future<void> montarPainel(WidgetTester t, Size tamanho) async {
    t.view.physicalSize = tamanho;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      theme: temaEditorial(Brightness.light),
      shortcuts: shortcuts,
      actions: keyboardIntents,
      home: LayoutDesktop(
        lateral: const LateralEditorial.comDados(contas: []),
        carregarDetalhe: _detalhe,
        conteudo: PainelDesktop.comDados(modelo, transacoes: [
          linha('a', 'MERCADO A'),
          linha('b', 'PADARIA B')
        ], orcamentos: const [
          (nome: 'Mercado', gasto: 812.0, limite: 1400.0)
        ]),
      ),
    ));
    await t.pump();
  }

  testWidgets('painel a 1100px com detalhe aberto não estoura', (t) async {
    await montarPainel(t, const Size(1100, 700));
    mbTransacaoSelecionada.value = 'a';
    await t.pump();
    await t.pump();
    expect(find.byType(DetalheTransacao), findsOneWidget);
    expect(
        find.text('Últimas transações', skipOffstage: false), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('J/K percorrem as transações do painel', (t) async {
    await montarPainel(t, const Size(1280, 800));
    await t.sendKeyEvent(LogicalKeyboardKey.keyJ);
    expect(mbTransacaoSelecionada.value, 'a');
    await t.sendKeyEvent(LogicalKeyboardKey.keyJ);
    expect(mbTransacaoSelecionada.value, 'b');
    await t.sendKeyEvent(LogicalKeyboardKey.keyK);
    expect(mbTransacaoSelecionada.value, 'a');
    await t.pump();
    // Fora do Início (lista antiga) J/K não mexem na seleção.
    mbPaginaAtual.value = 1;
    await t.sendKeyEvent(LogicalKeyboardKey.keyJ);
    expect(mbTransacaoSelecionada.value, 'a');
    mbPaginaAtual.value = 0;
  });

  testWidgets('letras não valem com rota empilhada', (t) async {
    await montarPainel(t, const Size(1280, 800));
    navigatorKey.currentState!.push(MaterialPageRoute(
        builder: (_) =>
            const Scaffold(body: Focus(autofocus: true, child: SizedBox()))));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.keyJ);
    expect(mbTransacaoSelecionada.value, isNull);
  });

  testWidgets('versão do canto reaparece com página empilhada no desktop',
      (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: temaEditorial(Brightness.light),
      navigatorObservers: [ObservadorPaginas()],
      builder: (context, child) => VersaoCanto(child: child!),
      home: const Scaffold(body: SizedBox.expand()),
    ));
    await t.pump();
    expect(find.textContaining('· dev'), findsNothing);
    final nav = t.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute(builder: (_) => const Scaffold()));
    await t.pumpAndSettle();
    expect(find.textContaining('· dev'), findsOneWidget);
    nav.pop();
    await t.pumpAndSettle();
    expect(find.textContaining('· dev'), findsNothing);
  });
}
