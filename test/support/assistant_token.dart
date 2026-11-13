import 'package:apiary/assistant/assistant_model.dart';

/// Токен входу для тестів помічника: завжди той самий.
AssistantTokenSource fixedToken(String token) =>
    ({bool force = false}) async => token;
