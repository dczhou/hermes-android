import 'dart:convert';

/// Utility for filtering chat messages before display in the session chat view.
class MessageFilter {
  /// Default maximum number of messages to show after filtering.
  ///
  /// Sessions can have hundreds of messages; a small window meant past turns
  /// would silently disappear the moment the conversation filled up. 30 keeps
  /// the most recent user/assistant exchanges visible while leaving the older
  /// history accessible via "Load older" in ChatScreen.
  static const int defaultMaxMessages = 30;

  /// When assistant-side tool-call bubble placeholders appear consecutively,
  /// collapse them into a single bubble. Set this to 1 to disable folding.
  static const int toolGroupFoldThreshold = 3;

  /// Filter, clean, and truncate [messages] for display.
  ///
  /// The pipeline has four stages:
  /// 1. **Filter** — drop tool results, empty content, pure-think messages,
  ///    context-compression artifacts (across every role), and live
  ///    tool-progress placeholders.
  /// 2. **Clean** — strip `<think>…</think>` reasoning blocks from any
  ///    remaining message, then drop messages that became empty afterwards.
  /// 3. **Fold** — collapse runs of consecutive assistant tool-call labels
  ///    (`🔧 X`) into a single `(N tool calls (…))` summary bubble so a long
  ///    chain of agent actions doesn't crowd out the surrounding conversation.
  /// 4. **Truncate** — keep only the last [maxMessages] entries.
  static List<Map<String, dynamic>> filterForDisplay(
    List<Map<String, dynamic>> messages, {
    int maxMessages = defaultMaxMessages,
    int toolFoldThreshold = toolGroupFoldThreshold,
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

      // Context-compression / summarization artifacts (any role)
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

    // ── Stage 3: collapse consecutive tool-call labels into a summary bubble ──
    final folded = _foldConsecutiveToolLabels(
      cleaned,
      threshold: toolFoldThreshold,
    );

    // ── Stage 4: keep only the latest N messages ──
    if (folded.length > maxMessages) {
      return folded.sublist(folded.length - maxMessages);
    }
    return folded;
  }

  // ── Private helpers ──────────────────────────────────────────────────

  /// Extract a human-readable display label from tool_calls.
  /// [toolCalls] may be a List<Map> or a JSON-encoded String.
  static String _toolCallsLabel(Object? toolCalls) {
    final names = _toolCallNames(toolCalls);
    if (names.isNotEmpty) {
      return '🔧 ${names.first}';
    }
    return '🔧 tool';
  }

  /// Extract ordered tool names from a tool_calls payload.
  /// Returns an empty list if anything goes wrong.
  static List<String> _toolCallNames(Object? toolCalls) {
    List<Object?>? calls;
    try {
      if (toolCalls is List<Object?>) {
        calls = toolCalls;
      } else if (toolCalls is String) {
        final decoded = jsonDecode(toolCalls);
        if (decoded is List<Object?>) {
          calls = decoded;
        }
      }
      if (calls == null) return const <String>[];
      return calls
          .whereType<Map<dynamic, dynamic>>()
          .map((c) => (c['function']?['name'] ?? c['name'] ?? 'tool').toString())
          .toList();
    } catch (_) {
      return const <String>[];
    }
  }

  /// Collapse runs of [threshold] or more consecutive assistant tool-call
  /// bubble placeholders (`🔧 X`) into a single summary bubble. Short runs
  /// (1 or 2 stand-alone tool calls) are preserved verbatim so the reader can
  /// still see what just happened.
  static List<Map<String, dynamic>> _foldConsecutiveToolLabels(
    List<Map<String, dynamic>> messages, {
    int threshold = toolGroupFoldThreshold,
  }) {
    if (threshold <= 1) return messages;

    bool isToolLabelBubble(Map<String, dynamic> m) {
      final role = m['role'] as String?;
      final content = (m['content'] as String?) ?? '';
      return role == 'assistant' &&
          m['tool_calls'] != null &&
          content.startsWith('🔧 ');
    }

    final out = <Map<String, dynamic>>[];
    var run = <Map<String, dynamic>>[];
    void flushRun() {
      if (run.length < threshold) {
        out.addAll(run);
      } else {
        final names = <String>[];
        for (final m in run) {
          names.addAll(_toolCallNames(m['tool_calls']));
        }
        out.add({
          'role': 'assistant',
          'content': '🔧 ${run.length} tool calls (${names.join(', ')})',
          'folded_tool_calls': true,
          'folded_count': run.length,
          'folded_tools': names,
        });
      }
      run = <Map<String, dynamic>>[];
    }

    for (final m in messages) {
      if (isToolLabelBubble(m)) {
        run.add(m);
      } else {
        flushRun();
        out.add(m);
      }
    }
    flushRun();
    return out;
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
  ///
  /// Hermes injects these as a `role: user` turn when a previous context
  /// window is rolled forward; the message body declares its own nature
  /// ("[CONTEXT COMPACTION — REFERENCE ONLY]" / "END OF CONTEXT SUMMARY")
  /// rather than living in a `role: system` slot, so we have to match the
  /// content rather than the role. System messages also match via the same
  /// content markers, but we keep a few role-system-only phrase markers for
  /// backwards compatibility with older sessions.
  static bool _isContextCompression(
    String role,
    String content,
    Map<String, dynamic> msg,
  ) {
    // Content markers that appear on the injected handoff message regardless
    // of role. The two anchors ("CONTEXT COMPACTION" preamble and
    // "END OF CONTEXT SUMMARY" delimiter) together form a tight signature that
    // is never produced by ordinary conversation.
    const contentMarkers = [
      '[CONTEXT COMPACTION',
      'CONTEXT COMPACTION — REFERENCE',
      '— REFERENCE ONLY]',
      'END OF CONTEXT SUMMARY',
      'Historical Task Snapshot', // header inside the compaction handoff
      'Historical In-Progress State',
      'Historical Pending User Asks',
      'Historical Remaining Work',
    ];
    final lowerContent = content.toLowerCase();
    int hits = 0;
    for (final marker in contentMarkers) {
      if (lowerContent.contains(marker.toLowerCase())) hits++;
    }
    // Need at least two marker hits so legitimate user/assistant prose that
    // mentions "compaction" in passing doesn't get dropped.
    if (hits >= 2) return true;

    // Phrase markers — only meaningful for system messages.
    if (role == 'system') {
      const phraseMarkers = [
        'context compress',
        'context compression',
        'conversation summary',
        'context window',
        'summary of previous',
        'compacted conversation',
        'truncated conversation',
        'previous messages were compressed',
      ];
      for (final marker in phraseMarkers) {
        if (lowerContent.contains(marker)) return true;
      }
    }

    // Explicit metadata flags (any role)
    if (msg['type'] == 'compression' ||
        msg['type'] == 'context_compress' ||
        msg['metadata']?['compressed'] == true) {
      return true;
    }

    return false;
  }
}
