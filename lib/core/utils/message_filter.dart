/// Utility for filtering chat messages before display in the session chat view.
///
/// Hermes sessions accumulate many internal messages that are not useful to an
/// end-user reading a conversation: tool-call results, empty placeholders,
/// model thinking/reasoning blocks, and context-compression summaries. This
/// filter removes them and keeps only the human-readable conversation turns.
import 'dart:convert';

class MessageFilter {
  /// Default maximum number of messages to show after filtering.
  static const int defaultMaxMessages = 10;

  /// Filter, clean, and truncate [messages] for display.
  ///
  /// The pipeline has three stages:
  /// 1. **Filter** — drop tool results, empty content, pure-think messages,
  ///    context-compression artifacts, and live tool-progress placeholders.
  /// 2. **Clean** — strip `<think>…</think>` reasoning blocks from any
  ///    remaining message, then drop messages that became empty afterwards.
  /// 3. **Truncate** — keep only the last [maxMessages] entries.
  static List<Map<String, dynamic>> filterForDisplay(
    List<Map<String, dynamic>> messages, {
    int maxMessages = defaultMaxMessages,
  }) {
    // ── Stage 1: filter out unwanted message types ──
    final filtered = messages.where((msg) {
      final role = (msg['role'] as String?) ?? '';
      final content = (msg['content']?.toString() ?? '').trim();

      // Tool result messages (OpenAI format: role == "tool" + tool_call_id)
      if (role == 'tool') return false;
      if (msg.containsKey('tool_call_id')) return false;

      // Live tool-progress placeholders inserted during streaming
      if (role == 'tool_progress') return false;

      // Empty messages (null, empty, or whitespace-only content)
      // except: keep messages with tool_calls — they show what the agent is doing
      if (content.isEmpty &&
          (msg['tool_calls'] == null && msg['response_item_id'] == null)) {
        return false;
      }

      // Messages whose content is entirely a <think> reasoning block
      if (_isEntirelyThinkContent(content)) return false;

      // Context-compression / summarization artifacts
      if (_isContextCompression(role, content, msg)) return false;

      return true;
    }).toList();

    // ── Stage 2: strip <think> blocks and re-check emptiness ──
    final cleaned = <Map<String, dynamic>>[];
    for (final msg in filtered) {
      final content = msg['content']?.toString() ?? '';
      final stripped = _stripThinkTags(content).trim();
      final hasToolCalls = msg['tool_calls'] != null;
      if (stripped.isEmpty && !hasToolCalls) continue; // became empty after stripping, no tool info
      cleaned.add({
        ...msg,
        'content': stripped.isEmpty && hasToolCalls
            ? _toolCallsLabel(msg['tool_calls'])
            : stripped,
      });
    }

    // ── Stage 3: keep only the latest N messages ──
    if (cleaned.length > maxMessages) {
      return cleaned.sublist(cleaned.length - maxMessages);
    }
    return cleaned;
  }

  // ── Private helpers ──────────────────────────────────────────────────

  /// Extract a human-readable display label from tool_calls.
  /// [toolCalls] may be a List<Map> or a JSON-encoded String.
  static String _toolCallsLabel(Object? toolCalls) {
    List<Object?>? calls;
    try {
      if (toolCalls is List<Object?>) {
        calls = toolCalls;
      } else if (toolCalls is String) {
        final decoded = jsonDecode(toolCalls);
        if (decoded is List) {
          calls = decoded.cast<Object?>();
        }
      }
      if (calls != null && calls.isNotEmpty) {
        final first = calls.first;
        if (first is Map) {
          final name = first['function']?['name'] ?? first['name'] ?? 'tool';
          return '🔧 ${name}';
        }
      }
    } catch (_) {
      // not a valid JSON List — return default label below
    }
    return '🔧 tool';
  }

  /// True when [content] starts with `<think>` and contains nothing outside
  /// the think block (handles both closed and unclosed tags from streaming).
  static bool _isEntirelyThinkContent(String content) {
    final trimmed = content.trim();
    if (!trimmed.toLowerCase().startsWith('<think>')) return false;
    final closeIndex = trimmed.toLowerCase().indexOf('</think>');
    if (closeIndex == -1) return true; // unclosed — all think
    final afterClose = trimmed.substring(closeIndex + '</think>'.length).trim();
    return afterClose.isEmpty;
  }

  /// Remove all `<think>…</think>` blocks (case-insensitive).
  /// Also removes trailing unclosed `<think>` blocks (streaming artifacts).
  static String _stripThinkTags(String content) {
    // Closed blocks: <think> ... </think>
    var result = content.replaceAll(
      RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
      '',
    );
    // Trailing unclosed block: <think> ... (to end of string)
    result = result.replaceAll(
      RegExp(r'<think>[\s\S]*$', caseSensitive: false),
      '',
    );
    return result;
  }

  /// Detect context-compression / conversation-summarization messages.
  static bool _isContextCompression(
    String role,
    String content,
    Map<String, dynamic> msg,
  ) {
    // System messages containing compression markers
    if (role == 'system') {
      final lower = content.toLowerCase();
      const markers = [
        'context compress',
        'context compression',
        'conversation summary',
        'context window',
        'summary of previous',
        'compacted conversation',
        'truncated conversation',
        'previous messages were compressed',
      ];
      for (final marker in markers) {
        if (lower.contains(marker)) return true;
      }
    }

    // Explicit metadata flags
    if (msg['type'] == 'compression' ||
        msg['type'] == 'context_compress' ||
        msg['metadata']?['compressed'] == true) {
      return true;
    }

    return false;
  }
}
