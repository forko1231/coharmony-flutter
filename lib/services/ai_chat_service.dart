import '../models/ai_models.dart';
import 'api_client.dart';

/// Port of `Services/AiChatService.cs`. Client for the AI chat backend.
/// Routes/payloads are 1:1 with the C# service and `AiChatController.cs`.
class AiChatService {
  AiChatService(this._api);
  final ApiClient _api;

  Future<AiChatResponse?> sendMessage(
    String message, {
    String context = 'general',
    List<AiChatMessageDto>? conversationHistory,
  }) async {
    final json = await _api.postJson(
      'api/ai/chat',
      AiChatRequestDto(
        message: message,
        context: context,
        conversationHistory: conversationHistory,
      ).toJson(),
    );
    return json is Map<String, dynamic> ? AiChatResponse.fromJson(json) : null;
  }

  Future<AiTokenUsageDto?> getUsage() async {
    final json = await _api.getJson('api/ai/usage');
    return json is Map<String, dynamic> ? AiTokenUsageDto.fromJson(json) : null;
  }
}
