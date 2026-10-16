import 'assistant_model.dart';

/// Виконання одного інструмента застосунком: результат (коротко, лише
/// потрібне моделі) або помилка (модель про неї дізнається).
typedef ToolRunner = Future<ToolOutcome> Function(String name, Map<String, dynamic> input);

class ToolOutcome {
  final String content;
  final bool isError;
  const ToolOutcome(this.content, {this.isError = false});
}

/// Чим закінчилося одне повідомлення людини.
class AssistantReply {
  final String text;

  /// Модель хотіла ще кроків, але ліміт вичерпано.
  final bool stoppedAtLimit;
  const AssistantReply(this.text, {this.stoppedAtLimit = false});
}

/// Розмова з помічником: історія (лише дописується) і цикл інструментів.
class AssistantSession {
  final AssistantModel model;
  AssistantSession(this.model, {List<Map<String, dynamic>>? history})
      : messages = history ?? [];

  /// Не більше стільки кроків з інструментами на одне повідомлення
  /// (сервер перевіряє те саме).
  static const maxSteps = 6;

  static const limitText = 'Не вийшло відповісти за кілька кроків. Спитайте, будь ласка, простіше.';

  final List<Map<String, dynamic>> messages;

  /// Надіслати повідомлення людини й довести відповідь до кінця.
  /// Помилка зв'язку ([AssistantException]) - повідомлення людини з
  /// історії прибирається (його можна надіслати знову чи з черги).
  Future<AssistantReply> ask(String text, {ToolRunner? tools}) async {
    final start = messages.length;
    messages.add({'role': 'user', 'content': text});
    try {
      var steps = 0;
      while (true) {
        final ModelTurn turn;
        try {
          turn = await model.send(messages);
        } on AssistantException catch (e) {
          if (e.kind == AssistantFailure.stepLimit) return _limit();
          rethrow;
        }
        messages.add({'role': 'assistant', 'content': turn.content});
        final uses = turn.toolUses;
        if (turn.stopReason != 'tool_use' || uses.isEmpty) return AssistantReply(turn.text);
        steps++;
        // усі результати - одним повідомленням (так модель і далі
        // викликатиме інструменти паралельно)
        final results = <Map<String, dynamic>>[];
        for (final u in uses) {
          results.add(await _run(u, tools));
        }
        messages.add({'role': 'user', 'content': results});
        if (steps >= maxSteps) return _limit();
      }
    } on AssistantException {
      messages.removeRange(start, messages.length);
      rethrow;
    }
  }

  // Розмова лишається такою, що далі може писати людина: останнє -
  // відповідь помічника.
  AssistantReply _limit() {
    messages.add({
      'role': 'assistant',
      'content': [
        {'type': 'text', 'text': limitText}
      ],
    });
    return const AssistantReply(limitText, stoppedAtLimit: true);
  }

  Future<Map<String, dynamic>> _run(Map<String, dynamic> use, ToolRunner? tools) async {
    ToolOutcome out;
    if (tools == null) {
      out = const ToolOutcome('Інструмент недоступний', isError: true);
    } else {
      try {
        out = await tools(
            use['name'] as String, Map<String, dynamic>.from(use['input'] as Map? ?? const {}));
      } catch (_) {
        out = const ToolOutcome('Не вдалося виконати', isError: true);
      }
    }
    return {
      'type': 'tool_result',
      'tool_use_id': use['id'],
      'content': out.content,
      if (out.isError) 'is_error': true,
    };
  }
}
