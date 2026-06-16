import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/utils/message_filter.dart';

void main() {
  group('MessageFilter.filterForDisplay', () {
    test('returns empty list for empty input', () {
      expect(MessageFilter.filterForDisplay([]), isEmpty);
    });

    test('keeps normal user and assistant messages', () {
      final messages = [
        {'role': 'user', 'content': 'Hello'},
        {'role': 'assistant', 'content': 'Hi there!'},
      ];
      final result = MessageFilter.filterForDisplay(messages);
      expect(result.length, 2);
      expect(result[0]['content'], 'Hello');
      expect(result[1]['content'], 'Hi there!');
    });

    test('keeps assistant tool-call messages even with empty content', () {
      final messages = [
        {'role': 'user', 'content': 'Read the file'},
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {'id': 'call_1', 'type': 'function', 'function': {'name': 'read_file'}},
          ],
        },
        {'role': 'tool', 'content': 'file contents here', 'tool_call_id': 'call_1'},
        {'role': 'assistant', 'content': 'The file says hello.'},
      ];
      final result = MessageFilter.filterForDisplay(messages);
      // tool-call assistant message is kept (has tool_calls)
      // and rendered with a tool-call label instead of empty content
      expect(result.length, 3);
      expect(result[0]['role'], 'user');
      expect(result[1]['role'], 'assistant');
      expect(result[1]['content'], '🔧 read_file');
      expect(result[1]['tool_calls'], isNotNull);
      expect(result[2]['content'], 'The file says hello.');
    });

    test('filters out tool result messages', () {
      final messages = [
        {'role': 'user', 'content': 'question'},
        {'role': 'tool', 'content': 'result data', 'tool_call_id': 'c1'},
        {'role': 'assistant', 'content': 'answer'},
      ];
      final result = MessageFilter.filterForDisplay(messages);
      expect(result.length, 2);
      expect(result[0]['role'], 'user');
      expect(result[1]['content'], 'answer');
    });

    test('filters out messages with tool_call_id regardless of role', () {
      final messages = [
        {'role': 'user', 'content': 'question'},
        {'role': 'assistant', 'content': 'tool output', 'tool_call_id': 'call_42'},
        {'role': 'assistant', 'content': 'real answer'},
      ];
      final result = MessageFilter.filterForDisplay(messages);
      expect(result.length, 2);
      expect(result[0]['content'], 'question');
      expect(result[1]['content'], 'real answer');
    });

    test('filters out empty messages', () {
      final messages = [
        {'role': 'user', 'content': ''},
        {'role': 'assistant', 'content': null},
        {'role': 'user', 'content': '   '},
        {'role': 'assistant', 'content': 'valid reply'},
      ];
      final result = MessageFilter.filterForDisplay(messages);
      expect(result.length, 1);
      expect(result[0]['content'], 'valid reply');
    });

    test('filters out pure thinking/reasoning messages', () {
      final messages = [
        {'role': 'user', 'content': 'What is 2+2?'},
        {'role': 'assistant', 'content': '<think>Let me calculate... 2 plus 2 is 4.</think>'},
        {'role': 'assistant', 'content': '2 + 2 = 4'},
      ];
      final result = MessageFilter.filterForDisplay(messages);
      expect(result.length, 2);
      expect(result[0]['content'], 'What is 2+2?');
      expect(result[1]['content'], '2 + 2 = 4');
    });

    test('filters out unclosed think tags (streaming artifacts)', () {
      final messages = [
        {'role': 'user', 'content': 'Hi'},
        {'role': 'assistant', 'content': '<think>reasoning in progress'},
        {'role': 'assistant', 'content': 'Hello!'},
      ];
      final result = MessageFilter.filterForDisplay(messages);
      expect(result.length, 2);
      expect(result[1]['content'], 'Hello!');
    });

    test('strips think blocks from mixed content', () {
      final messages = [
        {'role': 'user', 'content': 'Explain X'},
        {
          'role': 'assistant',
          'content': '<think>Internal reasoning here.</think>Here is the explanation of X.',
        },
      ];
      final result = MessageFilter.filterForDisplay(messages);
      expect(result.length, 2);
      expect(result[1]['content'], 'Here is the explanation of X.');
    });

    test('filters out context compression system messages', () {
      final messages = [
        {'role': 'system', 'content': 'Context compression: previous 50 messages were summarized.'},
        {'role': 'user', 'content': 'Continue our discussion'},
        {'role': 'assistant', 'content': 'Sure!'},
      ];
      final result = MessageFilter.filterForDisplay(messages);
      expect(result.length, 2);
    });

    test('filters out messages with compression metadata', () {
      final messages = [
        {'role': 'system', 'content': 'Previous messages summary', 'type': 'compression'},
        {'role': 'user', 'content': 'Hello'},
        {'role': 'assistant', 'content': 'Hi'},
      ];
      final result = MessageFilter.filterForDisplay(messages);
      expect(result.length, 2);
    });

    // ── New: context compaction injected as user role ──

    test('filters out [CONTEXT COMPACTION] injected as user role', () {
      final compactionBody =
          '[CONTEXT COMPACTION — REFERENCE ONLY] Earlier turns were compacted '
          'into the summary below.\n\n## Historical Task Snapshot\nDo something.\n\n'
          '--- END OF CONTEXT SUMMARY ---';
      final messages = [
        {'role': 'user', 'content': compactionBody},
        {'role': 'user', 'content': 'What is the weather?'},
        {'role': 'assistant', 'content': 'Sunny!'},
      ];
      final result = MessageFilter.filterForDisplay(messages);
      // Compaction handoff must be dropped; only real conversation survives.
      expect(result.length, 2);
      expect(result[0]['content'], 'What is the weather?');
      expect(result[1]['content'], 'Sunny!');
    });

    test('filters out [CONTEXT COMPACTION] injected as assistant role', () {
      final compactionBody =
          '[CONTEXT COMPACTION — REFERENCE ONLY] Summary of previous work.\n'
          '## Historical In-Progress State\nTask A in progress.\n'
          '--- END OF CONTEXT SUMMARY ---';
      final messages = [
        {'role': 'assistant', 'content': compactionBody},
        {'role': 'user', 'content': 'Continue'},
        {'role': 'assistant', 'content': 'OK'},
      ];
      final result = MessageFilter.filterForDisplay(messages);
      expect(result.length, 2);
    });

    test('does NOT drop normal messages mentioning "compaction" in passing', () {
      // Only one marker → below the 2-hit threshold → message kept.
      final messages = [
        {'role': 'user', 'content': 'What is context compression about?'},
        {'role': 'assistant', 'content': 'It reduces token usage.'},
      ];
      final result = MessageFilter.filterForDisplay(messages);
      expect(result.length, 2);
    });

    // ── New: tool-call label folding ──

    test('folds 3+ consecutive tool-call labels into a summary bubble', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'user', 'content': 'Fix the bug'},
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {'id': 'c1', 'type': 'function', 'function': {'name': 'read_file'}},
          ],
        },
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {'id': 'c2', 'type': 'function', 'function': {'name': 'patch'}},
          ],
        },
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {'id': 'c3', 'type': 'function', 'function': {'name': 'execute_code'}},
          ],
        },
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {'id': 'c4', 'type': 'function', 'function': {'name': 'patch'}},
          ],
        },
        {'role': 'assistant', 'content': 'Done!'},
      ];
      final result = MessageFilter.filterForDisplay(messages, maxMessages: 100);
      // user(1) + folded(1) + assistant text(1) = 3
      expect(result.length, 3);
      expect(result[1]['content'], '🔧 4 tool calls (read_file, patch, execute_code, patch)');
      expect(result[1]['folded_tool_calls'], isTrue);
      expect(result[1]['folded_count'], 4);
    });

    test('does NOT fold when only 1-2 consecutive tool-call labels', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'user', 'content': 'Read it'},
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {'id': 'c1', 'type': 'function', 'function': {'name': 'read_file'}},
          ],
        },
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {'id': 'c2', 'type': 'function', 'function': {'name': 'patch'}},
          ],
        },
        {'role': 'assistant', 'content': 'All done.'},
      ];
      final result = MessageFilter.filterForDisplay(messages, maxMessages: 100);
      // user(1) + tool1(1) + tool2(1) + assistant text(1) = 4
      expect(result.length, 4);
      expect(result[1]['content'], '🔧 read_file');
      expect(result[2]['content'], '🔧 patch');
    });

    test('folds separately when tool groups are interrupted by text', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'user', 'content': 'Do stuff'},
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {'id': 'c1', 'type': 'function', 'function': {'name': 'read_file'}},
          ],
        },
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {'id': 'c2', 'type': 'function', 'function': {'name': 'patch'}},
          ],
        },
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {'id': 'c3', 'type': 'function', 'function': {'name': 'read_file'}},
          ],
        },
        {'role': 'assistant', 'content': 'Let me verify...'},
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {'id': 'c4', 'type': 'function', 'function': {'name': 'execute_code'}},
          ],
        },
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {'id': 'c5', 'type': 'function', 'function': {'name': 'execute_code'}},
          ],
        },
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {'id': 'c6', 'type': 'function', 'function': {'name': 'execute_code'}},
          ],
        },
        {'role': 'assistant', 'content': 'Done!'},
      ];
      final result = MessageFilter.filterForDisplay(messages, maxMessages: 100);
      // user(1) + folded1(1, 3 tools) + text(1) + folded2(1, 3 tools) + text(1) = 5
      expect(result.length, 5);
      expect(result[1]['content'], '🔧 3 tool calls (read_file, patch, read_file)');
      expect(result[3]['content'], '🔧 3 tool calls (execute_code, execute_code, execute_code)');
    });

    test('handles JSON-string tool_calls in fold', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'user', 'content': 'Go'},
        {
          'role': 'assistant',
          'content': '',
          'tool_calls':
              '[{"id":"c1","type":"function","function":{"name":"terminal"}}]',
        },
        {
          'role': 'assistant',
          'content': '',
          'tool_calls':
              '[{"id":"c2","type":"function","function":{"name":"read_file"}}]',
        },
        {
          'role': 'assistant',
          'content': '',
          'tool_calls':
              '[{"id":"c3","type":"function","function":{"name":"patch"}}]',
        },
        {'role': 'assistant', 'content': 'Finished.'},
      ];
      final result = MessageFilter.filterForDisplay(messages, maxMessages: 100);
      expect(result.length, 3);
      expect(result[1]['content'], '🔧 3 tool calls (terminal, read_file, patch)');
    });

    // ── Updated: defaultMaxMessages is now 30 ──

    test('truncates to latest 30 messages by default', () {
      final messages = <Map<String, dynamic>>[];
      for (var i = 0; i < 50; i++) {
        messages.add({'role': i.isEven ? 'user' : 'assistant', 'content': 'Message $i'});
      }
      final result = MessageFilter.filterForDisplay(messages);
      expect(result.length, 30);
      expect(result.first['content'], 'Message 20');
      expect(result.last['content'], 'Message 49');
    });

    test('respects custom maxMessages parameter', () {
      final messages = <Map<String, dynamic>>[];
      for (var i = 0; i < 10; i++) {
        messages.add({'role': 'user', 'content': 'Msg $i'});
      }
      final result = MessageFilter.filterForDisplay(messages, maxMessages: 3);
      expect(result.length, 3);
      expect(result[0]['content'], 'Msg 7');
      expect(result[2]['content'], 'Msg 9');
    });

    test('handles complex mixed scenario', () {
      final messages = [
        {'role': 'system', 'content': 'Context compression applied'},
        {'role': 'user', 'content': ''},
        {'role': 'tool', 'content': 'result', 'tool_call_id': 'c1'},
        {'role': 'assistant', 'content': '<think>hmm</think>'},
        {'role': 'user', 'content': 'What can you do?'},
        {
          'role': 'assistant',
          'content': '<think>I should explain my capabilities</think>I can help with many tasks.',
        },
        {'role': 'tool', 'content': 'another result', 'tool_call_id': 'c2'},
        {'role': 'assistant', 'content': ''},
        {'role': 'user', 'content': 'Thanks!'},
        {'role': 'assistant', 'content': 'You are welcome!'},
      ];
      final result = MessageFilter.filterForDisplay(messages);
      // Should keep: user "What can you do?", assistant cleaned, user "Thanks!", assistant "You are welcome!"
      expect(result.length, 4);
      expect(result[0]['content'], 'What can you do?');
      expect(result[1]['content'], 'I can help with many tasks.');
      expect(result[2]['content'], 'Thanks!');
      expect(result[3]['content'], 'You are welcome!');
    });

    test('preserves metadata fields on kept messages', () {
      final messages = [
        {'role': 'assistant', 'content': 'Hello', 'model': 'gpt-4', 'id': 'msg_1'},
      ];
      final result = MessageFilter.filterForDisplay(messages);
      expect(result.length, 1);
      expect(result[0]['model'], 'gpt-4');
      expect(result[0]['id'], 'msg_1');
    });

    test('filters tool_progress role messages', () {
      final messages = [
        {'role': 'user', 'content': 'Do something'},
        {'role': 'tool_progress', 'content': '🔧 read_file — running', 'toolCallId': 'tc1'},
        {'role': 'tool_progress', 'content': '🔧 read_file — done', 'toolCallId': 'tc1'},
        {'role': 'assistant', 'content': 'Done!'},
      ];
      final result = MessageFilter.filterForDisplay(messages);
      expect(result.length, 2);
      expect(result[0]['role'], 'user');
      expect(result[1]['role'], 'assistant');
    });
  });
}
