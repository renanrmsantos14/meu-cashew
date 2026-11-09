import 'package:budget/main.dart';
import 'package:budget/pages/homePage/painelDesktop.dart';
import 'package:budget/widgets/editorial/buscaRapida.dart';
import 'package:budget/widgets/editorial/detalheTransacao.dart';
import 'package:budget/widgets/editorial/layoutDesktop.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Map<Type, Action<Intent>> keyboardIntents = {
  EscapeIntent: CallbackAction<EscapeIntent>(
    onInvoke: (EscapeIntent intent) => {
      if (navigatorKey.currentState!.canPop())
        navigatorKey.currentState!.pop()
      else if (mbTransacaoSelecionada.value != null)
        mbTransacaoSelecionada.value = null
      else
        pageNavigationFrameworkKey.currentState!
            .changePage(0, switchNavbar: true, animar: false)
    },
  ),
  AbrirBuscaIntent: CallbackAction<AbrirBuscaIntent>(
    onInvoke: (AbrirBuscaIntent intent) => abrirBuscaRapida(),
  ),
  MudarCategoriaIntent: _AcaoDesktop<MudarCategoriaIntent>(
      () => mbAcaoMudarCategoria?.call()),
  VerTransacoesIntent: _AcaoDesktop<VerTransacoesIntent>(
      () => mbIrParaPagina(1)),
  ProximaTransacaoIntent: _AcaoDesktop<ProximaTransacaoIntent>(
      () => mbSelecionarVizinha(1)),
  AnteriorTransacaoIntent: _AcaoDesktop<AnteriorTransacaoIntent>(
      () => mbSelecionarVizinha(-1)),
  AtualizarIntent: CallbackAction<AtualizarIntent>(
    onInvoke: (AtualizarIntent intent) => mbAtualizarComAviso(),
  ),
  Digit1Intent: CallbackAction<Digit1Intent>(
    onInvoke: (Digit1Intent intent) => {
      // we are on the root of navigation pages
      if (!navigatorKey.currentState!.canPop())
        pageNavigationFrameworkKey.currentState!
            .changePage(0, switchNavbar: true, animar: false)
    },
  ),
  Digit2Intent: CallbackAction<Digit2Intent>(
    onInvoke: (Digit2Intent intent) => {
      // we are on the root of navigation pages
      if (!navigatorKey.currentState!.canPop())
        pageNavigationFrameworkKey.currentState!
            .changePage(1, switchNavbar: true, animar: false)
    },
  ),
  Digit3Intent: CallbackAction<Digit3Intent>(
    onInvoke: (Digit3Intent intent) => {
      // we are on the root of navigation pages
      if (!navigatorKey.currentState!.canPop())
        pageNavigationFrameworkKey.currentState!
            .changePage(2, switchNavbar: true, animar: false)
    },
  ),
  Digit4Intent: CallbackAction<Digit4Intent>(
    onInvoke: (Digit4Intent intent) => {
      // we are on the root of navigation pages
      if (!navigatorKey.currentState!.canPop())
        pageNavigationFrameworkKey.currentState!
            .changePage(3, switchNavbar: true, animar: false)
    },
  ),
};

Map<ShortcutActivator, Intent> shortcuts = {
  LogicalKeySet(LogicalKeyboardKey.escape): const EscapeIntent(),
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK):
      const AbrirBuscaIntent(),
  LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyK):
      const AbrirBuscaIntent(),
  LogicalKeySet(LogicalKeyboardKey.keyC): const MudarCategoriaIntent(),
  LogicalKeySet(LogicalKeyboardKey.keyT): const VerTransacoesIntent(),
  LogicalKeySet(LogicalKeyboardKey.keyJ): const ProximaTransacaoIntent(),
  LogicalKeySet(LogicalKeyboardKey.keyK): const AnteriorTransacaoIntent(),
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift,
      LogicalKeyboardKey.keyR): const AtualizarIntent(),
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit1):
      const Digit1Intent(),
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit2):
      const Digit2Intent(),
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit3):
      const Digit3Intent(),
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit4):
      const Digit4Intent(),
};

// Teclas de letra só valem no desktop e fora de campos de texto.
class _AcaoDesktop<T extends Intent> extends CallbackAction<T> {
  _AcaoDesktop(void Function() acao) : super(onInvoke: (_) => acao());

  @override
  bool isEnabled(T intent) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ehDesktop(ctx)) return false;
    final foco = FocusManager.instance.primaryFocus?.context;
    return foco == null ||
        (foco.widget is! EditableText &&
            foco.findAncestorWidgetOfExactType<EditableText>() == null);
  }
}

class AbrirBuscaIntent extends Intent {
  const AbrirBuscaIntent();
}

class MudarCategoriaIntent extends Intent {
  const MudarCategoriaIntent();
}

class VerTransacoesIntent extends Intent {
  const VerTransacoesIntent();
}

class ProximaTransacaoIntent extends Intent {
  const ProximaTransacaoIntent();
}

class AnteriorTransacaoIntent extends Intent {
  const AnteriorTransacaoIntent();
}

class AtualizarIntent extends Intent {
  const AtualizarIntent();
}

class EscapeIntent extends Intent {
  const EscapeIntent();
}

class Digit1Intent extends Intent {
  const Digit1Intent();
}

class Digit2Intent extends Intent {
  const Digit2Intent();
}

class Digit3Intent extends Intent {
  const Digit3Intent();
}

class Digit4Intent extends Intent {
  const Digit4Intent();
}
