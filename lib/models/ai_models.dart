// DTOs for the AI-chat domain. 1:1 with `Services/AiChatService.cs` (explicit
// camelCase [JsonPropertyName]). Tool-call argument models are deserialized from
// the `arguments` JSON string the AI returns, then used by the chat UI to apply
// the requested action.

double? _dblN(dynamic v) => v == null ? null : (v as num).toDouble();
double _dbl(dynamic v) => v == null ? 0 : (v as num).toDouble();
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

Map<String, dynamic> _stripNulls(Map<String, dynamic> m) {
  m.removeWhere((_, v) => v == null);
  return m;
}

class AiChatMessageDto {
  AiChatMessageDto({this.role = 'user', this.content = ''});
  final String role;
  final String content;
  Map<String, dynamic> toJson() => {'role': role, 'content': content};
  factory AiChatMessageDto.fromJson(Map<String, dynamic> j) => AiChatMessageDto(
        role: j['role'] as String? ?? 'user',
        content: j['content'] as String? ?? '',
      );
}

class AiChatRequestDto {
  AiChatRequestDto({
    this.message = '',
    this.context = 'general',
    this.conversationHistory,
  });
  final String message;
  final String context;
  final List<AiChatMessageDto>? conversationHistory;
  Map<String, dynamic> toJson() => _stripNulls({
        'message': message,
        'context': context,
        'conversationHistory':
            conversationHistory?.map((m) => m.toJson()).toList(),
      });
}

class AiToolCallDto {
  AiToolCallDto({this.functionName = '', this.arguments = '{}'});
  final String functionName;
  final String arguments;
  factory AiToolCallDto.fromJson(Map<String, dynamic> j) => AiToolCallDto(
        functionName: j['functionName'] as String? ?? '',
        arguments: j['arguments'] as String? ?? '{}',
      );
}

class AiChatResponse {
  AiChatResponse({
    this.message = '',
    this.toolCalls,
    this.tokensUsed = 0,
    this.monthlyTokensUsed = 0,
    this.monthlySpend = 0,
    this.monthlyBudget = 0,
    this.limitReached = false,
    this.rateLimited = false,
  });
  final String message;
  final List<AiToolCallDto>? toolCalls;
  final int tokensUsed;
  final int monthlyTokensUsed;
  final double monthlySpend;
  final double monthlyBudget;
  final bool limitReached;
  final bool rateLimited;
  factory AiChatResponse.fromJson(Map<String, dynamic> j) => AiChatResponse(
        message: j['message'] as String? ?? '',
        toolCalls: (j['toolCalls'] as List<dynamic>?)
            ?.map((e) => AiToolCallDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        tokensUsed: (j['tokensUsed'] as num?)?.toInt() ?? 0,
        monthlyTokensUsed: (j['monthlyTokensUsed'] as num?)?.toInt() ?? 0,
        monthlySpend: _dbl(j['monthlySpend']),
        monthlyBudget: _dbl(j['monthlyBudget']),
        limitReached: j['limitReached'] as bool? ?? false,
        rateLimited: j['rateLimited'] as bool? ?? false,
      );
}

class AiTokenUsageDto {
  AiTokenUsageDto({
    this.monthlyTokensUsed = 0,
    this.monthlySpend = 0,
    this.monthlyBudget = 0,
    this.resetDate,
  });
  final int monthlyTokensUsed;
  final double monthlySpend;
  final double monthlyBudget;
  final DateTime? resetDate;
  factory AiTokenUsageDto.fromJson(Map<String, dynamic> j) => AiTokenUsageDto(
        monthlyTokensUsed: (j['monthlyTokensUsed'] as num?)?.toInt() ?? 0,
        monthlySpend: _dbl(j['monthlySpend']),
        monthlyBudget: _dbl(j['monthlyBudget']),
        resetDate: _date(j['resetDate']),
      );
}

// ---- Tool-call argument models ------------------------------------------

class PatternDayArg {
  PatternDayArg({
    this.weekIndex = 0,
    this.dayIndex = 0,
    this.parentAssignment = 'None',
    this.transferTime,
    this.transferEndTime,
    this.locationName,
    this.locationAddress,
    this.latitude,
    this.longitude,
  });
  final int weekIndex;
  final int dayIndex;
  final String parentAssignment;
  final String? transferTime;
  final String? transferEndTime;
  final String? locationName;
  final String? locationAddress;
  final double? latitude;
  final double? longitude;
  factory PatternDayArg.fromJson(Map<String, dynamic> j) => PatternDayArg(
        weekIndex: (j['weekIndex'] as num?)?.toInt() ?? 0,
        dayIndex: (j['dayIndex'] as num?)?.toInt() ?? 0,
        parentAssignment: j['parentAssignment'] as String? ?? 'None',
        transferTime: j['transferTime'] as String?,
        transferEndTime: j['transferEndTime'] as String?,
        locationName: j['locationName'] as String?,
        locationAddress: j['locationAddress'] as String?,
        latitude: _dblN(j['latitude']),
        longitude: _dblN(j['longitude']),
      );
}

class SetCustodyPatternArgs {
  SetCustodyPatternArgs({this.patternLengthWeeks = 0, this.days = const []});
  final int patternLengthWeeks;
  final List<PatternDayArg> days;
  factory SetCustodyPatternArgs.fromJson(Map<String, dynamic> j) => SetCustodyPatternArgs(
        patternLengthWeeks: (j['patternLengthWeeks'] as num?)?.toInt() ?? 0,
        days: (j['days'] as List<dynamic>? ?? [])
            .map((e) => PatternDayArg.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AddOverrideDayArgs {
  AddOverrideDayArgs({
    this.month = 0,
    this.day = 0,
    this.parentAssignment = 'None',
    this.label = '',
    this.holidayRule,
    this.transferTime,
    this.transferEndTime,
    this.isAnnual = true,
    this.alternationMode,
    this.alternationStartParent,
    this.locationName,
    this.locationAddress,
    this.latitude,
    this.longitude,
  });
  final int month;
  final int day;
  final String parentAssignment;
  final String label;
  final String? holidayRule;
  final String? transferTime;
  final String? transferEndTime;
  final bool isAnnual;
  final String? alternationMode;
  final String? alternationStartParent;
  final String? locationName;
  final String? locationAddress;
  final double? latitude;
  final double? longitude;
  factory AddOverrideDayArgs.fromJson(Map<String, dynamic> j) => AddOverrideDayArgs(
        month: (j['month'] as num?)?.toInt() ?? 0,
        day: (j['day'] as num?)?.toInt() ?? 0,
        parentAssignment: j['parentAssignment'] as String? ?? 'None',
        label: j['label'] as String? ?? '',
        holidayRule: j['holidayRule'] as String?,
        transferTime: j['transferTime'] as String?,
        transferEndTime: j['transferEndTime'] as String?,
        isAnnual: j['isAnnual'] as bool? ?? true,
        alternationMode: j['alternationMode'] as String?,
        alternationStartParent: j['alternationStartParent'] as String?,
        locationName: j['locationName'] as String?,
        locationAddress: j['locationAddress'] as String?,
        latitude: _dblN(j['latitude']),
        longitude: _dblN(j['longitude']),
      );
}

class CreateEventArgs {
  CreateEventArgs({
    this.title = '',
    this.month = 0,
    this.day = 0,
    this.year = 0,
    this.startTime = '',
    this.endTime = '',
    this.repeatType = 'none',
    this.endDate,
    this.notes,
  });
  final String title;
  final int month;
  final int day;
  final int year;
  final String startTime;
  final String endTime;
  final String repeatType;
  final String? endDate;
  final String? notes;
  factory CreateEventArgs.fromJson(Map<String, dynamic> j) => CreateEventArgs(
        title: j['title'] as String? ?? '',
        month: (j['month'] as num?)?.toInt() ?? 0,
        day: (j['day'] as num?)?.toInt() ?? 0,
        year: (j['year'] as num?)?.toInt() ?? 0,
        startTime: j['startTime'] as String? ?? '',
        endTime: j['endTime'] as String? ?? '',
        repeatType: j['repeatType'] as String? ?? 'none',
        endDate: j['endDate'] as String?,
        notes: j['notes'] as String?,
      );
}

class DraftMessageArgs {
  DraftMessageArgs({this.messageText = '', this.subject = ''});
  final String messageText;
  final String subject;
  factory DraftMessageArgs.fromJson(Map<String, dynamic> j) => DraftMessageArgs(
        messageText: j['messageText'] as String? ?? '',
        subject: j['subject'] as String? ?? '',
      );
}

class SelectTemplateArgs {
  SelectTemplateArgs({this.templateId = '', this.answers});
  final String templateId;
  final Map<String, String>? answers;
  factory SelectTemplateArgs.fromJson(Map<String, dynamic> j) => SelectTemplateArgs(
        templateId: j['templateId'] as String? ?? '',
        answers: (j['answers'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v.toString())),
      );
}
