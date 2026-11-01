
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  runApp(const SmartKeyboardApp());
}

class SmartKeyboardApp extends StatelessWidget {
  const SmartKeyboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Glass Keyboard',
      theme: ThemeData.dark(),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _textController = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _arabic = true;
  bool _dark = true;
  bool _micOn = false;
  bool _ready = false;
  bool _listening = false;

  String _apiKey = '';
  List<String> _predictions = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initVoice();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString('gemini_key') ?? '';
    _dark = prefs.getBool('dark_mode') ?? true;
    setState(() {});
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_key', _apiKey);
    await prefs.setBool('dark_mode', _dark);
  }

  Future<void> _initVoice() async {
    final ok = await _speech.initialize(
      onError: (error) {},
      onStatus: (status) {
        setState(() {
          _listening = status == 'listening';
        });
      },
    );
    if (ok) {
      await _tts.setLanguage('ar-SA');
      await _tts.setSpeechRate(0.52);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      setState(() => _ready = true);
    }
  }

  Future<void> _startListening() async {
    if (!_ready) return;
    await _speech.listen(
      localeId: 'ar-SA',
      partialResults: true,
      onResult: (result) {
        if (result.finalResult) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            _insertText(words);
          }
        }
      },
      onError: (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mic error: ${error.errorMsg ?? "unknown"}')),
        );
      },
    );
    setState(() => _micOn = true);
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() => _micOn = false);
  }

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;
    await _tts.speak(text);
  }

  Future<void> _insertText(String value) {
    final text = _textController.text;
    final offset = _textController.selection.baseOffset;
    final safeOffset = offset < 0 ? 0 : offset;
    final before = text.substring(0, safeOffset.clamp(0, text.length));
    final after = text.substring(safeOffset.clamp(0, text.length));
    final next = before + value + after;
    _textController.text = next;
    _textController.selection = TextSelection.collapsed(
      offset: safeOffset + value.length,
    );
    _updatePrediction();
    return Future.value();
  }

  Future<void> _updatePrediction() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _predictions = []);
      return;
    }
    if (_apiKey.isEmpty) {
      setState(() => _predictions = ['Add Gemini Key']);
      return;
    }
    final result = await _predictNextWord(text);
    final clean = result.replaceAll(RegExp(r'[\n\r]'), '').trim();
    if (clean.isEmpty || clean.length > 18) {
      setState(() => _predictions = []);
      return;
    }
    setState(() => _predictions = [clean]);
  }

  Future<String> _predictNextWord(String context) async {
    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_apiKey',
      );
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {'parts': [{'text': 'Predict the next word only from this context: "$context". Return the word only.'}]}
          ],
          'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 80}
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
        return text?.toString() ?? '';
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _correctText() async {
    if (_apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter Gemini key first')),
      );
      return;
    }
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final result = await _callGemini(
      'Correct grammar and spelling only. Return the text only without explanation: "$text"',
    );
    if (result.isNotEmpty) {
      _textController.text = result;
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textController.text.length),
      );
    }
  }

  Future<String> _callGemini(String prompt) async {
    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_apiKey',
      );
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {'parts': [{'text': prompt}]}
          ],
          'generationConfig': {
            'temperature': 0.7,
            'maxOutputTokens': 512,
          }
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
        return text?.toString() ?? '';
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _showApiDialog() async {
    final controller = TextEditingController(text: _apiKey);
    final result = await showDialog<String>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Gemini API Key'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Enter Gemini Key',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (result != null && result.trim().isNotEmpty) {
      _apiKey = result.trim();
      await _saveSettings();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gemini key saved')),
      );
    }
  }

  void _keyPress(String key) {
    if (key == 'BACKSPACE') {
      final text = _textController.text;
      final pos = _textController.selection.baseOffset;
      if (pos > 0 && pos <= text.length) {
        final before = text.substring(0, pos - 1);
        final after = text.substring(pos);
        _textController.text = before + after;
        _textController.selection = TextSelection.collapsed(offset: pos - 1);
      }
    } else if (key == 'SPACE') {
      _insertText(' ');
    } else if (key == 'ENTER') {
      _insertText('\n');
    } else {
      _insertText(key);
    }
    _updatePrediction();
  }

  @override
  Widget build(BuildContext context) {
    final bg = _dark ? const Color(0xFF131B22) : const Color(0xFFF5EFE7);
    final panel = _dark ? const Color(0xCC1E2A33) : const Color(0x99F7F2EB);
    final keyTop = _dark ? const Color(0xFF495767) : const Color(0xFFFFFBF6);
    final keyBottom = _dark ? const Color(0xFF1D2730) : const Color(0xFFE9D8BA);
    final textColor = _dark ? Colors.white : Colors.black87;
    final accent = const Color(0xFF7E6DFF);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Smart Glass Keyboard'),
        backgroundColor: bg,
        foregroundColor: textColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.key),
            onPressed: _showApiDialog,
          ),
          IconButton(
            icon: Icon(_micOn ? Icons.mic_off : Icons.mic),
            onPressed: () async {
              if (_micOn) {
                await _stopListening();
              } else {
                await _startListening();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.volume_up),
            onPressed: () async {
              await _speak(_textController.text);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: panel,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: TextField(
                    controller: _textController,
                    maxLines: null,
                    expands: true,
                    style: TextStyle(color: textColor, fontSize: 22),
                    decoration: InputDecoration(
                      hintText: 'Type here...',
                      hintStyle: TextStyle(color: textColor.withOpacity(0.5)),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),
            if (_predictions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: panel,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: _predictions
                        .map(
                          (word) => Expanded(
                            child: GestureDetector(
                              onTap: () {
                                _insertText(word);
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF5CC9FF).withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF5CC9FF).withOpacity(0.5),
                                  ),
                                ),
                                child: Text(
                                  word,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFF5CC9FF),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                children: [
                  _buildKeyboardLayout(
                    keyTop: keyTop,
                    keyBottom: keyBottom,
                    textColor: textColor,
                    accent: accent,
                    dark: _dark,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _toggleButton(
                        title: _dark ? 'Dark' : 'Light',
                        icon: _dark ? Icons.dark_mode : Icons.light_mode,
                        onTap: () async {
                          setState(() => _dark = !_dark);
                          await _saveSettings();
                        },
                        accent: accent,
                      ),
                      const SizedBox(width: 10),
                      _toggleButton(
                        title: _arabic ? 'English' : 'Arabic',
                        icon: Icons.language,
                        onTap: () {
                          setState(() => _arabic = !_arabic);
                        },
                        accent: accent,
                      ),
                      const SizedBox(width: 10),
                      _toggleButton(
                        title: 'AI',
                        icon: Icons.smart_toy_outlined,
                        onTap: () async {
                          await _correctText();
                        },
                        accent: accent,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleButton({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    required Color accent,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withOpacity(0.8)),
        ),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 18),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF7E6DFF),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyboardLayout({
    required Color keyTop,
    required Color keyBottom,
    required Color textColor,
    required Color accent,
    required bool dark,
  }) {
    final numberRow = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
    final arabicTop = ['\u0636', '\u0635', '\u062b', '\u0642', '\u0641', '\u063a', '\u0639', '\u0647', '\u062e', '\u062d', '\u062c', '\u062f'];
    final arabicMid = ['\u0634', '\u0633', '\u064a', '\u0628', '\u0644', '\u0627', '\u062a', '\u0646', '\u0645', '\u0643', '\u0637'];
    final arabicLow = ['\u0626', '\u0621', '\u0624', '\u0631', '\u0644\u0627', '\u0649', '\u0629', '\u0648', '\u0632', '\u0638', '\u0630'];
    final englishTop = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
    final englishMid = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
    final englishLow = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];

    if (_arabic) {
      return Column(
        children: [
          Row(children: numberRow.map((n) => Expanded(child: _glassKey(n, keyTop, keyBottom, textColor, () => _keyPress(n)))).toList()),
          const SizedBox(height: 6),
          Row(children: arabicTop.map((k) => Expanded(child: _glassKey(k, keyTop, keyBottom, textColor, () => _keyPress(k)))).toList()),
          const SizedBox(height: 6),
          Row(children: arabicMid.map((k) => Expanded(child: _glassKey(k, keyTop, keyBottom, textColor, () => _keyPress(k)))).toList()),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _glassKey('\u21E7', keyTop, keyBottom, textColor, () => setState(() => {}), isSpecial: true)),
            ...arabicLow.map((k) => Expanded(child: _glassKey(k, keyTop, keyBottom, textColor, () => _keyPress(k)))),
            Expanded(child: _glassKey('\u232B', keyTop, keyBottom, textColor, () => _keyPress('BACKSPACE'), isSpecial: true)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _glassKey('123', keyTop, keyBottom, textColor, () {}, isSpecial: true)),
            Expanded(flex: 5, child: _glassKey('Space', keyTop, keyBottom, textColor, () => _keyPress('SPACE'))),
            Expanded(flex: 2, child: _glassKey('\u21B5', keyTop, keyBottom, textColor, () => _keyPress('ENTER'), isSpecial: true)),
          ]),
        ],
      );
    }

    return Column(
      children: [
        Row(children: numberRow.map((n) => Expanded(child: _glassKey(n, keyTop, keyBottom, textColor, () => _keyPress(n)))).toList()),
        const SizedBox(height: 6),
        Row(children: englishTop.map((k) => Expanded(child: _glassKey(k, keyTop, keyBottom, textColor, () => _keyPress(k)))).toList()),
        const SizedBox(height: 6),
        Row(children: englishMid.map((k) => Expanded(child: _glassKey(k, keyTop, keyBottom, textColor, () => _keyPress(k)))).toList()),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _glassKey('\u21E7', keyTop, keyBottom, textColor, () => setState(() => {}), isSpecial: true)),
          ...englishLow.map((k) => Expanded(child: _glassKey(k, keyTop, keyBottom, textColor, () => _keyPress(k)))),
          Expanded(child: _glassKey('\u232B', keyTop, keyBottom, textColor, () => _keyPress('BACKSPACE'), isSpecial: true)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _glassKey('123', keyTop, keyBottom, textColor, () {}, isSpecial: true)),
          Expanded(flex: 5, child: _glassKey('space', keyTop, keyBottom, textColor, () => _keyPress('SPACE'))),
          Expanded(flex: 2, child: _glassKey('\u21B5', keyTop, keyBottom, textColor, () => _keyPress('ENTER'), isSpecial: true)),
        ]),
      ],
    );
  }

  Widget _glassKey(
    String label,
    Color top,
    Color bottom,
    Color textColor,
    VoidCallback onTap, {
    bool isSpecial = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        height: 52,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: bottom.withOpacity(0.7),
              offset: const Offset(0, 6),
              blurRadius: 10,
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [top, top.withOpacity(0.94)],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: isSpecial ? 15 : 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
