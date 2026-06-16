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
        {'role': 'assistant', 'content': '', 'tool_calls': [
          {'id': 'call_1', 'type': 'function', 'function': {'name': 'read_file'}},
        ]},
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
        {'role': 'assistant', 'content': '<think>Internal reasoning here.</think>Here is the explanation of X.'},
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

    test('truncates to latest 10 messages', () {
      final messages = <Map<String, dynamic>>[];
      for (var i = 0; i < 20; i++) {
        messages.add({'role': i.isEven ? 'user' : 'assistant', 'content': 'Message $i'});
      }
      final result = MessageFilter.filterForDisplay(messages);
      expect(result.length, 10);
      expect(result.first['content'], 'Message 10');
      expect(result.last['content'], 'Message 19');
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
        {'role': 'assistant', 'content': '<think>I should explain my capabilities</think>I can help with many tasks.'},
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
